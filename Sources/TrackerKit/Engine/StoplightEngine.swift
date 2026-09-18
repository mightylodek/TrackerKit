import Foundation

/// Turns a number into a traffic light.
///
/// The judgment is **pace-aware**, which is the whole point: zero of five
/// workouts on Monday is fine, and the same zero on Saturday is not. A naive
/// `actual / target` would paint both red and train the user to ignore the color.
///
/// Thresholds are tunable because "at risk" means different things for a kid's
/// reading habit and a sales number.
public struct StoplightEngine: Sendable, Hashable {

    /// Above this share of the paced expectation, progress reads green.
    public var greenFloor: Double
    /// Above this share it reads yellow; below it, red.
    public var yellowFloor: Double
    /// Slack allowed on an `.atMost` goal before it stops reading green,
    /// as a share of the total allowance.
    public var atMostSlack: Double
    /// Relative band around an `.exactly` target that still counts as on it.
    public var exactlyTolerance: Double

    /// The opening stretch of a period where nothing is graded.
    ///
    /// Real habits are not uniformly distributed through a week. Somebody who
    /// works out Wednesday, Friday and Sunday is not "behind" on Monday morning,
    /// and a light that says otherwise gets ignored within a week — at which
    /// point every light is decoration.
    public var gracePace: Double

    /// Minimum expected amount before a shortfall counts as being behind.
    ///
    /// Guards discrete targets from absurd fractional expectations. One day into
    /// a 5-workouts-a-week goal, strict pacing expects 0.7 workouts and calls you
    /// behind for not having done most of one. You cannot do most of a workout.
    public var minimumExpectation: Double

    public init(
        greenFloor: Double = 0.85,
        yellowFloor: Double = 0.6,
        atMostSlack: Double = 0.1,
        exactlyTolerance: Double = 0.15,
        gracePace: Double = 0.25,
        minimumExpectation: Double = 1
    ) {
        self.greenFloor = greenFloor
        self.yellowFloor = yellowFloor
        self.atMostSlack = atMostSlack
        self.exactlyTolerance = exactlyTolerance
        self.gracePace = gracePace
        self.minimumExpectation = minimumExpectation
    }

    public static let standard = StoplightEngine()

    /// A stricter light for goals that matter more — narrower green band, and it
    /// starts grading almost immediately.
    public static let strict = StoplightEngine(
        greenFloor: 0.95, yellowFloor: 0.8, gracePace: 0.1
    )

    /// A forgiving light, good for kids' habits where red should be rare.
    public static let lenient = StoplightEngine(
        greenFloor: 0.7, yellowFloor: 0.4, gracePace: 0.4
    )

    /// Rates `actual` against `target`.
    ///
    /// - Parameters:
    ///   - paceFraction: how far through the period we are, 0...1. At 1 the period
    ///     is over and the verdict is final.
    ///   - cadence: `.total` goals have no deadline, so they are green when met
    ///     and `.neutral` otherwise — there is no such thing as "behind" without
    ///     a date to be behind against.
    public func status(
        actual: Double,
        target: Double?,
        direction: GoalDirection,
        cadence: Cadence,
        paceFraction: Double
    ) -> StoplightStatus {
        guard let target, target > 0 || direction == .atMost else { return .neutral }
        guard target != 0 || direction != .atLeast else { return .neutral }

        if cadence == .total {
            return direction.isSatisfied(value: actual, target: target) ? .green : .neutral
        }

        let pace = min(max(paceFraction.isFinite ? paceFraction : 0, 0), 1)
        let periodIsOver = pace >= 0.999

        switch direction {
        case .atLeast:
            if actual >= target { return .green }
            if periodIsOver { return .red }

            // Early in the period, and before a whole unit is even expected,
            // there is nothing to be behind on.
            guard pace > gracePace else { return .green }
            let expected = target * pace
            guard expected >= minimumExpectation else { return .green }

            let ratio = actual / expected
            if ratio >= greenFloor { return .green }
            if ratio >= yellowFloor { return .yellow }
            return .red

        case .atMost:
            guard target > 0 else {
                // A zero allowance: any usage at all is a miss.
                return actual <= 0 ? .green : .red
            }
            if actual > target { return .red }
            if periodIsOver { return .green }
            let consumed = actual / target
            if consumed <= pace + atMostSlack { return .green }
            if consumed <= pace + atMostSlack + 0.15 { return .yellow }
            return .red

        case .exactly:
            if periodIsOver {
                return direction.isSatisfied(value: actual, target: target) ? .green : .red
            }
            guard pace > gracePace else { return .green }
            let expected = target * pace
            guard expected >= minimumExpectation else { return .green }
            let drift = abs(actual - expected) / max(expected, 0.0001)
            if drift <= exactlyTolerance { return .green }
            if drift <= exactlyTolerance * 2 { return .yellow }
            return .red
        }
    }

    /// One-line reason for the light, shown under a stoplight badge. Written to be
    /// actionable — a color with no "so what" is decoration.
    public func explanation(
        status: StoplightStatus,
        actual: Double,
        target: Double?,
        direction: GoalDirection,
        unit: String,
        daysRemaining: Int
    ) -> String {
        guard let target else { return "No goal set" }
        let remaining = max(0, target - actual)

        switch (status, direction) {
        case (.neutral, _):
            return "Not enough data yet"

        case (.green, .atLeast):
            if actual >= target { return "Goal met" }
            return daysRemaining > 0
                ? "On pace — \(Formatters.value(remaining, unit: unit)) to go"
                : "On pace"
        case (.yellow, .atLeast):
            return daysRemaining > 0
                ? "\(Formatters.value(remaining, unit: unit)) in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s")"
                : "Short by \(Formatters.value(remaining, unit: unit))"
        case (.red, .atLeast):
            return daysRemaining > 0
                ? "Behind — needs \(Formatters.value(remaining, unit: unit)) in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s")"
                : "Missed by \(Formatters.value(remaining, unit: unit))"

        case (.green, .atMost):
            return "Under the limit — \(Formatters.value(max(0, target - actual), unit: unit)) left"
        case (.yellow, .atMost):
            return "Burning the limit early"
        case (.red, .atMost):
            return actual > target
                ? "Over by \(Formatters.value(actual - target, unit: unit))"
                : "Well ahead of the limit"

        case (.green, .exactly):
            return "On target"
        case (.yellow, .exactly):
            return "Drifting off target"
        case (.red, .exactly):
            return "Off target by \(Formatters.value(abs(actual - target), unit: unit))"
        }
    }
}
