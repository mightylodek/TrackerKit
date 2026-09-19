import Foundation

// MARK: - ReportBucket

/// One row of a breakdown: a labelled span and what it came to.
public struct ReportBucket: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let label: String
    public let interval: DateInterval
    public let value: Double
    /// How many entries landed in this bucket. Distinguishes "nothing logged"
    /// from "logged a zero", which matters for a habit you can genuinely do none
    /// of on purpose.
    public let entryCount: Int

    public init(
        id: UUID = UUID(),
        label: String,
        interval: DateInterval,
        value: Double,
        entryCount: Int
    ) {
        self.id = id
        self.label = label
        self.interval = interval
        self.value = value
        self.entryCount = entryCount
    }

    public var isEmpty: Bool { entryCount == 0 }
}

// MARK: - CustomReportSection

/// Every bucket at one level of grouping.
public struct CustomReportSection: Identifiable, Sendable, Hashable {
    public let breakdown: ReportBreakdown
    public let buckets: [ReportBucket]

    public var id: ReportBreakdown { breakdown }

    public init(breakdown: ReportBreakdown, buckets: [ReportBucket]) {
        self.breakdown = breakdown
        self.buckets = buckets
    }
}

// MARK: - CustomReportTracker

/// One habit's contribution to a report.
public struct CustomReportTracker: Identifiable, Sendable, Hashable {
    public let trackerID: UUID
    public let title: String
    public let unit: String
    public let symbolName: String
    public let colorHex: String
    public let aggregation: Aggregation
    public let sections: [CustomReportSection]
    /// The whole range in one number, always computed whether or not `.total`
    /// was asked for — a caller wants it for a headline even when the report
    /// only shows days.
    public let total: Double
    public let entryCount: Int

    public var id: UUID { trackerID }

    public init(
        trackerID: UUID,
        title: String,
        unit: String,
        symbolName: String,
        colorHex: String,
        aggregation: Aggregation,
        sections: [CustomReportSection],
        total: Double,
        entryCount: Int
    ) {
        self.trackerID = trackerID
        self.title = title
        self.unit = unit
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.aggregation = aggregation
        self.sections = sections
        self.total = total
        self.entryCount = entryCount
    }

    public var totalText: String { Formatters.value(total, unit: unit) }
    public var hasData: Bool { entryCount > 0 }

    public func section(_ breakdown: ReportBreakdown) -> CustomReportSection? {
        sections.first { $0.breakdown == breakdown }
    }
}

// MARK: - CustomReport

/// A built report, ready to render.
public struct CustomReport: Sendable, Hashable {
    public let definition: ReportDefinition
    public let interval: DateInterval
    public let generatedAt: Date
    public let trackers: [CustomReportTracker]

    public init(
        definition: ReportDefinition,
        interval: DateInterval,
        generatedAt: Date = .now,
        trackers: [CustomReportTracker]
    ) {
        self.definition = definition
        self.interval = interval
        self.generatedAt = generatedAt
        self.trackers = trackers
    }

    public var title: String { definition.name }
    public var rangeText: String { Formatters.range(interval) }
    public var isEmpty: Bool { trackers.allSatisfy { !$0.hasData } }
}

// MARK: - CustomReportEngine

/// Turns a ``ReportDefinition`` plus raw entries into a ``CustomReport``.
///
/// Pure: value types in, value types out, no SwiftData and no SwiftUI. That is
/// what lets it be tested against fixed dates and run from a widget or a watch.
public struct CustomReportEngine: Sendable {

    public var calculator: PeriodCalculator

    public init(calculator: PeriodCalculator = PeriodCalculator()) {
        self.calculator = calculator
    }

    /// The calendar this report reckons in — the calculator's, with the
    /// report's own week start applied.
    public func calendar(for definition: ReportDefinition) -> Calendar {
        var calendar = calculator.calendar
        calendar.firstWeekday = definition.firstWeekday
        return calendar
    }

