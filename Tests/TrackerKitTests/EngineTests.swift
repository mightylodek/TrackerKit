import Testing
import Foundation
@testable import TrackerKit

/// All date maths runs against a fixed UTC calendar so results don't move with
/// the machine's locale or timezone.
private let fixed = PeriodCalculator.fixed

private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    return fixed.calendar.date(from: components)!
}

// MARK: - PeriodCalculator

struct PeriodCalculatorTests {

    @Test("A daily period covers exactly one day")
    func dailyPeriod() {
        let period = fixed.period(for: .daily, containing: day(2026, 9, 17))
        #expect(period.start == day(2026, 9, 17, hour: 0))
        #expect(period.end == day(2026, 9, 18, hour: 0))
        #expect(period.contains(day(2026, 9, 17, hour: 23)))
        #expect(!period.contains(day(2026, 9, 18, hour: 0)))
    }

    @Test("A weekly period starts on the calendar's first weekday")
    func weeklyPeriod() {
        // 2026-09-17 is a Thursday; the fixed calendar starts weeks on Sunday.
        let period = fixed.period(for: .weekly, containing: day(2026, 9, 17))
        #expect(period.start == day(2026, 9, 13, hour: 0))
        #expect(period.end == day(2026, 9, 20, hour: 0))
    }

    @Test("Trailing periods come back oldest first and end on today")
    func trailingPeriods() {
        let periods = fixed.trailingPeriods(4, cadence: .daily, endingAt: day(2026, 9, 17))
        #expect(periods.count == 4)
        #expect(periods.first?.start == day(2026, 9, 14, hour: 0))
        #expect(periods.last?.start == day(2026, 9, 17, hour: 0))
        // Strictly ascending.
        #expect(zip(periods, periods.dropFirst()).allSatisfy { $0.start < $1.start })
    }

    @Test("Pace is the share of the period elapsed")
    func pacing() {
        let week = fixed.period(for: .weekly, containing: day(2026, 9, 17))
        // Sunday 00:00 start; Wednesday 00:00 is 3 of 7 days in.
        let pace = fixed.fractionElapsed(of: week, at: day(2026, 9, 16, hour: 0))
        #expect(abs(pace - 3.0 / 7.0) < 0.001)

        #expect(fixed.fractionElapsed(of: week, at: day(2026, 9, 13, hour: 0)) == 0)
        #expect(fixed.fractionElapsed(of: week, at: day(2026, 9, 25)) == 1)
    }

    @Test("Days remaining counts today as remaining")
    func daysRemaining() {
        let week = fixed.period(for: .weekly, containing: day(2026, 9, 17))
        // Thursday, with Fri and Sat to go after it.
        #expect(fixed.daysRemaining(in: week, from: day(2026, 9, 17)) == 2)
        #expect(fixed.daysRemaining(in: week, from: day(2026, 9, 19)) == 0)
    }
}

// MARK: - StoplightEngine

struct StoplightEngineTests {
    private let engine = StoplightEngine.standard

    @Test("Zero progress early in a period is not a failure")
    func earlyZeroIsGreen() {
        // Monday of a weekly 5-target: inside the grace window, and strict pacing
        // would expect 0.7 of a workout, which is not a thing anyone can do.
        let status = engine.status(
            actual: 0, target: 5, direction: .atLeast, cadence: .weekly, paceFraction: 0.14
        )
        #expect(status == .green)
    }

