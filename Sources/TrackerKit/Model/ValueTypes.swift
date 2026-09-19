import Foundation
import SwiftUI

// MARK: - Profile

/// One person logging on this device. A shared iPad can hold many.
///
/// Profiles are the top-level partition for every other type: trackers, entries,
/// login days and export schedules all belong to exactly one profile.
public struct Profile: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    /// Hex string like `#34C759`. Drives this profile's accent throughout the UI.
    public var colorHex: String
    /// SF Symbol shown on the profile chip and picker tile.
    public var symbolName: String
    public var role: ProfileRole
    public var createdAt: Date
    /// Whether a 4-digit PIN guards this profile. The PIN itself never lives here —
    /// it is salted, hashed and stored in the keychain. See ``PINManager``.
    public var isPINProtected: Bool
    /// Sort order in the profile picker.
    public var sortIndex: Int

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#0A84FF",
        symbolName: String = "person.fill",
        role: ProfileRole = .member,
        createdAt: Date = .now,
        isPINProtected: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.role = role
        self.createdAt = createdAt
        self.isPINProtected = isPINProtected
        self.sortIndex = sortIndex
    }

    public var color: Color { Color(hex: colorHex) }

    /// First initial, used on the avatar when no symbol is set.
    public var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }
}

// MARK: - GoalVersion

/// A goal as it stood during one stretch of time.
///
/// Goals are **append-only history**, never edits in place. Raising a target from
/// 3 to 5 workouts a week writes a new version effective today and leaves the old
/// one intact, so a chart of last month still renders against the target that was
/// actually in force back then. This is what makes "what was the goal at that
/// time?" answerable.
public struct GoalVersion: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    /// Start of the window this goal governs. The version with the latest
    /// `effectiveFrom` that is `<=` a given date is the one in force on that date.
    public var effectiveFrom: Date
    public var target: Double
    public var cadence: Cadence
    public var direction: GoalDirection
    /// Display unit, e.g. "min", "reps", "mi". Empty is fine.
    public var unit: String
    public var aggregation: Aggregation
    /// Optional free text — why the goal changed. Surfaces in the history view.
    public var note: String?

    public init(
        id: UUID = UUID(),
        effectiveFrom: Date = .now,
        target: Double,
        cadence: Cadence = .daily,
        direction: GoalDirection = .atLeast,
        unit: String = "",
        aggregation: Aggregation = .sum,
        note: String? = nil
    ) {
        self.id = id
        self.effectiveFrom = effectiveFrom
        self.target = target
        self.cadence = cadence
        self.direction = direction
        self.unit = unit
        self.aggregation = aggregation
        self.note = note
    }

    /// "At least 5 / wk"
    public var summary: String {
        let value = Formatters.value(target, unit: unit)
        return "\(direction.displayName) \(value) / \(cadence.shortSuffix)"
    }
}

// MARK: - Tracker

/// A single habit, goal or metric being tracked by one profile.
public struct Tracker: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var profileID: UUID
    public var title: String
    public var detail: String
    public var symbolName: String
    public var colorHex: String
    public var kind: TrackerKind
    public var isArchived: Bool
    public var sortIndex: Int
    public var createdAt: Date
    /// Every goal this tracker has ever had, oldest first. May be empty —
    /// a tracker with no goal is a plain log, still chartable, never stoplit.
    public var goalHistory: [GoalVersion]
    /// Optional daily reminder, stored as minutes past midnight.
    public var reminderMinutes: Int?
    /// How much one tap of the quick-log button adds. `nil` derives it from the
    /// goal — see ``quickLogStep``.
    public var quickLogIncrement: Double?

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        title: String,
        detail: String = "",
        symbolName: String = "target",
        colorHex: String = "#0A84FF",
        kind: TrackerKind = .checkbox,
        isArchived: Bool = false,
        sortIndex: Int = 0,
        createdAt: Date = .now,
        goalHistory: [GoalVersion] = [],
        reminderMinutes: Int? = nil,
        quickLogIncrement: Double? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.kind = kind
        self.isArchived = isArchived
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.goalHistory = goalHistory.sorted { $0.effectiveFrom < $1.effectiveFrom }
        self.reminderMinutes = reminderMinutes
        self.quickLogIncrement = quickLogIncrement
    }

    public var color: Color { Color(hex: colorHex) }

    /// The goal in force right now, if any.
    public var currentGoal: GoalVersion? { goal(on: .now) }

    /// The goal that was in force on `date`.
    ///
    /// Returns `nil` when the tracker had no goal yet on that date — which is
    /// correct and load-bearing: progress before the first goal is unscored, not
    /// scored against today's target.
    public func goal(on date: Date) -> GoalVersion? {
        goalHistory
            .filter { $0.effectiveFrom <= date }
            .max { $0.effectiveFrom < $1.effectiveFrom }
    }

    /// Goal versions paired with the date each stopped being in force.
    /// The newest version has an open end (`nil`).
    public var goalTimeline: [(goal: GoalVersion, endedAt: Date?)] {
        let sorted = goalHistory.sorted { $0.effectiveFrom < $1.effectiveFrom }
        return sorted.enumerated().map { index, goal in
            let next = index + 1 < sorted.count ? sorted[index + 1].effectiveFrom : nil
            return (goal, next)
        }
    }

    /// How much one tap of the quick-log button adds.
    ///
    /// Derived from the **goal**, not the kind, because the kind cannot possibly
    /// know. A step count and a glass of water are both `.amount`-ish and want
    /// increments three orders of magnitude apart: a per-kind constant meant
    /// `+` added 1 step against an 8,000 goal, which is 8,000 taps.
    ///
    /// The rule is roughly a twelfth of the target — about a dozen taps to
    /// complete a goal — snapped to a number a person would actually say out
    /// loud (1, 5, 10, 25, 100, 500…). An explicit ``quickLogIncrement``
    /// always wins, because some trackers just know better.
    public var quickLogStep: Double {
        if let quickLogIncrement, quickLogIncrement > 0 { return quickLogIncrement }
        guard kind != .checkbox, kind != .rating,
              let target = currentGoal?.target, target > 0
        else { return kind.defaultIncrement }

        // Derived steps are always whole units of at least one. A twelfth of
        // eight glasses is 0.67 and a twelfth of four workouts is 0.33 — nobody
        // logs half a glass or a quarter of a workout. Anyone who genuinely
        // needs a fractional step sets ``quickLogIncrement`` explicitly, which
        // is checked above and wins outright.
        return max(1, Tracker.niceStep(near: target / 12).rounded())
    }

    /// Snaps a raw amount to the nearest value a person would say out loud.
    static func niceStep(near raw: Double) -> Double {
        guard raw.isFinite, raw > 0 else { return 1 }
        let candidates: [Double] = [
            0.25, 0.5, 1, 2, 5, 10, 15, 20, 25, 50, 100, 150, 250, 500, 1000, 2500, 5000
        ]
        // Nearest in *log* space, so 60 lands on 50 rather than being dragged
        // toward the larger absolute neighbour.
        return candidates.min {
            abs(log($0) - log(raw)) < abs(log($1) - log(raw))
        } ?? 1
    }

    /// Unit taken from the current goal, falling back to the kind's default.
    public var unit: String {
        let goalUnit = currentGoal?.unit ?? ""
        return goalUnit.isEmpty ? kind.defaultUnit : goalUnit
    }
}

