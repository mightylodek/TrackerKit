import Foundation
import SwiftUI

// MARK: - TrackerKind

/// The kind of thing a tracker measures. Drives the logging UI, the default
/// aggregation, and how values are formatted for display.
public enum TrackerKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// A yes/no habit. Entries are 0 or 1. "Did I do it today?"
    case checkbox
    /// A whole-number tally. Reps, glasses of water, pages read.
    case count
    /// Elapsed time, stored in **minutes**.
    case duration
    /// An arbitrary continuous measurement with a unit. Weight, miles, dollars.
    case amount
    /// A bounded subjective score, 1...5 by default.
    case rating

    public var displayName: String {
        switch self {
        case .checkbox: "Yes / No"
        case .count: "Count"
        case .duration: "Duration"
        case .amount: "Amount"
        case .rating: "Rating"
        }
    }

    public var symbolName: String {
        switch self {
        case .checkbox: "checkmark.circle"
        case .count: "number"
        case .duration: "clock"
        case .amount: "chart.line.uptrend.xyaxis"
        case .rating: "star"
        }
    }

    /// Entries of this kind collapse to a single value per day rather than summing.
    public var isSingleValuePerDay: Bool {
        switch self {
        case .checkbox, .rating: true
        case .count, .duration, .amount: false
        }
    }

    /// How multiple entries inside one period roll up into a single number.
    public var defaultAggregation: Aggregation {
        switch self {
        case .checkbox: .max
        case .count, .duration, .amount: .sum
        case .rating: .average
        }
    }

    /// The step used by steppers and the default quick-log button.
    public var defaultIncrement: Double {
        switch self {
        case .checkbox: 1
        case .count: 1
        case .duration: 5
        case .amount: 1
        case .rating: 1
        }
    }

    public var defaultUnit: String {
        switch self {
        case .checkbox: ""
        case .count: "x"
        case .duration: "min"
        case .amount: ""
        case .rating: "/5"
        }
    }
}

// MARK: - Aggregation

/// How a set of entries inside a period becomes one number.
public enum Aggregation: String, Codable, Sendable, CaseIterable, Hashable {
    case sum
    case average
    case max
    case min
    case latest

    public func apply(to values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        switch self {
        case .sum: return values.reduce(0, +)
        case .average: return values.reduce(0, +) / Double(values.count)
        case .max: return values.max() ?? 0
        case .min: return values.min() ?? 0
        case .latest: return values.last ?? 0
        }
    }

    public var displayName: String {
        switch self {
        case .sum: "Total"
        case .average: "Average"
        case .max: "Best"
        case .min: "Lowest"
        case .latest: "Most recent"
        }
    }
}

// MARK: - Cadence

/// The window a goal target applies to. A target of 5 with a `.weekly` cadence
/// means "5 per week", and progress resets every week.
public enum Cadence: String, Codable, Sendable, CaseIterable, Hashable {
    case daily
    case weekly
    case monthly
    case quarterly
    case yearly
    /// No reset. Progress accumulates forever toward the target.
    case total

    public var displayName: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        case .total: "All time"
        }
    }

    /// Short suffix used after a target, e.g. "5 / wk".
    public var shortSuffix: String {
        switch self {
        case .daily: "day"
        case .weekly: "wk"
        case .monthly: "mo"
        case .quarterly: "qtr"
        case .yearly: "yr"
        case .total: "total"
        }
    }

    /// The `Calendar.Component` this cadence buckets by, if any.
    public var calendarComponent: Calendar.Component? {
        switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .quarterly: .quarter
        case .yearly: .year
        case .total: nil
        }
    }

    /// Roughly how many days one period spans. Used for pacing math only.
    public var approximateDayCount: Double {
        switch self {
        case .daily: 1
        case .weekly: 7
        case .monthly: 30.44
        case .quarterly: 91.31
        case .yearly: 365.25
        case .total: 365.25
        }
    }

    /// Whether a streak can meaningfully be counted at this cadence.
    public var supportsStreaks: Bool { self != .total }
}

// MARK: - GoalDirection

/// Which side of the target counts as success.
public enum GoalDirection: String, Codable, Sendable, CaseIterable, Hashable {
    /// Hit the target or beat it. "At least 3 workouts a week."
    case atLeast
    /// Stay under the target. "No more than 2 sodas a day."
    case atMost
    /// Land on the target. "Exactly 8 hours of sleep."
    case exactly

    public var displayName: String {
        switch self {
        case .atLeast: "At least"
        case .atMost: "At most"
        case .exactly: "Exactly"
        }
    }

    public var symbolName: String {
        switch self {
        case .atLeast: "arrow.up.right"
        case .atMost: "arrow.down.right"
        case .exactly: "target"
        }
    }