    @Test("A small discrete target isn't graded on fractional expectations")
    func fractionalExpectationsAreNotGraded() {
        // A 2-per-week goal expects 0.8 by midweek — under one whole unit, so
        // there is nothing to be behind on and it stays green.
        #expect(engine.status(
            actual: 0, target: 2, direction: .atLeast, cadence: .weekly, paceFraction: 0.4
        ) == .green)

        // Once a whole unit is expected the grading resumes: 30% into the week a
        // 5-target expects 1.5, so one done is mildly behind — at risk, not off track.
        #expect(engine.status(
            actual: 1, target: 5, direction: .atLeast, cadence: .weekly, paceFraction: 0.3
        ) == .yellow)

        // And two done at that point is ahead of the expectation.
        #expect(engine.status(
            actual: 2, target: 5, direction: .atLeast, cadence: .weekly, paceFraction: 0.3
        ) == .green)
    }

    @Test("A large target is graded normally once out of the grace window")
    func largeTargetsGradeNormally() {
        // 8000 steps, 40% through the day, none logged: genuinely behind.
        #expect(engine.status(
            actual: 0, target: 8000, direction: .atLeast, cadence: .daily, paceFraction: 0.4
        ) == .red)
    }

    @Test("The grace window is configurable")
    func graceIsTunable() {
        let strict = StoplightEngine.strict
        let lenient = StoplightEngine.lenient

        // 30% through the week with nothing done on a 20-target.
        #expect(strict.status(
            actual: 0, target: 20, direction: .atLeast, cadence: .weekly, paceFraction: 0.3
        ) == .red)
        #expect(lenient.status(
            actual: 0, target: 20, direction: .atLeast, cadence: .weekly, paceFraction: 0.3
        ) == .green)
    }

    @Test("Zero progress late in a period is a failure")
    func lateZeroIsRed() {
        let status = engine.status(
            actual: 0, target: 5, direction: .atLeast, cadence: .weekly, paceFraction: 0.86
        )
        #expect(status == .red)
    }

    @Test("A met goal is green regardless of pace")
    func metIsAlwaysGreen() {
        #expect(engine.status(
            actual: 5, target: 5, direction: .atLeast, cadence: .weekly, paceFraction: 0.1
        ) == .green)
        #expect(engine.status(
            actual: 9, target: 5, direction: .atLeast, cadence: .weekly, paceFraction: 1
        ) == .green)
    }

    @Test("A closed period that fell short is red, not yellow")
    func closedAndShortIsRed() {
        #expect(engine.status(
            actual: 4.9, target: 5, direction: .atLeast, cadence: .weekly, paceFraction: 1
        ) == .red)
    }

    @Test("Slightly behind pace reads yellow, badly behind reads red")
    func pacingBands() {
        // Half the week gone, 5 target: 2.5 expected.
        #expect(engine.status(
            actual: 2.2, target: 5, direction: .atLeast, cadence: .weekly, paceFraction: 0.5
        ) == .green)
        #expect(engine.status(
            actual: 1.7, target: 5, direction: .atLeast, cadence: .weekly, paceFraction: 0.5
        ) == .yellow)
        #expect(engine.status(
            actual: 1.0, target: 5, direction: .atLeast, cadence: .weekly, paceFraction: 0.5
        ) == .red)
    }

    @Test("An at-most goal goes red the moment the limit is passed")
    func atMostOverLimit() {
        #expect(engine.status(
            actual: 121, target: 120, direction: .atMost, cadence: .daily, paceFraction: 0.2
        ) == .red)
        #expect(engine.status(
            actual: 20, target: 120, direction: .atMost, cadence: .daily, paceFraction: 0.2
        ) == .green)
    }

    @Test("An at-most goal under the limit at period end is green")
    func atMostSurvivesTheDay() {
        #expect(engine.status(
            actual: 119, target: 120, direction: .atMost, cadence: .daily, paceFraction: 1
        ) == .green)
    }

    @Test("Burning an allowance too early reads yellow")
    func atMostBurnedEarly() {
        // 70% of the allowance gone with only 30% of the day elapsed.
        let status = engine.status(
            actual: 84, target: 120, direction: .atMost, cadence: .daily, paceFraction: 0.3
        )
        #expect(status == .red || status == .yellow)
    }

    @Test("A total-cadence goal is never 'behind' — it has no deadline")
    func totalHasNoPace() {
        #expect(engine.status(
            actual: 10, target: 100, direction: .atLeast, cadence: .total, paceFraction: 1
        ) == .neutral)
        #expect(engine.status(
            actual: 100, target: 100, direction: .atLeast, cadence: .total, paceFraction: 1
        ) == .green)
    }

    @Test("A breached ceiling is flagged so a full bar can't read as success")
    func ceilingBreachIsFlagged() {
        let period = fixed.period(for: .daily, containing: day(2026, 9, 17))

        func snapshot(actual: Double, target: Double, direction: GoalDirection) -> ProgressSnapshot {
            ProgressSnapshot(
                trackerID: UUID(),
                period: period,
                goal: GoalVersion(target: target, cadence: .daily, direction: direction, unit: "min"),
                actual: actual,
                entryCount: 1,
                paceFraction: 0.5,
                status: .red
            )
        }

        // Over a ceiling: flagged.
        #expect(snapshot(actual: 138, target: 120, direction: .atMost).breachesLimit)
        // Under a ceiling: not flagged.
        #expect(!snapshot(actual: 90, target: 120, direction: .atMost).breachesLimit)
        // Beating a floor is an achievement, never a breach.
        #expect(!snapshot(actual: 138, target: 120, direction: .atLeast).breachesLimit)
        // Exactly on the limit is still within it.
        #expect(!snapshot(actual: 120, target: 120, direction: .atMost).breachesLimit)
    }

    @Test("No target means no judgment")
    func noTargetIsNeutral() {
        #expect(engine.status(
            actual: 42, target: nil, direction: .atLeast, cadence: .daily, paceFraction: 0.5
        ) == .neutral)
    }
}