    // MARK: Resolving the range

    /// Turns a range into concrete dates.
    ///
    /// The returned interval is half-open — `end` is the first instant *after*
    /// the range — so a day's entries at 23:59 are inside it and the next day's
    /// at 00:00 are not.
    public func resolve(_ range: ReportRange, for definition: ReportDefinition, now: Date = .now) -> DateInterval {
        let calendar = calendar(for: definition)
        let today = calendar.startOfDay(for: now)

        switch range {
        case .absolute(let start, let end):
            let from = calendar.startOfDay(for: min(start, end))
            let toDay = calendar.startOfDay(for: max(start, end))
            // Inclusive of the end day: someone picking Mar 1–Mar 7 means seven
            // days, not six and a sliver.
            let to = calendar.date(byAdding: .day, value: 1, to: toDay) ?? toDay
            return DateInterval(start: from, end: to)

        case .lastDays(let days):
            let span = max(1, days)
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            let start = calendar.date(byAdding: .day, value: -(span - 1), to: today) ?? today
            return DateInterval(start: start, end: end)

        case .lastCompleteWeeks(let count):
            let weeks = max(1, count)
            let thisWeekStart = startOfWeek(containing: today, calendar: calendar)
            let end = thisWeekStart
            let start = calendar.date(byAdding: .day, value: -7 * weeks, to: thisWeekStart) ?? thisWeekStart
            return DateInterval(start: start, end: end)

        case .monthToDate:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            return DateInterval(start: start, end: end)

        case .yearToDate:
            let start = calendar.date(from: calendar.dateComponents([.year], from: today)) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            return DateInterval(start: start, end: end)
        }
    }

