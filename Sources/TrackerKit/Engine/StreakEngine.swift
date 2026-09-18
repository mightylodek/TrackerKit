import Foundation

// MARK: - StreakSummary

/// The state of one streak.
public struct StreakSummary: Sendable, Hashable {
    /// Days (or periods) running up to now without a break.
    public let current: Int
    /// Best run ever recorded.
    public let longest: Int
    /// The most recent day that counted.
    public let lastActiveDay: Date?
    /// Whether today already counts.
    public let isActiveToday: Bool
    /// The streak is alive but today hasn't been logged — log today or lose it.
    /// This is the flag a "don't break the chain" nudge should fire on.
    public let isAtRisk: Bool
    /// Total number of qualifying days, streak or not.
    public let totalActiveDays: Int

    public init(
        current: Int,
        longest: Int,
        lastActiveDay: Date?,
        isActiveToday: Bool,
        isAtRisk: Bool,
        totalActiveDays: Int
    ) {
        self.current = current
        self.longest = longest
        self.lastActiveDay = lastActiveDay
        self.isActiveToday = isActiveToday
        self.isAtRisk = isAtRisk
        self.totalActiveDays = totalActiveDays
    }

    public static let empty = StreakSummary(
        current: 0,
        longest: 0,
        lastActiveDay: nil,
        isActiveToday: false,
        isAtRisk: false,
        totalActiveDays: 0
    )

    /// True when the current run is the best one ever — worth celebrating in UI.
    public var isPersonalBest: Bool { current > 0 && current >= longest }

    public var displayText: String { Formatters.streak(current) }
}

// MARK: - StreakEngine

/// Counts consecutive activity.
///
/// Two rules make streaks feel fair rather than punishing, and both are
/// deliberate:
///
/// 1. **Today is never a break.** An unlogged today leaves the streak standing
///    and flags it `isAtRisk`. Breaking someone's 40-day streak at 12:01am for a
///    day that isn't over is the fastest way to lose them.
/// 2. **Grace days are optional.** `graceDays > 0` lets a run survive that many
///    missed days, the "streak freeze" pattern. Default is 0 — strict.
public struct StreakEngine: Sendable {
    public var calculator: PeriodCalculator
    /// Missed days a run can absorb without breaking.
    public var graceDays: Int

    public init(calculator: PeriodCalculator = PeriodCalculator(), graceDays: Int = 0) {
        self.calculator = calculator
        self.graceDays = graceDays
    }

    /// A streak that forgives one missed day per run.
    public static let forgiving = StreakEngine(graceDays: 1)

    // MARK: Day streaks

    /// Counts a streak over a set of qualifying days.
    ///
    /// - Parameter days: any dates; duplicates and times of day are fine, they get
    ///   normalized to calendar days.
    public func summary(days: [Date], asOf now: Date = .now) -> StreakSummary {
        let normalized = Set(days.map(calculator.startOfDay))
        guard !normalized.isEmpty else { return .empty }

        let sorted = normalized.sorted()
        let today = calculator.startOfDay(now)
        let isActiveToday = normalized.contains(today)

        // Longest run anywhere in history.
        var longest = 1
        var run = 1
        for index in 1..<max(sorted.count, 1) where sorted.count > 1 {
            let gap = calculator.dayCount(from: sorted[index - 1], to: sorted[index])
            if gap <= 1 + graceDays {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
        }

        // Current run, walking backwards from today.
        // Today not being logged yet costs nothing; the walk simply starts at
        // yesterday and the streak is marked at risk.
        var current = 0
        var cursor = today
        if !isActiveToday {
            guard let yesterday = calculator.calendar.date(byAdding: .day, value: -1, to: today) else {
                return StreakSummary(
                    current: 0,
                    longest: longest,
                    lastActiveDay: sorted.last,
                    isActiveToday: false,
                    isAtRisk: false,
                    totalActiveDays: normalized.count
                )
            }
            cursor = yesterday
        }

        var budget = graceDays
        while cursor >= sorted.first ?? cursor {
            if normalized.contains(cursor) {
                current += 1
            } else if budget > 0 {
                budget -= 1
            } else {
                break
            }
            guard let previous = calculator.calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        let isAtRisk = current > 0 && !isActiveToday

        return StreakSummary(
            current: current,
            longest: max(longest, current),
            lastActiveDay: sorted.last,
            isActiveToday: isActiveToday,
            isAtRisk: isAtRisk,
            totalActiveDays: normalized.count
        )
    }

    /// The daily login streak for one profile.
    public func loginStreak(_ loginDays: [LoginDay], asOf now: Date = .now) -> StreakSummary {
        summary(days: loginDays.map(\.day), asOf: now)
    }

    // MARK: Goal streaks

    /// Consecutive **periods** in which a tracker's goal was met.
    ///
    /// For a daily goal this is a day streak. For a weekly goal it is a run of
    /// weeks, which is the right unit — "4 weeks straight" is the achievement, not
    /// "28 days" of a goal that was never daily.
    ///
    /// The in-flight period counts only once actually met; falling short of a goal
    /// whose window is still open never breaks the run.
    public func goalStreak(
        tracker: Tracker,
        entries: [Entry],
        lookbackPeriods: Int = 180,
        asOf now: Date = .now,
        progress: ProgressEngine? = nil
    ) -> StreakSummary {
        let engine = progress ?? ProgressEngine(calculator: calculator)
        guard let cadence = tracker.goal(on: now)?.cadence, cadence.supportsStreaks else {
            return .empty
        }

        let snapshots = engine.history(
            tracker: tracker,
            entries: entries,
            periodCount: lookbackPeriods,
            cadence: cadence,
            endingAt: now
        )
        guard !snapshots.isEmpty else { return .empty }

        var longest = 0
        var run = 0
        for snapshot in snapshots {
            if snapshot.isMet {
                run += 1
                longest = max(longest, run)
            } else if snapshot.isPeriodComplete {
                run = 0
            }
            // An open period that isn't met yet: leave the run untouched.
        }

        var current = 0
        var budget = graceDays
        for snapshot in snapshots.reversed() {
            if snapshot.isMet {
                current += 1
            } else if !snapshot.isPeriodComplete {
                // Current window still open — skip without penalty.
                continue
            } else if budget > 0 {
                budget -= 1
            } else {
                break
            }
        }

        let currentSnapshot = snapshots.last
        let isActiveNow = currentSnapshot?.isMet ?? false
        let lastMet = snapshots.last { $0.isMet }?.period.start

        return StreakSummary(
            current: current,
            longest: max(longest, current),
            lastActiveDay: lastMet,
            isActiveToday: isActiveNow,
            isAtRisk: current > 0 && !isActiveNow,
            totalActiveDays: snapshots.filter(\.isMet).count
        )
    }

    // MARK: Calendar shape

    /// Per-day activity flags over a trailing window, oldest first — the backing
    /// data for the streak calendar / heatmap strip.
    public func activityFlags(
        days: [Date],
        dayCount: Int,
        endingAt end: Date = .now
    ) -> [(date: Date, isActive: Bool)] {
        let normalized = Set(days.map(calculator.startOfDay))
        return calculator.trailingDays(dayCount, endingAt: end).map {
            ($0, normalized.contains($0))
        }
    }
}