// MARK: - Goal history

struct GoalHistoryTests {

    private func trackerWithTwoGoals() -> Tracker {
        Tracker(
            profileID: UUID(),
            title: "Workouts",
            kind: .count,
            goalHistory: [
                GoalVersion(effectiveFrom: day(2026, 1, 1), target: 3, cadence: .weekly, unit: "x"),
                GoalVersion(effectiveFrom: day(2026, 6, 1), target: 5, cadence: .weekly, unit: "x")
            ]
        )
    }

    @Test("The goal in force on a date is the latest one starting at or before it")
    func goalResolution() {
        let tracker = trackerWithTwoGoals()

        #expect(tracker.goal(on: day(2025, 12, 31)) == nil)
        #expect(tracker.goal(on: day(2026, 3, 1))?.target == 3)
        #expect(tracker.goal(on: day(2026, 6, 1))?.target == 5)
        #expect(tracker.goal(on: day(2026, 9, 17))?.target == 5)
    }

    @Test("The timeline closes each version at the next one's start")
    func timeline() {
        let timeline = trackerWithTwoGoals().goalTimeline
        #expect(timeline.count == 2)
        #expect(timeline[0].goal.target == 3)
        #expect(timeline[0].endedAt == day(2026, 6, 1))
        #expect(timeline[1].goal.target == 5)
        #expect(timeline[1].endedAt == nil)
    }

    @Test("A past period is scored against the goal that was in force then")
    func pastPeriodsUseTheirOwnGoal() {
        let tracker = trackerWithTwoGoals()
        let engine = ProgressEngine(calculator: fixed)

        let march = fixed.period(for: .weekly, containing: day(2026, 3, 4))
        let july = fixed.period(for: .weekly, containing: day(2026, 7, 8))

        #expect(engine.governingGoal(for: tracker, period: march, now: day(2026, 9, 17))?.target == 3)
        #expect(engine.governingGoal(for: tracker, period: july, now: day(2026, 9, 17))?.target == 5)
    }

    @Test("The current period picks up a goal change immediately")
    func currentPeriodUsesTodaysGoal() {
        var tracker = trackerWithTwoGoals()
        let now = day(2026, 9, 17)
        // A goal raised mid-week applies to this week, not next.
        tracker.goalHistory.append(
            GoalVersion(effectiveFrom: day(2026, 9, 16), target: 8, cadence: .weekly, unit: "x")
        )

        let engine = ProgressEngine(calculator: fixed)
        let thisWeek = fixed.period(for: .weekly, containing: now)
        #expect(engine.governingGoal(for: tracker, period: thisWeek, now: now)?.target == 8)
    }

