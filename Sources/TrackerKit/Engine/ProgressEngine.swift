import Foundation

// MARK: - ProgressSnapshot

/// What one tracker did in one period, scored against the goal that actually
/// governed that period.
public struct ProgressSnapshot: Identifiable, Sendable, Hashable {
    public let trackerID: UUID
    public let period: Period
    /// The goal in force for this period, or `nil` if the tracker had no goal yet.
    /// A `nil` goal means unscored, **not** zero — history before a goal existed
    /// is still real data, it just can't be graded.
    public let goal: GoalVersion?
    /// Aggregated value for the period.
    public let actual: Double
    /// Number of entries that rolled up into `actual`.
    public let entryCount: Int
    /// How far through the period we were when this was computed, 0...1.
    public let paceFraction: Double
    public let status: StoplightStatus

    public var id: String { "\(trackerID.uuidString)-\(period.start.timeIntervalSince1970)" }

    public var target: Double? { goal?.target }
    public var unit: String { goal?.unit ?? "" }
    public var direction: GoalDirection { goal?.direction ?? .atLeast }

    /// Completion as a share of target, uncapped so overachievement is visible.
    /// `nil` when there is no goal.
    public var fraction: Double? {
        guard let target, target != 0 else { return nil }
        return actual / target
    }

    /// Completion clamped to 0...1, for rings and bars that can't overflow.
    public var clampedFraction: Double {
        guard let fraction else { return 0 }
        return min(max(fraction, 0), 1)
    }

    /// Whether the goal is satisfied as of now.
    public var isMet: Bool {
        guard let target else { return false }
        return direction.isSatisfied(value: actual, target: target)
    }

    /// Value still needed to satisfy an `.atLeast` goal, or headroom left on an
    /// `.atMost` one. Zero once satisfied.
    public var remaining: Double {
        guard let target else { return 0 }
        switch direction {
        case .atLeast: return max(0, target - actual)
        case .atMost: return max(0, target - actual)
        case .exactly: return target - actual
        }
    }

    public var isPeriodComplete: Bool { paceFraction >= 0.999 }

    /// True when this is an `.atMost` goal whose ceiling has been exceeded.
    ///
    /// Progress visuals key off this to avoid the "full bar means success"
    /// assumption, which is exactly backwards for a limit.
    public var breachesLimit: Bool {
        guard direction == .atMost, let target else { return false }
        return actual > target
    }
}

// MARK: - ProgressEngine

/// Rolls entries up into scored periods.
///
/// Pure and `Sendable` — no SwiftData, no SwiftUI — so it can run off the main
/// actor, be unit-tested against fixed dates, and be reused by the widget
/// extension without dragging the store along.
public struct ProgressEngine: Sendable {
    public var calculator: PeriodCalculator
    public var stoplight: StoplightEngine

    public init(
        calculator: PeriodCalculator = PeriodCalculator(),
        stoplight: StoplightEngine = .standard
    ) {
        self.calculator = calculator
        self.stoplight = stoplight
    }

    // MARK: Goal resolution

    /// Which goal version governs `period`.
    ///
    /// The rule, stated once so every view agrees:
    /// - For a **past** period, the goal that was in force when the period began.
    ///   That is what makes old charts honest — last month is graded against last
    ///   month's target, not today's.
    /// - For the **current** period, the goal in force right now, so raising a
    ///   target takes effect immediately instead of next week.
    public func governingGoal(for tracker: Tracker, period: Period, now: Date = .now) -> GoalVersion? {
        if period.contains(now) {
            return tracker.goal(on: now)
        }
        return tracker.goal(on: period.start)
    }

    // MARK: Aggregation

    /// Rolls the entries falling inside `interval` into a single number.
    public func aggregate(
        entries: [Entry],
        in interval: DateInterval,
        using aggregation: Aggregation
    ) -> (value: Double, count: Int) {
        let matching = entries
            .filter { $0.date >= interval.start && $0.date < interval.end }
            .sorted { $0.date < $1.date }
        guard !matching.isEmpty else { return (0, 0) }
        return (aggregation.apply(to: matching.map(\.value)), matching.count)
    }

    // MARK: Snapshots

    /// Scores one tracker for one period.
    public func snapshot(
        tracker: Tracker,
        entries: [Entry],
        period: Period,
        now: Date = .now
    ) -> ProgressSnapshot {
        let goal = governingGoal(for: tracker, period: period, now: now)
        let aggregation = goal?.aggregation ?? tracker.kind.defaultAggregation
        let rolled = aggregate(entries: entries, in: period.interval, using: aggregation)
        let pace = calculator.fractionElapsed(of: period, at: now)

        let status = stoplight.status(
            actual: rolled.value,
            target: goal?.target,
            direction: goal?.direction ?? .atLeast,
            cadence: period.cadence,
            paceFraction: pace
        )

        return ProgressSnapshot(
            trackerID: tracker.id,
            period: period,
            goal: goal,
            actual: rolled.value,
            entryCount: rolled.count,
            paceFraction: pace,
            status: status
        )
    }