// MARK: - Entry

/// One logged data point.
public struct Entry: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var trackerID: UUID
    public var profileID: UUID
    /// The moment being logged *about*, not when it was typed in. Backfilling
    /// yesterday sets this to yesterday.
    public var date: Date
    public var value: Double
    public var note: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        trackerID: UUID,
        profileID: UUID,
        date: Date = .now,
        value: Double = 1,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.trackerID = trackerID
        self.profileID = profileID
        self.date = date
        self.value = value
        self.note = note
        self.createdAt = createdAt
    }
}

// MARK: - LoginDay

/// A day a profile opened the app. One row per profile per calendar day —
/// the raw material for the daily login streak.
public struct LoginDay: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var profileID: UUID
    /// Normalized to the start of the day in the recording calendar.
    public var day: Date

    public init(id: UUID = UUID(), profileID: UUID, day: Date) {
        self.id = id
        self.profileID = profileID
        self.day = day
    }
}

// MARK: - ExportSchedule

/// A standing instruction to produce a progress report on a weekly rhythm.
///
/// iOS cannot send mail or SMS unattended, so this schedules a **local
/// notification**; tapping it opens a composer pre-filled with the report.
public struct ExportSchedule: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var profileID: UUID
    public var isEnabled: Bool
    /// 1 = Sunday ... 7 = Saturday, matching `DateComponents.weekday`.
    public var weekday: Int
    public var hour: Int
    public var minute: Int
    public var channel: ExportChannel
    public var format: ReportFormat
    /// Email addresses or phone numbers, depending on `channel`.
    public var recipients: [String]
    /// How many days of history each report covers. Ignored when
    /// ``reportDefinitionID`` is set — a saved report carries its own range.
    public var lookbackDays: Int
    public var lastDeliveredAt: Date?

    /// How often this fires.
    public var frequency: ReportFrequency

    /// The saved custom report this sends, if any.
    ///
    /// When set, the reminder carries the report's id so tapping it opens the
    /// composer with every saved choice already filled in — habits, range,
    /// weekday filter and totals. The point of scheduling a report you built is
    /// not having to rebuild it each time.
    public var reportDefinitionID: UUID?

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        isEnabled: Bool = true,
        weekday: Int = 1,
        hour: Int = 18,
        minute: Int = 0,
        channel: ExportChannel = .email,
        format: ReportFormat = .html,
        recipients: [String] = [],
        lookbackDays: Int = 7,
        lastDeliveredAt: Date? = nil,
        frequency: ReportFrequency = .weekly,
        reportDefinitionID: UUID? = nil
    ) {
        self.frequency = frequency
        self.reportDefinitionID = reportDefinitionID
        self.id = id
        self.profileID = profileID
        self.isEnabled = isEnabled
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.channel = channel
        self.format = format
        self.recipients = recipients
        self.lookbackDays = lookbackDays
        self.lastDeliveredAt = lastDeliveredAt
    }

    /// "Sundays at 6:00 PM"
    public var summary: String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(0, min(symbols.count - 1, weekday - 1))
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let time = Calendar.current.date(from: components).map {
            $0.formatted(date: .omitted, time: .shortened)
        } ?? "\(hour):\(String(format: "%02d", minute))"
        return "\(symbols[index])s at \(time)"
    }

    public var notificationIdentifier: String { "trackerkit.export.\(id.uuidString)" }
}