    @Test("Three workouts is a hit under the old goal and a miss under the new one")
    func sameNumberDifferentVerdict() {
        let tracker = trackerWithTwoGoals()
        let engine = ProgressEngine(calculator: fixed)
        let now = day(2026, 9, 17)

        func threeWorkouts(inWeekOf date: Date) -> [Entry] {
            (0..<3).map { offset in
                Entry(
                    trackerID: tracker.id,
                    profileID: tracker.profileID,
                    date: fixed.calendar.date(byAdding: .day, value: offset, to: date)!,
                    value: 1
                )
            }
        }

        let marchWeek = fixed.period(for: .weekly, containing: day(2026, 3, 4))
        let julyWeek = fixed.period(for: .weekly, containing: day(2026, 7, 8))

        let march = engine.snapshot(
            tracker: tracker,
            entries: threeWorkouts(inWeekOf: marchWeek.start),
            period: marchWeek,
            now: now
        )
        let july = engine.snapshot(
            tracker: tracker,
            entries: threeWorkouts(inWeekOf: julyWeek.start),
            period: julyWeek,
            now: now
        )

        #expect(march.actual == 3)
        #expect(july.actual == 3)
        #expect(march.isMet)          // 3 of 3
        #expect(!july.isMet)          // 3 of 5
        #expect(march.status == .green)
        #expect(july.status == .red)
    }
}

// MARK: - StreakEngine

struct StreakEngineTests {
    private let engine = StreakEngine(calculator: fixed)

    private func days(_ offsets: [Int], from now: Date) -> [Date] {
        offsets.compactMap { fixed.calendar.date(byAdding: .day, value: -$0, to: now) }
    }

    @Test("An unbroken run counts every day")
    func simpleStreak() {
        let now = day(2026, 9, 17)
        let summary = engine.summary(days: days([0, 1, 2, 3, 4], from: now), asOf: now)
        #expect(summary.current == 5)
        #expect(summary.isActiveToday)
        #expect(!summary.isAtRisk)
    }

    @Test("An unlogged today keeps the streak but flags it at risk")
    func todayIsNotABreak() {
        let now = day(2026, 9, 17)
        let summary = engine.summary(days: days([1, 2, 3], from: now), asOf: now)
        #expect(summary.current == 3)
        #expect(!summary.isActiveToday)
        #expect(summary.isAtRisk)
    }

    @Test("A missed day breaks the run")
    func gapBreaksStreak() {
        let now = day(2026, 9, 17)
        // Missing day 2 — so the current run is only today and yesterday.
        let summary = engine.summary(days: days([0, 1, 3, 4, 5], from: now), asOf: now)
        #expect(summary.current == 2)
        #expect(summary.longest == 3)
    }

    @Test("Grace days let a run survive one miss")
    func graceDays() {
        let now = day(2026, 9, 17)
        let forgiving = StreakEngine(calculator: fixed, graceDays: 1)
        let summary = forgiving.summary(days: days([0, 1, 3, 4, 5], from: now), asOf: now)
        #expect(summary.current == 5)
    }

    @Test("Duplicate logins on one day count once")
    func duplicatesCollapse() {
        let now = day(2026, 9, 17)
        let sameDay = [day(2026, 9, 17, hour: 8), day(2026, 9, 17, hour: 14), day(2026, 9, 17, hour: 22)]
        let summary = engine.summary(days: sameDay, asOf: now)
        #expect(summary.current == 1)
        #expect(summary.totalActiveDays == 1)
    }

    @Test("No history is an empty streak, not a crash")
    func emptyStreak() {
        #expect(engine.summary(days: [], asOf: day(2026, 9, 17)).current == 0)
        #expect(engine.summary(days: [], asOf: day(2026, 9, 17)) == .empty)
    }

    @Test("A weekly goal streaks in weeks, not days")
    func weeklyGoalStreak() {
        let now = day(2026, 9, 17)
        let tracker = Tracker(
            profileID: UUID(),
            title: "Workouts",
            kind: .count,
            goalHistory: [
                GoalVersion(effectiveFrom: day(2026, 1, 1), target: 2, cadence: .weekly, unit: "x")
            ]
        )

        // Two workouts in each of the last four complete weeks.
        var entries: [Entry] = []
        for weeksAgo in 1...4 {
            let weekStart = fixed.calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: now)!
            let period = fixed.period(for: .weekly, containing: weekStart)
            for offset in 0..<2 {
                entries.append(
                    Entry(
                        trackerID: tracker.id,
                        profileID: tracker.profileID,
                        date: fixed.calendar.date(byAdding: .day, value: offset, to: period.start)!,
                        value: 1
                    )
                )
            }
        }

        let summary = engine.goalStreak(
            tracker: tracker,
            entries: entries,
            asOf: now,
            progress: ProgressEngine(calculator: fixed)
        )
        // Four met weeks; the in-flight week isn't met yet but must not break it.
        #expect(summary.current == 4)
    }
}

