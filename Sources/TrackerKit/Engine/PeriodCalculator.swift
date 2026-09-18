import Foundation

// MARK: - Period

/// One goal window — the stretch of time a target applies to.
public struct Period: Identifiable, Sendable, Hashable {
    public let interval: DateInterval
    public let cadence: Cadence

    public var id: Date { interval.start }
    public var start: Date { interval.start }
    /// Exclusive upper bound.
    public var end: Date { interval.end }

    public init(interval: DateInterval, cadence: Cadence) {
        self.interval = interval
        self.cadence = cadence
    }

    public func contains(_ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }

    /// Axis-length label: "Mon", "Sep 17", "Sep", "Q3", "2026".
    public func shortLabel(calendar: Calendar = .current) -> String {
        switch cadence {
        case .daily:
            return Formatters.weekdayShort(start, calendar: calendar)
        case .weekly:
            return Formatters.dayMonth(start)
        case .monthly:
            return start.formatted(.dateTime.month(.abbreviated))
        case .quarterly:
            let quarter = (calendar.component(.month, from: start) - 1) / 3 + 1
            return "Q\(quarter)"
        case .yearly:
            return start.formatted(.dateTime.year())
        case .total:
            return "All time"
        }
    }

    /// Full label for tooltips and report rows.
    public func label(calendar: Calendar = .current) -> String {
        switch cadence {
        case .daily:
            return Formatters.friendlyDay(start, calendar: calendar)
        case .weekly:
            return "Week of \(Formatters.dayMonth(start))"
        case .monthly:
            return start.formatted(.dateTime.month(.wide).year())
        case .quarterly:
            let quarter = (calendar.component(.month, from: start) - 1) / 3 + 1
            return "Q\(quarter) \(start.formatted(.dateTime.year()))"
        case .yearly:
            return start.formatted(.dateTime.year())
        case .total:
            return "All time"
        }
    }
}

// MARK: - PeriodCalculator

/// Turns dates into goal windows.
///
/// Everything time-shaped in TrackerKit routes through here so that "this week"
/// means the same thing in a chart, a streak, a stoplight and a report. It carries
/// its own `Calendar`, which is what makes the whole library testable — tests pin
/// a fixed timezone and first-weekday rather than inheriting the device's.
public struct PeriodCalculator: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// A calculator pinned to UTC with Sunday as the first weekday.
    /// Use in tests so results don't move with the machine's locale.
    public static let fixed: PeriodCalculator = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 1
        return PeriodCalculator(calendar: calendar)
    }()

    // MARK: Days

    public func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    /// Whole calendar days from `start` to `end`. Negative when `end` precedes `start`.
    public func dayCount(from start: Date, to end: Date) -> Int {
        calendar.dateComponents(
            [.day],
            from: startOfDay(start),
            to: startOfDay(end)
        ).day ?? 0
    }

    /// Every day from `start` through `end`, inclusive of both.
    public func days(from start: Date, through end: Date) -> [Date] {
        guard start <= end else { return [] }
        var result: [Date] = []
        var cursor = startOfDay(start)
        let limit = startOfDay(end)
        // Guard against a pathological range locking the UI.
        while cursor <= limit, result.count < 4000 {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// The last `count` days ending today, oldest first.
    public func trailingDays(_ count: Int, endingAt end: Date = .now) -> [Date] {
        let last = startOfDay(end)
        guard count > 0,
              let first = calendar.date(byAdding: .day, value: -(count - 1), to: last)
        else { return [] }
        return days(from: first, through: last)
    }

    // MARK: Periods

    /// The window of `cadence` that `date` falls inside.
    ///
    /// - Parameter anchor: only used by `.total`, which has no natural start —
    ///   pass the tracker's creation date so "all time" begins where the data does.
    public func period(for cadence: Cadence, containing date: Date, anchor: Date? = nil) -> Period {
        guard let component = cadence.calendarComponent else {
            // .total — one open window from the anchor forward.
            let start = anchor.map(startOfDay) ?? Date.distantPast
            let end = calendar.date(byAdding: .year, value: 100, to: startOfDay(date)) ?? Date.distantFuture
            return Period(interval: DateInterval(start: start, end: end), cadence: cadence)
        }

        if let interval = calendar.dateInterval(of: component, for: date) {
            return Period(interval: interval, cadence: cadence)
        }

        // `.quarter` is unreliable on some calendars; derive it by hand.
        if component == .quarter {
            let month = calendar.component(.month, from: date)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var components = calendar.dateComponents([.year], from: date)
            components.month = quarterStartMonth
            components.day = 1
            if let start = calendar.date(from: components),
               let end = calendar.date(byAdding: .month, value: 3, to: start) {
                return Period(interval: DateInterval(start: start, end: end), cadence: cadence)
            }
        }

        let day = startOfDay(date)
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        return Period(interval: DateInterval(start: day, end: next), cadence: cadence)
    }

    /// Every period of `cadence` that overlaps `range`, oldest first.
    public func periods(for cadence: Cadence, in range: DateInterval) -> [Period] {
        guard cadence.calendarComponent != nil else {
            return [period(for: cadence, containing: range.start, anchor: range.start)]
        }

        var result: [Period] = []
        var cursor = range.start
        // Cap the count so a wide range with a daily cadence can't stall a view.
        while cursor < range.end, result.count < 1200 {
            let current = period(for: cadence, containing: cursor)
            result.append(current)
            guard current.end > cursor else { break }
            cursor = current.end
        }
        return result
    }

    /// The last `count` periods ending with the one containing `end`, oldest first.
    public func trailingPeriods(_ count: Int, cadence: Cadence, endingAt end: Date = .now) -> [Period] {
        guard count > 0, let component = cadence.calendarComponent else {
            return [period(for: cadence, containing: end, anchor: end)]
        }
        var result: [Period] = []
        var cursor = end
        for _ in 0..<count {
            result.append(period(for: cadence, containing: cursor))
            guard let previous = calendar.date(byAdding: component, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return result.reversed()
    }

    /// The period immediately before `period` — the comparison window for trends.
    public func previous(_ period: Period) -> Period? {
        guard let component = period.cadence.calendarComponent,
              let earlier = calendar.date(byAdding: component, value: -1, to: period.start)
        else { return nil }
        return self.period(for: period.cadence, containing: earlier)
    }

    // MARK: Pacing

    /// How far through a period we are, 0...1.
    ///
    /// This is what separates "behind" from "off track": two days into a week with
    /// 0 of 5 workouts is fine; six days in it is not.
    public func fractionElapsed(of period: Period, at date: Date = .now) -> Double {
        guard period.cadence != .total else { return 1 }
        let span = period.end.timeIntervalSince(period.start)
        guard span > 0 else { return 1 }
        let elapsed = date.timeIntervalSince(period.start)
        return min(max(elapsed / span, 0), 1)
    }

    /// Days remaining in the period, counting today as remaining.
    public func daysRemaining(in period: Period, from date: Date = .now) -> Int {
        guard period.cadence != .total else { return 0 }
        let end = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.end
        return max(0, dayCount(from: date, to: end))
    }
}
