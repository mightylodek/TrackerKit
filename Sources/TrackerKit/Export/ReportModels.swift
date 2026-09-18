import Foundation

// MARK: - ReportItem

/// One tracker's line in a progress report.
public struct ReportItem: Identifiable, Sendable, Hashable {
    public let trackerID: UUID
    public let title: String
    public let detail: String
    public let symbolName: String
    public let colorHex: String
    public let kind: TrackerKind

    /// The goal governing the reporting window.
    public let goal: GoalVersion?
    /// Aggregated value across the window.
    public let actual: Double
    public let target: Double?
    public let status: StoplightStatus
    public let statusReason: String
    /// Movement against the previous comparable window.
    public let trend: Trend?
    public let streak: StreakSummary
    /// Day-by-day values across the window, oldest first.
    public let dailyValues: [DailyValue]
    /// Per-period scoring inside the window, for the sparkline and the table.
    public let periods: [ProgressSnapshot]
    /// True when the goal was changed during the reporting window — worth calling
    /// out, because the numbers are being compared across a moved goalpost.
    public let goalChangedInWindow: Bool

    public var id: UUID { trackerID }
    public var unit: String { goal?.unit ?? kind.defaultUnit }

    public var actualText: String { Formatters.value(actual, unit: unit) }
    public var targetText: String? { target.map { Formatters.value($0, unit: unit) } }

    /// "42 / 60 min" or just "42 min" when there's no goal.
    public var progressText: String {
        guard let targetText else { return actualText }
        return "\(actualText) / \(targetText)"
    }

    public var completionFraction: Double? {
        guard let target, target != 0 else { return nil }
        return actual / target
    }

    public init(
        trackerID: UUID,
        title: String,
        detail: String,
        symbolName: String,
        colorHex: String,
        kind: TrackerKind,
        goal: GoalVersion?,
        actual: Double,
        target: Double?,
        status: StoplightStatus,
        statusReason: String,
        trend: Trend?,
        streak: StreakSummary,
        dailyValues: [DailyValue],
        periods: [ProgressSnapshot],
        goalChangedInWindow: Bool
    ) {
        self.trackerID = trackerID
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.kind = kind
        self.goal = goal
        self.actual = actual
        self.target = target
        self.status = status
        self.statusReason = statusReason
        self.trend = trend
        self.streak = streak
        self.dailyValues = dailyValues
        self.periods = periods
        self.goalChangedInWindow = goalChangedInWindow
    }
}

// MARK: - ProgressReport

/// A rendered-ready summary of one profile over one window.
///
/// The report is built once as data, then handed to whichever renderer the
/// delivery channel needs. A text message and a PDF say the same things because
/// they come from the same struct.
public struct ProgressReport: Sendable, Hashable {
    public let profileID: UUID
    public let profileName: String
    public let interval: DateInterval
    public let generatedAt: Date
    public let loginStreak: StreakSummary
    public let items: [ReportItem]

    public init(
        profileID: UUID,
        profileName: String,
        interval: DateInterval,
        generatedAt: Date = .now,
        loginStreak: StreakSummary,
        items: [ReportItem]
    ) {
        self.profileID = profileID
        self.profileName = profileName
        self.interval = interval
        self.generatedAt = generatedAt
        self.loginStreak = loginStreak
        self.items = items
    }

    /// "Sep 11 – Sep 17"
    public var rangeText: String { Formatters.range(interval) }

    /// "Alex — Sep 11 – Sep 17"
    public var title: String { "\(profileName) — \(rangeText)" }

    public var scoredItems: [ReportItem] { items.filter { $0.status != .neutral } }

    public var greenCount: Int { items.filter { $0.status == .green }.count }
    public var yellowCount: Int { items.filter { $0.status == .yellow }.count }
    public var redCount: Int { items.filter { $0.status == .red }.count }

    /// Share of scored goals sitting green.
    public var greenShare: Double {
        guard !scoredItems.isEmpty else { return 0 }
        return Double(greenCount) / Double(scoredItems.count)
    }

    public var worstStatus: StoplightStatus {
        scoredItems.map(\.status).max() ?? .neutral
    }

    /// The one-sentence version, used as the notification body and the SMS opener.
    public var headline: String {
        guard !scoredItems.isEmpty else {
            return "\(profileName): \(items.count) tracked, no goals set yet."
        }
        return "\(profileName): \(greenCount) of \(scoredItems.count) goals on track"
            + (redCount > 0 ? ", \(redCount) off track." : ".")
    }

    /// Items worth calling out first — anything red, then anything at risk.
    public var attentionItems: [ReportItem] {
        items
            .filter { $0.status == .red || $0.status == .yellow }
            .sorted { $0.status > $1.status }
    }

    /// Items that had a good week, for the positive half of the summary.
    public var winItems: [ReportItem] {
        items
            .filter { $0.status == .green }
            .sorted { ($0.completionFraction ?? 0) > ($1.completionFraction ?? 0) }
    }

    /// A filename stem like `alex-progress-2026-09-17`.
    public var fileStem: String {
        let slug = profileName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "\(slug.isEmpty ? "profile" : slug)-progress-\(Formatters.fileStamp(interval.end))"
    }
}
