import Testing
import Foundation
@testable import TrackerKit

/// Custom report ranges, bucketing and filtering.
///
/// Everything runs against `PeriodCalculator.fixed` (UTC, Sunday-start) so a
/// result never moves with the machine's locale — then overrides the week start
/// per report, which is the whole point of the feature.
@Suite("Custom reports")
struct CustomReportTests {

    private let engine = CustomReportEngine(calculator: .fixed)
    private let profileID = UUID()

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: hour)) ?? .distantPast
    }

    private func makeTracker(title: String = "Reading", kind: TrackerKind = .duration) -> Tracker {
        Tracker(profileID: profileID, title: title, kind: kind)
    }

    private func entries(_ tracker: Tracker, _ days: [(Int, Double)], month: Int = 9, year: Int = 2026) -> [Entry] {
        days.map { day, value in
            Entry(trackerID: tracker.id, profileID: profileID, date: date(year, month, day), value: value)
        }
    }

    private func definition(
        _ tracker: Tracker,
        range: ReportRange,
        weekdays: Set<Int> = [],
        firstWeekday: Int = 1,
        breakdowns: Set<ReportBreakdown> = [.daily, .total]
    ) -> ReportDefinition {
        ReportDefinition(
            name: "Test",
            profileID: profileID,
            trackerIDs: [tracker.id],
            range: range,
            weekdays: weekdays,
            firstWeekday: firstWeekday,
            breakdowns: breakdowns
        )
    }

    // MARK: Ranges

    @Test("An absolute range includes the last day")
    func absoluteIncludesEndDay() {
        let tracker = makeTracker()
        // Sep 1–7 is seven days, not six and a sliver.
        let def = definition(tracker, range: .absolute(start: date(2026, 9, 1), end: date(2026, 9, 7)))
        let interval = engine.resolve(def.range, for: def, now: date(2026, 9, 20))

        #expect(interval.start == utc.startOfDay(for: date(2026, 9, 1)))
        #expect(interval.end == utc.startOfDay(for: date(2026, 9, 8)))
    }

    @Test("Backwards dates are accepted rather than producing nothing")
    func absoluteHandlesReversedDates() {
        let tracker = makeTracker()
        let def = definition(tracker, range: .absolute(start: date(2026, 9, 7), end: date(2026, 9, 1)))
        let interval = engine.resolve(def.range, for: def, now: date(2026, 9, 20))

        #expect(interval.start == utc.startOfDay(for: date(2026, 9, 1)))
        #expect(interval.end == utc.startOfDay(for: date(2026, 9, 8)))
    }

    @Test("Last N days counts today as one of them")
    func lastDaysIncludesToday() {
        let tracker = makeTracker()
        let def = definition(tracker, range: .lastDays(5))
        let interval = engine.resolve(def.range, for: def, now: date(2026, 9, 20))

        // The 16th through the 20th — five days, not six.
        #expect(interval.start == utc.startOfDay(for: date(2026, 9, 16)))
        #expect(interval.end == utc.startOfDay(for: date(2026, 9, 21)))
    }

    /// Sep 20 2026 is a Sunday.
    @Test("Complete weeks exclude the week in progress")
    func completeWeeksExcludePartial() {
        let tracker = makeTracker()
        // Friday-start weeks: the current one began Fri Sep 18.
        let def = definition(tracker, range: .lastCompleteWeeks(2), firstWeekday: 6)
        let interval = engine.resolve(def.range, for: def, now: date(2026, 9, 20))

        #expect(interval.end == utc.startOfDay(for: date(2026, 9, 18)))
        #expect(interval.start == utc.startOfDay(for: date(2026, 9, 4)))
    }

    // MARK: Week start — the Friday-to-Thursday case

    @Test("Weeks begin on the day the report says")
    func weekStartIsHonoured() {
        var friday = utc
        friday.firstWeekday = 6
        // Sep 20 is a Sunday; a Friday-start week began on the 18th.
        #expect(engine.startOfWeek(containing: date(2026, 9, 20), calendar: friday)
                == utc.startOfDay(for: date(2026, 9, 18)))

        var sunday = utc
        sunday.firstWeekday = 1
        #expect(engine.startOfWeek(containing: date(2026, 9, 20), calendar: sunday)
                == utc.startOfDay(for: date(2026, 9, 20)))
    }

    /// The example this feature was asked for: a reading report running Friday
    /// to Thursday, broken down by day with a total.
    @Test("A Friday-to-Thursday reading week buckets correctly")
    func fridayToThursdayWeek() {
        let tracker = makeTracker()
        // Fri Sep 11 through Thu Sep 17, 10 minutes a day.
        let logged = entries(tracker, (11...17).map { ($0, 10.0) })
        let def = definition(
            tracker,
            range: .absolute(start: date(2026, 9, 11), end: date(2026, 9, 17)),
            firstWeekday: 6,
            breakdowns: [.daily, .weekly, .total]
        )

        let report = engine.build(def, trackers: [tracker], entriesByTracker: [tracker.id: logged],
                                  now: date(2026, 9, 20))
        let built = try! #require(report.trackers.first)

        #expect(built.section(.daily)?.buckets.count == 7)
        #expect(built.total == 70)
        // One whole week, because the range lines up with the report's own week.
        let weekly = try! #require(built.section(.weekly))
        #expect(weekly.buckets.count == 1)
        #expect(weekly.buckets.first?.value == 70)
    }

    // MARK: Weekday filtering

    @Test("A weekday filter drops days rather than showing them as zero")
    func weekdayFilterOmitsDays() {
        let tracker = makeTracker()
        // Sep 14–20 2026 is Mon–Sun. Log every day.
        let logged = entries(tracker, (14...20).map { ($0, 5.0) })
        // Mon–Fri only: Calendar weekdays 2...6.
        let def = definition(
            tracker,
            range: .absolute(start: date(2026, 9, 14), end: date(2026, 9, 20)),
            weekdays: [2, 3, 4, 5, 6]
        )

        let report = engine.build(def, trackers: [tracker], entriesByTracker: [tracker.id: logged],
                                  now: date(2026, 9, 21))
        let built = try! #require(report.trackers.first)

        // Five rows, not seven with two zeroes — a Saturday at 0 in a weekdays
        // report reads as a failure rather than a day out of scope.
        #expect(built.section(.daily)?.buckets.count == 5)
        #expect(built.total == 25)
    }

    @Test("An empty weekday set means every day")
    func emptyWeekdaySetMeansAll() {
        let tracker = makeTracker()
        let logged = entries(tracker, (14...20).map { ($0, 5.0) })
        let def = definition(tracker, range: .absolute(start: date(2026, 9, 14), end: date(2026, 9, 20)))

        let report = engine.build(def, trackers: [tracker], entriesByTracker: [tracker.id: logged],
                                  now: date(2026, 9, 21))
        #expect(report.trackers.first?.section(.daily)?.buckets.count == 7)
        #expect(report.trackers.first?.total == 35)
    }

    // MARK: Breakdowns

    @Test("Daily and total come back together")
    func breakdownsAreAdditive() {
        let tracker = makeTracker()
        let logged = entries(tracker, [(1, 10), (2, 20), (3, 30)])
        let def = definition(
            tracker,
            range: .absolute(start: date(2026, 9, 1), end: date(2026, 9, 3)),
            breakdowns: [.daily, .total]
        )

        let report = engine.build(def, trackers: [tracker], entriesByTracker: [tracker.id: logged],
                                  now: date(2026, 9, 20))
        let built = try! #require(report.trackers.first)

        #expect(built.sections.count == 2)
        #expect(built.section(.daily)?.buckets.map(\.value) == [10, 20, 30])
        #expect(built.section(.total)?.buckets.first?.value == 60)
    }

    @Test("Sections read finest first")
    func sectionsAreOrdered() {
        let tracker = makeTracker()
        let def = definition(tracker, range: .lastDays(30), breakdowns: [.total, .daily, .monthly])
        let report = engine.build(def, trackers: [tracker], entriesByTracker: [:], now: date(2026, 9, 20))

        #expect(report.trackers.first?.sections.map(\.breakdown) == [.daily, .monthly, .total])
    }

    @Test("Monthly buckets split across a month boundary")
    func monthlyBuckets() {
        let tracker = makeTracker()
        let august = entries(tracker, [(30, 5), (31, 5)], month: 8)
        let september = entries(tracker, [(1, 10)], month: 9)
        let def = definition(
            tracker,
            range: .absolute(start: date(2026, 8, 30), end: date(2026, 9, 1)),
            breakdowns: [.monthly]
        )

        let report = engine.build(def, trackers: [tracker],
                                  entriesByTracker: [tracker.id: august + september],
                                  now: date(2026, 9, 20))
        let buckets = try! #require(report.trackers.first?.section(.monthly)?.buckets)

        #expect(buckets.count == 2)
        #expect(buckets.map(\.value) == [10, 10])
    }

    @Test("A breakdown-less definition still reports a total")
    func emptyBreakdownsFallBack() {
        let tracker = makeTracker()
        let def = ReportDefinition(name: "x", profileID: profileID, trackerIDs: [tracker.id], breakdowns: [])
        #expect(def.breakdowns == [.total])
    }

    // MARK: Aggregation

    @Test("The goal's aggregation decides what a bucket means")
    func aggregationIsRespected() {
        let summed = makeTracker(kind: .amount)
        let logged = entries(summed, [(1, 10), (1, 20)])
        let def = definition(summed, range: .absolute(start: date(2026, 9, 1), end: date(2026, 9, 1)),
                             breakdowns: [.total])

        let report = engine.build(def, trackers: [summed], entriesByTracker: [summed.id: logged],
                                  now: date(2026, 9, 20))
        // .amount sums by default: two logs on one day is 30, not 20.
        #expect(report.trackers.first?.total == 30)
    }

    // MARK: Nothing logged

    @Test("A day with no entries is empty, not zero")
    func emptyIsDistinctFromZero() {
        let tracker = makeTracker()
        let logged = entries(tracker, [(1, 0)])
        let def = definition(tracker, range: .absolute(start: date(2026, 9, 1), end: date(2026, 9, 2)))

        let report = engine.build(def, trackers: [tracker], entriesByTracker: [tracker.id: logged],
                                  now: date(2026, 9, 20))
        let buckets = try! #require(report.trackers.first?.section(.daily)?.buckets)

        #expect(buckets.count == 2)
        #expect(buckets[0].isEmpty == false, "A logged zero is not an empty day")
        #expect(buckets[1].isEmpty == true, "A day with nothing logged should read as empty")
    }

    @Test("Several habits keep the report's own order")
    func trackerOrderFollowsTheDefinition() {
        let a = makeTracker(title: "Reading")
        let b = makeTracker(title: "Water")
        let def = ReportDefinition(
            name: "Two", profileID: profileID,
            trackerIDs: [b.id, a.id],
            range: .lastDays(7)
        )

        let report = engine.build(def, trackers: [a, b], entriesByTracker: [:], now: date(2026, 9, 20))
        #expect(report.trackers.map(\.title) == ["Water", "Reading"])
    }

    @Test("A deleted habit is skipped rather than crashing the report")
    func missingTrackerIsSkipped() {
        let a = makeTracker(title: "Reading")
        let def = ReportDefinition(
            name: "Stale", profileID: profileID,
            trackerIDs: [a.id, UUID()],
            range: .lastDays(7)
        )

        let report = engine.build(def, trackers: [a], entriesByTracker: [:], now: date(2026, 9, 20))
        #expect(report.trackers.count == 1)
    }
}
