import Foundation

// MARK: - Trend

/// Movement between two comparable windows.
public struct Trend: Sendable, Hashable {
    public let current: Double
    public let previous: Double
    public let absoluteChange: Double
    /// Relative change. `nil` when the previous value was zero — "up from nothing"
    /// is not a percentage, and printing ∞% is how dashboards lose trust.
    public let changeFraction: Double?
    public let direction: TrendDirection

    public init(current: Double, previous: Double, flatThreshold: Double = 0.02) {
        self.current = current
        self.previous = previous
        self.absoluteChange = current - previous

        if previous == 0 {
            self.changeFraction = nil
        } else {
            self.changeFraction = (current - previous) / abs(previous)
        }

        let relative = previous == 0
            ? (current == 0 ? 0 : 1)
            : (current - previous) / abs(previous)

        if abs(relative) < flatThreshold {
            self.direction = .flat
        } else {
            self.direction = relative > 0 ? .rising : .falling
        }
    }

    /// Whether the movement is good news, which depends entirely on the goal.
    /// More workouts: good. More cigarettes: not.
    public func isFavorable(for goalDirection: GoalDirection) -> Bool {
        direction.isFavorable(for: goalDirection)
    }

    /// "+12%" / "−4%" / "+3" when there's no usable base.
    public func displayText(unit: String = "") -> String {
        if let changeFraction {
            return Formatters.signedPercent(changeFraction)
        }
        if absoluteChange == 0 { return "No change" }
        let sign = absoluteChange > 0 ? "+" : "\u{2212}"
        return "\(sign)\(Formatters.value(abs(absoluteChange), unit: unit))"
    }
}

// MARK: - TrendEngine

/// Period-over-period comparison, smoothing and projection.
public struct TrendEngine: Sendable {
    public var calculator: PeriodCalculator

    public init(calculator: PeriodCalculator = PeriodCalculator()) {
        self.calculator = calculator
    }

    /// Compares the last two snapshots in a history run.
    ///
    /// The final snapshot is usually a period still in flight, so comparing it
    /// raw against a finished one always reads as a decline. When `prorate` is on
    /// (the default) the previous period is scaled to the same share of elapsed
    /// time — a like-for-like comparison.
    public func trend(from history: [ProgressSnapshot], prorate: Bool = true) -> Trend? {
        guard history.count >= 2,
              let latest = history.last
        else { return nil }
        let earlier = history[history.count - 2]

        let comparisonBase: Double
        if prorate && !latest.isPeriodComplete && latest.paceFraction > 0.05 {
            comparisonBase = earlier.actual * latest.paceFraction
        } else {
            comparisonBase = earlier.actual
        }

        return Trend(current: latest.actual, previous: comparisonBase)
    }

    /// Simple comparison of two numbers.
    public func trend(current: Double, previous: Double) -> Trend {
        Trend(current: current, previous: previous)
    }

    /// Trailing moving average, same length as the input. Leading positions
    /// average over however many values exist so the line starts at x₀ rather than
    /// hanging in space.
    public func movingAverage(_ values: [Double], window: Int) -> [Double] {
        guard window > 1, !values.isEmpty else { return values }
        return values.indices.map { index in
            let lower = max(0, index - window + 1)
            let slice = values[lower...index]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    /// Where the current period lands if the present pace holds.
    ///
    /// Returns `nil` before enough of the period has elapsed to extrapolate from —
    /// a projection off 4% of a week is noise dressed as insight.
    public func projectedTotal(for snapshot: ProgressSnapshot, minimumPace: Double = 0.15) -> Double? {
        guard !snapshot.isPeriodComplete,
              snapshot.paceFraction >= minimumPace,
              snapshot.paceFraction > 0
        else { return nil }
        return snapshot.actual / snapshot.paceFraction
    }

    /// Least-squares slope and intercept over evenly spaced values.
    /// Slope is per index step; positive means climbing.
    public func linearFit(_ values: [Double]) -> (slope: Double, intercept: Double)? {
        let count = Double(values.count)
        guard values.count >= 2 else { return nil }

        let indices = values.indices.map(Double.init)
        let meanX = indices.reduce(0, +) / count
        let meanY = values.reduce(0, +) / count

        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(indices, values) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator != 0 else { return nil }

        let slope = numerator / denominator
        return (slope, meanY - slope * meanX)
    }

    /// Fitted trend line values, for overlaying on a series.
    public func trendLine(_ values: [Double]) -> [Double] {
        guard let fit = linearFit(values) else { return values }
        return values.indices.map { fit.intercept + fit.slope * Double($0) }
    }

    /// Best and worst periods in a run, for the report's callouts.
    public func extremes(_ history: [ProgressSnapshot]) -> (best: ProgressSnapshot?, worst: ProgressSnapshot?) {
        let scored = history.filter { $0.entryCount > 0 }
        guard !scored.isEmpty else { return (nil, nil) }
        return (
            scored.max { $0.actual < $1.actual },
            scored.min { $0.actual < $1.actual }
        )
    }

    /// Share of completed periods whose goal was met, 0...1.
    public func consistency(_ history: [ProgressSnapshot]) -> Double {
        let completed = history.filter { $0.isPeriodComplete && $0.goal != nil }
        guard !completed.isEmpty else { return 0 }
        return Double(completed.filter(\.isMet).count) / Double(completed.count)
    }
}