    /// The start of the week a date falls in, per the report's own week start.
    ///
    /// Computed by walking back from the day rather than via
    /// `dateInterval(of: .weekOfYear:)`, which quietly ignores a `firstWeekday`
    /// that isn't the locale's on some calendars.
    public func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -delta, to: day) ?? day
    }

    // MARK: Building

    public func build(
        _ definition: ReportDefinition,
        trackers: [Tracker],
        entriesByTracker: [UUID: [Entry]],
        now: Date = .now
    ) -> CustomReport {
        let interval = resolve(definition.range, for: definition, now: now)
        let calendar = calendar(for: definition)

        // The report's own order, not the dashboard's.
        let ordered = definition.trackerIDs.compactMap { id in
            trackers.first { $0.id == id }
        }

        let built = ordered.map { tracker -> CustomReportTracker in
            let entries = filtered(
                entriesByTracker[tracker.id] ?? [],
                to: interval,
                weekdays: definition.weekdays,
                calendar: calendar
            )
            let aggregation = tracker.currentGoal?.aggregation ?? tracker.kind.defaultAggregation
            let sections = definition.orderedBreakdowns.map { breakdown in
                CustomReportSection(
                    breakdown: breakdown,
                    buckets: buckets(
                        for: breakdown,
                        entries: entries,
                        interval: interval,
                        calendar: calendar,
                        aggregation: aggregation,
                        weekdays: definition.weekdays
                    )
                )
            }
            return CustomReportTracker(
                trackerID: tracker.id,
                title: tracker.title,
                unit: tracker.currentGoal?.unit ?? tracker.kind.defaultUnit,
                symbolName: tracker.symbolName,
                colorHex: tracker.colorHex,
                aggregation: aggregation,
                sections: sections,
                total: aggregation.apply(to: entries.map(\.value)),
                entryCount: entries.count
            )
        }

        return CustomReport(definition: definition, interval: interval, generatedAt: now, trackers: built)
    }

    /// Entries inside the range, on the weekdays that count.
    private func filtered(
        _ entries: [Entry],
        to interval: DateInterval,
        weekdays: Set<Int>,
        calendar: Calendar
    ) -> [Entry] {
        entries.filter { entry in
            guard entry.date >= interval.start, entry.date < interval.end else { return false }
            guard !weekdays.isEmpty else { return true }
            return weekdays.contains(calendar.component(.weekday, from: entry.date))
        }
    }

    // MARK: Buckets

    private func buckets(
        for breakdown: ReportBreakdown,
        entries: [Entry],
        interval: DateInterval,
        calendar: Calendar,
        aggregation: Aggregation,
        weekdays: Set<Int>
    ) -> [ReportBucket] {
        switch breakdown {
        case .total:
            return [ReportBucket(
                label: "Total",
                interval: interval,
                value: aggregation.apply(to: entries.map(\.value)),
                entryCount: entries.count
            )]

        case .daily:
            return walk(interval, by: .day, calendar: calendar) { start, end in
                // A filtered-out weekday is omitted rather than shown as zero:
                // a Mon–Fri report listing Saturday at 0 reads as a failure
                // rather than a day that was never in scope.
                guard weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: start))
                else { return nil }
                return (Formatters.shortDay(start), DateInterval(start: start, end: end))
            } aggregate: { bucketInterval in
                slice(entries, in: bucketInterval, aggregation: aggregation)
            }

        case .weekly:
            let firstWeek = startOfWeek(containing: interval.start, calendar: calendar)
            return walk(
                DateInterval(start: firstWeek, end: interval.end),
                by: .weekOfYear,
                calendar: calendar
            ) { start, end in
                (Formatters.shortDay(start), DateInterval(start: start, end: end))
            } aggregate: { bucketInterval in
                slice(entries, in: bucketInterval, aggregation: aggregation)
            }

        case .monthly:
            let firstMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: interval.start)
            ) ?? interval.start
            return walk(
                DateInterval(start: firstMonth, end: interval.end),
                by: .month,
                calendar: calendar
            ) { start, end in
                (Formatters.monthYear(start), DateInterval(start: start, end: end))
            } aggregate: { bucketInterval in
                slice(entries, in: bucketInterval, aggregation: aggregation)
            }

        case .yearly:
            let firstYear = calendar.date(
                from: calendar.dateComponents([.year], from: interval.start)
            ) ?? interval.start
            return walk(
                DateInterval(start: firstYear, end: interval.end),
                by: .year,
                calendar: calendar
            ) { start, end in
                (Formatters.year(start), DateInterval(start: start, end: end))
            } aggregate: { bucketInterval in
                slice(entries, in: bucketInterval, aggregation: aggregation)
            }
        }
    }

    /// Steps through an interval one calendar unit at a time.
    ///
    /// `label` returning nil skips that step, which is how filtered-out weekdays
    /// are dropped rather than drawn as zeroes.
    private func walk(
        _ interval: DateInterval,
        by component: Calendar.Component,
        calendar: Calendar,
        label: (Date, Date) -> (String, DateInterval)?,
        aggregate: (DateInterval) -> (value: Double, count: Int)
    ) -> [ReportBucket] {
        var result: [ReportBucket] = []
        var cursor = interval.start
        // A guard against a calendar that fails to advance: without it a
        // date-arithmetic failure spins here forever.
        var guardCount = 0

        while cursor < interval.end, guardCount < 5_000 {
            guardCount += 1
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            let capped = min(next, interval.end)
            if let (text, bucketInterval) = label(cursor, capped) {
                let (value, count) = aggregate(bucketInterval)
                result.append(ReportBucket(
                    label: text,
                    interval: bucketInterval,
                    value: value,
                    entryCount: count
                ))
            }
            cursor = next
        }
        return result
    }

    private func slice(
        _ entries: [Entry],
        in interval: DateInterval,
        aggregation: Aggregation
    ) -> (value: Double, count: Int) {
        let matching = entries.filter { $0.date >= interval.start && $0.date < interval.end }
        return (aggregation.apply(to: matching.map(\.value)), matching.count)
    }
}
