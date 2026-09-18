import Foundation

/// Assembles a ``ProgressReport`` from raw trackers and entries.
///
/// Pure and off-actor-safe: give it value types, get a report. The store has a
/// convenience wrapper, but a widget or a background task can call this directly.
public struct ReportBuilder: Sendable {
    public var progress: ProgressEngine
    public var streaks: StreakEngine
    public var trends: TrendEngine
    public var calculator: PeriodCalculator

    public init(
        calculator: PeriodCalculator = PeriodCalculator(),
        stoplight: StoplightEngine = .standard
    ) {
        self.calculator = calculator
        self.progress = ProgressEngine(calculator: calculator, stoplight: stoplight)
        self.streaks = StreakEngine(calculator: calculator)
        self.trends = TrendEngine(calculator: calculator)
    }

    /// Builds a report covering the `lookbackDays` ending at `end`.
    public func build(
        profile: Profile,
        trackers: [Tracker],
        entriesByTracker: [UUID: [Entry]],
        loginDays: [LoginDay],
        lookbackDays: Int = 7,
        endingAt end: Date = .now
    ) -> ProgressReport {
        let endOfWindow = calculator.calendar.date(
            byAdding: .day, value: 1, to: calculator.startOfDay(end)
        ) ?? end
        let startOfWindow = calculator.calendar.date(
            byAdding: .day, value: -lookbackDays, to: endOfWindow
        ) ?? end
        let interval = DateInterval(start: startOfWindow, end: endOfWindow)

        let items = trackers
            .filter { !$0.isArchived }
            .map { tracker in
                buildItem(
                    tracker: tracker,
                    entries: entriesByTracker[tracker.id] ?? [],
                    interval: interval,
                    lookbackDays: lookbackDays,
                    end: end
                )
            }

        return ProgressReport(
            profileID: profile.id,
            profileName: profile.name,
            interval: interval,
            generatedAt: end,
            loginStreak: streaks.loginStreak(loginDays, asOf: end),
            items: items
        )
    }

    private func buildItem(
        tracker: Tracker,
        entries: [Entry],
        interval: DateInterval,
        lookbackDays: Int,
        end: Date
    ) -> ReportItem {
        let goal = tracker.goal(on: end)
        let aggregation = goal?.aggregation ?? tracker.kind.defaultAggregation

        // The window total, scored against the goal expressed at window scale.
        let rolled = progress.aggregate(entries: entries, in: interval, using: aggregation)

        // A daily goal over a 7-day window is a 7× target; a weekly goal is 1×.
        let windowTarget = goal.map { scaledTarget($0, lookbackDays: lookbackDays) }

        let stoplight = progress.stoplight
        let status = stoplight.status(
            actual: rolled.value,
            target: windowTarget,
            direction: goal?.direction ?? .atLeast,
            cadence: goal?.cadence ?? .daily,
            // The window is closed by the time a report goes out.
            paceFraction: 1
        )

        let reason = stoplight.explanation(
            status: status,
            actual: rolled.value,
            target: windowTarget,
            direction: goal?.direction ?? .atLeast,
            unit: goal?.unit ?? tracker.kind.defaultUnit,
            daysRemaining: 0
        )

        // Previous comparable window, for the trend.
        let previousEnd = interval.start
        let previousStart = calculator.calendar.date(
            byAdding: .day, value: -lookbackDays, to: previousEnd
        ) ?? previousEnd
        let previous = progress.aggregate(
            entries: entries,
            in: DateInterval(start: previousStart, end: previousEnd),
            using: aggregation
        )

        let trend: Trend? = (previous.count > 0 || rolled.count > 0)
            ? trends.trend(current: rolled.value, previous: previous.value)
            : nil

        let daily = progress.dailyValues(
            tracker: tracker,
            entries: entries,
            dayCount: lookbackDays,
            endingAt: end
        )

        let periods = progress.history(
            tracker: tracker,
            entries: entries,
            periodCount: max(lookbackDays, 7),
            cadence: goal?.cadence ?? .daily,
            endingAt: end
        )

        let goalChanged = tracker.goalHistory.contains {
            $0.effectiveFrom >= interval.start && $0.effectiveFrom < interval.end
        }

        return ReportItem(
            trackerID: tracker.id,
            title: tracker.title,
            detail: tracker.detail,
            symbolName: tracker.symbolName,
            colorHex: tracker.colorHex,
            kind: tracker.kind,
            goal: goal,
            actual: rolled.value,
            target: windowTarget,
            status: status,
            statusReason: reason,
            trend: trend,
            streak: streaks.goalStreak(
                tracker: tracker,
                entries: entries,
                asOf: end,
                progress: progress
            ),
            dailyValues: daily,
            periods: periods,
            goalChangedInWindow: goalChanged
        )
    }

    /// Expresses a goal's target at the scale of the reporting window.
    ///
    /// A daily 8-glasses goal over a 7-day report is 56; a weekly 4-workout goal
    /// over the same report is 4. Without this, every daily goal would look wildly
    /// overachieved in a weekly summary.
    public func scaledTarget(_ goal: GoalVersion, lookbackDays: Int) -> Double {
        switch goal.cadence {
        case .total:
            return goal.target
        default:
            let periodsInWindow = Double(lookbackDays) / goal.cadence.approximateDayCount
            // Aggregations that average don't scale with period count.
            switch goal.aggregation {
            case .average, .max, .min, .latest:
                return goal.target
            case .sum:
                return goal.target * max(periodsInWindow, 0.0001)
            }
        }
    }
}

// MARK: - Store convenience

public extension TrackerStore {

    /// Builds a report for a profile straight from the store.
    @MainActor
    func buildReport(
        for profileID: UUID? = nil,
        lookbackDays: Int = 7,
        endingAt end: Date = .now
    ) -> ProgressReport? {
        guard let id = profileID ?? activeProfileID,
              let profile = profiles.first(where: { $0.id == id })
        else { return nil }

        let scopedTrackers: [Tracker]
        let entriesByTracker: [UUID: [Entry]]
        let days: [LoginDay]

        if id == activeProfileID {
            scopedTrackers = trackers
            entriesByTracker = Dictionary(
                grouping: entries,
                by: { $0.trackerID }
            )
            days = loginDays
        } else {
            // Another profile — reach into storage directly.
            let previousActive = activeProfileID
            activeProfileID = id
            scopedTrackers = trackers
            entriesByTracker = Dictionary(grouping: entries, by: { $0.trackerID })
            days = loginDays
            activeProfileID = previousActive
        }

        let builder = ReportBuilder(calculator: calculator, stoplight: progress.stoplight)
        return builder.build(
            profile: profile,
            trackers: scopedTrackers,
            entriesByTracker: entriesByTracker,
            loginDays: days,
            lookbackDays: lookbackDays,
            endingAt: end
        )
    }
}
