import Foundation

/// Shared number and date formatting so every chart, widget and report says the
/// same thing the same way.
public enum Formatters {

    // MARK: Numbers

    /// Trims pointless decimals: 5 renders as "5", 5.25 as "5.25", 5.20 as "5.2".
    public static func number(_ value: Double, maximumFractionDigits: Int = 2) -> String {
        if value.isNaN || value.isInfinite { return "—" }
        if value.rounded() == value && abs(value) < 1_000_000 {
            return String(Int(value))
        }
        return value.formatted(
            .number.precision(.fractionLength(0...maximumFractionDigits))
        )
    }

    /// A value with its unit attached. Durations get an h/m breakdown instead.
    public static func value(_ value: Double, unit: String) -> String {
        if unit == "min" { return duration(minutes: value) }
        guard !unit.isEmpty else { return number(value) }
        if unit.hasPrefix("/") { return "\(number(value))\(unit)" }
        return "\(number(value)) \(unit)"
    }

    /// 90 → "1h 30m", 45 → "45m", 120 → "2h".
    public static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        guard total >= 60 else { return "\(total)m" }
        let hours = total / 60
        let remainder = total % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    /// Clamped to 0...1 on the way in, rendered whole: 0.734 → "73%".
    public static func percent(_ fraction: Double) -> String {
        if fraction.isNaN { return "—" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// Signed delta for trend labels: +12%, −4%.
    public static func signedPercent(_ fraction: Double) -> String {
        if fraction.isNaN || fraction.isInfinite { return "—" }
        let pct = Int((fraction * 100).rounded())
        if pct == 0 { return "0%" }
        return pct > 0 ? "+\(pct)%" : "\u{2212}\(abs(pct))%"
    }

    /// Compact axis labels: 1500 → "1.5K", 2_400_000 → "2.4M".
    public static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        switch magnitude {
        case 1_000_000...:
            return "\(number(value / 1_000_000, maximumFractionDigits: 1))M"
        case 10_000...:
            return "\(number(value / 1_000, maximumFractionDigits: 0))K"
        case 1_000...:
            return "\(number(value / 1_000, maximumFractionDigits: 1))K"
        default:
            return number(value, maximumFractionDigits: 1)
        }
    }

    // MARK: Streaks

    /// "12 days", "1 day", "no streak yet".
    public static func streak(_ days: Int) -> String {
        switch days {
        case ..<1: "No streak yet"
        case 1: "1 day"
        default: "\(days) days"
        }
    }

    // MARK: Dates

    /// "Mon", used on weekly axes.
    public static func weekdayShort(_ date: Date, calendar: Calendar = .current) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    /// "Sep 17"
    public static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Relative where it reads naturally, absolute where it doesn't.
    /// Today/Yesterday get words; anything older gets a date.
    public static func friendlyDay(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let days = calendar.dateComponents([.day], from: date, to: .now).day ?? 0
        if days > 0 && days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return dayMonth(date)
    }

    /// "Sep 11 – Sep 17", the label on a weekly report.
    public static func range(_ interval: DateInterval) -> String {
        let end = interval.end.addingTimeInterval(-1)
        return "\(dayMonth(interval.start)) – \(dayMonth(end))"
    }

    /// Filename-safe stamp: "2026-09-17".
    public static func fileStamp(_ date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