    /// Scores the tracker's *current* window, at its own goal's cadence.
    /// Falls back to a daily window when the tracker has no goal.
    public func currentSnapshot(
        tracker: Tracker,
        entries: [Entry],
        now: Date = .now
    ) -> ProgressSnapshot {
        let cadence = tracker.goal(on: now)?.cadence ?? .daily
        let period = calculator.period(for: cadence, containing: now, anchor: tracker.createdAt)
        return snapshot(tracker: tracker, entries: entries, period: period, now: now)
    }

    /// Scores a run of consecutive periods, oldest first — the backing data for
    /// every time-series chart in the library.
    ///
    /// Bucketed with a single ordered sweep rather than filtering the whole entry
    /// array once per period. The naive version is O(periods × entries) and it
    /// shows: 180 daily periods over a year of entries is millions of comparisons
    /// on every SwiftUI body pass, which is the difference between a dashboard
    /// that appears and one that arrives ten seconds later.
    public func history(
        tracker: Tracker,
        entries: [Entry],
        periodCount: Int,
        cadence: Cadence? = nil,
        endingAt end: Date = .now
    ) -> [ProgressSnapshot] {
        let resolved = cadence ?? tracker.goal(on: end)?.cadence ?? .daily
        let periods = calculator.trailingPeriods(periodCount, cadence: resolved, endingAt: end)
        guard !periods.isEmpty else { return [] }

        let sorted = entries.sorted { $0.date < $1.date }
        var cursor = 0

        // Periods are contiguous and ascending, so one pointer walks the entries
        // exactly once across the whole run.
        return periods.map { period in
            while cursor < sorted.count, sorted[cursor].date < period.interval.start {
                cursor += 1
            }
            var bucket: [Double] = []
            var scan = cursor
            while scan < sorted.count, sorted[scan].date < period.interval.end {
                bucket.append(sorted[scan].value)
                scan += 1
            }

            let goal = governingGoal(for: tracker, period: period, now: end)
            let aggregation = goal?.aggregation ?? tracker.kind.defaultAggregation
            let pace = calculator.fractionElapsed(of: period, at: end)
            let value = bucket.isEmpty ? 0 : aggregation.apply(to: bucket)

            return ProgressSnapshot(
                trackerID: tracker.id,
                period: period,
                goal: goal,
                actual: value,
                entryCount: bucket.count,
                paceFraction: pace,
                status: stoplight.status(
                    actual: value,
                    target: goal?.target,
                    direction: goal?.direction ?? .atLeast,
                    cadence: period.cadence,
                    paceFraction: pace
                )
            )
        }
    }

    /// Daily values for a tracker over a trailing window. Used by sparklines,
    /// heatmaps and the stacked-bar composition.
    public func dailyValues(
        tracker: Tracker,
        entries: [Entry],
        dayCount: Int,
        endingAt end: Date = .now
    ) -> [DailyValue] {
        let aggregation = tracker.goal(on: end)?.aggregation ?? tracker.kind.defaultAggregation
        let days = calculator.trailingDays(dayCount, endingAt: end)
        // Bucket once instead of filtering the whole array per day.
        var buckets: [Date: [Double]] = [:]
        for entry in entries {
            let day = calculator.startOfDay(entry.date)
            buckets[day, default: []].append(entry.value)
        }
        return days.map { day in
            let values = buckets[day] ?? []
            return DailyValue(
                date: day,
                value: values.isEmpty ? 0 : aggregation.apply(to: values),
                entryCount: values.count
            )
        }
    }

    /// Totals across several trackers for one period — the input to a stacked bar.
    public func composition(
        trackers: [Tracker],
        entriesByTracker: [UUID: [Entry]],
        period: Period,
        now: Date = .now
    ) -> [ProgressSnapshot] {
        trackers.map { tracker in
            snapshot(
                tracker: tracker,
                entries: entriesByTracker[tracker.id] ?? [],
                period: period,
                now: now
            )
        }
    }

    /// The single worst status across a set of trackers — what a parent needs to
    /// see on a profile tile without opening anything.
    public func worstStatus(_ snapshots: [ProgressSnapshot]) -> StoplightStatus {
        let scored = snapshots.map(\.status).filter { $0 != .neutral }
        guard !scored.isEmpty else { return .neutral }
        return scored.max() ?? .neutral
    }

    /// Share of scored trackers currently sitting green, 0...1.
    public func greenShare(_ snapshots: [ProgressSnapshot]) -> Double {
        let scored = snapshots.filter { $0.status != .neutral }
        guard !scored.isEmpty else { return 0 }
        let green = scored.filter { $0.status == .green }.count
        return Double(green) / Double(scored.count)
    }
}

// MARK: - DailyValue

/// One day's rolled-up value for a tracker.
public struct DailyValue: Identifiable, Sendable, Hashable {
    public let date: Date
    public let value: Double
    public let entryCount: Int

    public var id: Date { date }
    public var hasData: Bool { entryCount > 0 }

    public init(date: Date, value: Double, entryCount: Int) {
        self.date = date
        self.value = value
        self.entryCount = entryCount
    }
}