    /// True when `value` satisfies `target` in this direction.
    /// `tolerance` only applies to `.exactly`.
    public func isSatisfied(value: Double, target: Double, tolerance: Double = 0.0001) -> Bool {
        switch self {
        case .atLeast: value >= target - tolerance
        case .atMost: value <= target + tolerance
        case .exactly: abs(value - target) <= max(tolerance, target * 0.02)
        }
    }
}

// MARK: - StoplightStatus

/// Traffic-light rating of progress toward a goal. Deliberately coarse — this is
/// the "how am I doing" glance, not the number.
public enum StoplightStatus: String, Codable, Sendable, CaseIterable, Hashable, Comparable {
    /// On or ahead of pace.
    case green
    /// Behind pace but still reachable.
    case yellow
    /// Off pace badly enough to need attention.
    case red
    /// No goal set, or not enough data to judge.
    case neutral

    public var displayName: String {
        switch self {
        case .green: "On track"
        case .yellow: "At risk"
        case .red: "Off track"
        case .neutral: "No data"
        }
    }

    public var symbolName: String {
        switch self {
        case .green: "checkmark.circle.fill"
        case .yellow: "exclamationmark.triangle.fill"
        case .red: "xmark.octagon.fill"
        case .neutral: "minus.circle"
        }
    }

    /// Ordering runs best → worst so `min()` over a set finds the worst offender.
    private var rank: Int {
        switch self {
        case .green: 0
        case .yellow: 1
        case .red: 2
        case .neutral: 3
        }
    }

    public static func < (lhs: StoplightStatus, rhs: StoplightStatus) -> Bool {
        lhs.rank < rhs.rank
    }
}

// MARK: - TrendDirection

/// Direction of travel between two comparable periods.
public enum TrendDirection: String, Codable, Sendable, CaseIterable, Hashable {
    case rising
    case falling
    case flat

    public var symbolName: String {
        switch self {
        case .rising: "arrow.up.right"
        case .falling: "arrow.down.right"
        case .flat: "arrow.right"
        }
    }

    /// Whether this direction is *good*, which depends on the goal direction.
    /// A rising soda count is bad; a rising workout count is good.
    public func isFavorable(for direction: GoalDirection) -> Bool {
        switch (self, direction) {
        case (.rising, .atLeast), (.falling, .atMost): true
        case (.flat, _): true
        default: false
        }
    }
}

// MARK: - ExportChannel

/// How a scheduled report leaves the device. Both channels open a system
/// composer pre-filled with the report — nothing sends without a human tap.
public enum ExportChannel: String, Codable, Sendable, CaseIterable, Hashable {
    case email
    case message
    /// Hand the file to the share sheet and let the user pick.
    case shareSheet

    public var displayName: String {
        switch self {
        case .email: "Email"
        case .message: "Text message"
        case .shareSheet: "Share sheet"
        }
    }

    public var symbolName: String {
        switch self {
        case .email: "envelope.fill"
        case .message: "message.fill"
        case .shareSheet: "square.and.arrow.up"
        }
    }
}

// MARK: - ReportFormat

/// Serialization format for an exported report.
public enum ReportFormat: String, Codable, Sendable, CaseIterable, Hashable {
    case csv
    case markdown
    case html
    case pdf

    public var fileExtension: String { rawValue }

    public var mimeType: String {
        switch self {
        case .csv: "text/csv"
        case .markdown: "text/markdown"
        case .html: "text/html"
        case .pdf: "application/pdf"
        }
    }

    public var displayName: String {
        switch self {
        case .csv: "CSV"
        case .markdown: "Markdown"
        case .html: "HTML"
        case .pdf: "PDF"
        }
    }

    /// Formats that can be dropped into a text message body as-is.
    public var isInlineText: Bool {
        switch self {
        case .csv, .markdown: true
        case .html, .pdf: false
        }
    }
}

// MARK: - ProfileRole

/// Distinguishes the adult who owns the device from the kids logging on it.
/// Only `.owner` profiles can see other profiles' data or change export settings.
public enum ProfileRole: String, Codable, Sendable, CaseIterable, Hashable {
    case owner
    case member

    public var displayName: String {
        switch self {
        case .owner: "Owner"
        case .member: "Member"
        }
    }
}

// MARK: - ReportFrequency

/// How often a scheduled report fires.
public enum ReportFrequency: String, Codable, Sendable, CaseIterable, Hashable {
    case daily
    case weekly
    case monthly

    public var displayName: String {
        switch self {
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }

    /// Whether a weekday needs picking. A daily report has no weekday to choose,
    /// and a monthly one runs on a date instead.
    public var needsWeekday: Bool { self == .weekly }
    public var needsDayOfMonth: Bool { self == .monthly }
}
