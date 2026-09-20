import Foundation

// MARK: - ReportBreakdown

/// A level of grouping a report can show. Additive — a report may carry several,
/// so "every day, and a total" is one report rather than two.
public enum ReportBreakdown: String, Codable, Sendable, CaseIterable, Hashable, Comparable {
    case daily
    case weekly
    case monthly
    case yearly
    case total

    public var displayName: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        case .total: "Total"
        }
    }

    /// Finest first, so sections read from detail up to the headline.
    private var order: Int {
        switch self {
        case .daily: 0
        case .weekly: 1
        case .monthly: 2
        case .yearly: 3
        case .total: 4
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

// MARK: - ReportRange

/// What span a report covers.
///
/// Absolute and relative are genuinely different intentions, not two spellings
/// of one: an absolute range is a fixed record ("that fortnight in March") and
/// keeps saying the same thing forever, while a relative one re-resolves every
/// time it runs, which is what a scheduled report needs.
public enum ReportRange: Codable, Sendable, Hashable {
    /// Fixed dates. Says the same thing whenever it runs.
    case absolute(start: Date, end: Date)
    /// The last `days` days, ending today. Re-resolves on every run.
    case lastDays(Int)
    /// The last `count` complete weeks, honouring the report's own week start.
    /// Excludes the week in progress, so a Friday-to-Thursday report run on a
    /// Tuesday covers the week that finished, not two days of a partial one.
    case lastCompleteWeeks(Int)
    /// This calendar month so far.
    case monthToDate
    /// This calendar year so far.
    case yearToDate

    public var displayName: String {
        switch self {
        case .absolute: "Set dates"
        case .lastDays(let n): "Last \(n) day\(n == 1 ? "" : "s")"
        case .lastCompleteWeeks(let n): "Last \(n) complete week\(n == 1 ? "" : "s")"
        case .monthToDate: "Month so far"
        case .yearToDate: "Year so far"
        }
    }

    /// Whether this range moves with the calendar. A scheduled report wants one
    /// that does; a fixed record wants one that doesn't.
    public var isRelative: Bool {
        if case .absolute = self { return false }
        return true
    }
}

// MARK: - ReportDefinition

/// A saved report: which habits, over what span, grouped how.
///
/// Persisted as JSON on the profile rather than as its own SwiftData entity —
/// it is read and written whole, and nothing queries across definitions.
public struct ReportDefinition: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var profileID: UUID

    /// One or more habits. Order is the report's own, not the dashboard's.
    public var trackerIDs: [UUID]

    public var range: ReportRange

    /// Which weekdays count, as `Calendar` numbers (1 = Sunday … 7 = Saturday).
    /// Empty means every day — stored as empty rather than all seven so "I never
    /// filtered" and "I ticked all of them" stay distinguishable.
    public var weekdays: Set<Int>

    /// Which day a week starts on for this report (1 = Sunday … 7 = Saturday).
    ///
    /// Separate from the weekday filter and often confused with it: a
    /// Friday-to-Thursday reading week is `firstWeekday = 6` with no filter,
    /// whereas "only weekdays" is a filter of Mon–Fri on any week start.
    public var firstWeekday: Int

    /// Which groupings to show. Never empty in practice — the builder falls back
    /// to `.total` rather than rendering nothing.
    public var breakdowns: Set<ReportBreakdown>

    /// Which charts to draw, in the order they appear on the page.
    ///
    /// Empty means a table-only report, which is a legitimate choice rather than
    /// an unfinished one — the numbers are often the point.
    public var visuals: [ReportVisual]

    /// The schedule that sends this report, if it is on one.
    public var scheduleID: UUID?

    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        profileID: UUID,
        trackerIDs: [UUID],
        range: ReportRange = .lastDays(7),
        weekdays: Set<Int> = [],
        firstWeekday: Int = 1,
        breakdowns: Set<ReportBreakdown> = [.daily, .total],
        visuals: [ReportVisual] = [],
        scheduleID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.profileID = profileID
        self.trackerIDs = trackerIDs
        self.range = range
        self.weekdays = weekdays
        self.firstWeekday = min(max(firstWeekday, 1), 7)
        self.breakdowns = breakdowns.isEmpty ? [.total] : breakdowns
        self.visuals = visuals
        self.scheduleID = scheduleID
        self.createdAt = createdAt
    }

    /// Ordered finest-first, so a report reads from detail up to the headline.
    public var orderedBreakdowns: [ReportBreakdown] {
        breakdowns.sorted()
    }

    public var filtersWeekdays: Bool { !weekdays.isEmpty && weekdays.count < 7 }

    /// "Mon, Tue, Wed" — or nil when every day counts.
    public var weekdaySummary: String? {
        guard filtersWeekdays else { return nil }
        let symbols = Calendar(identifier: .gregorian).shortWeekdaySymbols
        return weekdays.sorted()
            .compactMap { index in
                guard index >= 1, index <= symbols.count else { return nil }
                return symbols[index - 1]
            }
            .joined(separator: ", ")
    }

    /// "Friday" — the day this report's weeks begin on.
    public var weekStartName: String {
        let symbols = Calendar(identifier: .gregorian).weekdaySymbols
        guard firstWeekday >= 1, firstWeekday <= symbols.count else { return symbols[0] }
        return symbols[firstWeekday - 1]
    }

    /// One line describing the whole thing, for a list row.
    public var summary: String {
        var parts = [range.displayName]
        if let weekdaySummary { parts.append(weekdaySummary) }
        if breakdowns.contains(.weekly) { parts.append("weeks from \(weekStartName)") }
        return parts.joined(separator: " · ")
    }
}