// MARK: - Aggregation and trends

struct AggregationTests {

    @Test("Each aggregation reduces as advertised")
    func aggregations() {
        let values: [Double] = [2, 4, 6, 8]
        #expect(Aggregation.sum.apply(to: values) == 20)
        #expect(Aggregation.average.apply(to: values) == 5)
        #expect(Aggregation.max.apply(to: values) == 8)
        #expect(Aggregation.min.apply(to: values) == 2)
        #expect(Aggregation.latest.apply(to: values) == 8)
        #expect(Aggregation.sum.apply(to: []) == 0)
    }

    @Test("A checkbox collapses to one value a day; a count adds up")
    func kindAggregation() {
        #expect(TrackerKind.checkbox.defaultAggregation == .max)
        #expect(TrackerKind.count.defaultAggregation == .sum)
        #expect(TrackerKind.rating.defaultAggregation == .average)
        #expect(TrackerKind.checkbox.isSingleValuePerDay)
        #expect(!TrackerKind.count.isSingleValuePerDay)
    }

    @Test("Growth from zero has no percentage, and says so")
    func trendFromZero() {
        let trend = Trend(current: 5, previous: 0)
        #expect(trend.changeFraction == nil)
        #expect(trend.direction == .rising)
        #expect(trend.displayText() == "+5")
    }

    @Test("Trend direction respects what the goal wants")
    func favorability() {
        let rising = Trend(current: 10, previous: 5)
        #expect(rising.isFavorable(for: .atLeast))
        #expect(!rising.isFavorable(for: .atMost))

        let falling = Trend(current: 5, previous: 10)
        #expect(!falling.isFavorable(for: .atLeast))
        #expect(falling.isFavorable(for: .atMost))
    }

    @Test("A projection needs enough of the period to have elapsed")
    func projectionGuard() {
        let engine = TrendEngine(calculator: fixed)
        let period = fixed.period(for: .weekly, containing: day(2026, 9, 17))

        let tooEarly = ProgressSnapshot(
            trackerID: UUID(), period: period, goal: nil,
            actual: 1, entryCount: 1, paceFraction: 0.05, status: .green
        )
        #expect(engine.projectedTotal(for: tooEarly) == nil)

        let halfway = ProgressSnapshot(
            trackerID: UUID(), period: period, goal: nil,
            actual: 10, entryCount: 5, paceFraction: 0.5, status: .green
        )
        #expect(engine.projectedTotal(for: halfway) == 20)
    }

    @Test("Moving average is the same length as its input")
    func movingAverage() {
        let engine = TrendEngine(calculator: fixed)
        let values: [Double] = [1, 2, 3, 4, 5, 6]
        let averaged = engine.movingAverage(values, window: 3)
        #expect(averaged.count == values.count)
        #expect(averaged[0] == 1)          // only one value available
        #expect(averaged[2] == 2)          // (1+2+3)/3
        #expect(averaged[5] == 5)          // (4+5+6)/3
    }
}

// MARK: - Formatters

struct FormatterTests {

    @Test("Numbers drop pointless decimals")
    func numbers() {
        #expect(Formatters.number(5) == "5")
        #expect(Formatters.number(5.5) == "5.5")
        #expect(Formatters.number(0) == "0")
    }

    @Test("Durations read in hours and minutes")
    func durations() {
        #expect(Formatters.duration(minutes: 45) == "45m")
        #expect(Formatters.duration(minutes: 60) == "1h")
        #expect(Formatters.duration(minutes: 90) == "1h 30m")
        #expect(Formatters.value(90, unit: "min") == "1h 30m")
    }

    @Test("Compact axis labels abbreviate large numbers")
    func compact() {
        #expect(Formatters.compact(950) == "950")
        #expect(Formatters.compact(1500) == "1.5K")
        #expect(Formatters.compact(12_000) == "12K")
        #expect(Formatters.compact(2_400_000) == "2.4M")
    }

    @Test("Non-finite input renders as a dash rather than 'nan'")
    func nonFinite() {
        #expect(Formatters.number(.nan) == "—")
        #expect(Formatters.percent(.nan) == "—")
        #expect(Formatters.signedPercent(.infinity) == "—")
    }
}
