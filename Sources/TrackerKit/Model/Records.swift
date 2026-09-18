import Foundation
import SwiftData

// MARK: - ProfileRecord

/// SwiftData storage for a ``Profile``.
///
/// Records are the persistence layer and stay internal to the way TrackerKit
/// stores things; the public API traffics in the `Sendable` value types. Enums
/// persist as raw strings so adding a case later can't corrupt an existing store.
@Model
public final class ProfileRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var colorHex: String
    public var symbolName: String
    public var roleRaw: String
    public var createdAt: Date
    public var isPINProtected: Bool
    public var sortIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \TrackerRecord.profile)
    public var trackers: [TrackerRecord]

    @Relationship(deleteRule: .cascade, inverse: \LoginDayRecord.profile)
    public var loginDays: [LoginDayRecord]

    @Relationship(deleteRule: .cascade, inverse: \ExportScheduleRecord.profile)
    public var schedules: [ExportScheduleRecord]

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#0A84FF",
        symbolName: String = "person.fill",
        roleRaw: String = ProfileRole.member.rawValue,
        createdAt: Date = .now,
        isPINProtected: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.roleRaw = roleRaw
        self.createdAt = createdAt
        self.isPINProtected = isPINProtected
        self.sortIndex = sortIndex
        self.trackers = []
        self.loginDays = []
        self.schedules = []
    }

    public convenience init(_ profile: Profile) {
        self.init(
            id: profile.id,
            name: profile.name,
            colorHex: profile.colorHex,
            symbolName: profile.symbolName,
            roleRaw: profile.role.rawValue,
            createdAt: profile.createdAt,
            isPINProtected: profile.isPINProtected,
            sortIndex: profile.sortIndex
        )
    }

    public var value: Profile {
        Profile(
            id: id,
            name: name,
            colorHex: colorHex,
            symbolName: symbolName,
            role: ProfileRole(rawValue: roleRaw) ?? .member,
            createdAt: createdAt,
            isPINProtected: isPINProtected,
            sortIndex: sortIndex
        )
    }

    /// Copies mutable fields across. `id` and `createdAt` are never reassigned.
    public func apply(_ profile: Profile) {
        name = profile.name
        colorHex = profile.colorHex
        symbolName = profile.symbolName
        roleRaw = profile.role.rawValue
        isPINProtected = profile.isPINProtected
        sortIndex = profile.sortIndex
    }
}

// MARK: - TrackerRecord

@Model
public final class TrackerRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var detail: String
    public var symbolName: String
    public var colorHex: String
    public var kindRaw: String
    public var isArchived: Bool
    public var sortIndex: Int
    public var createdAt: Date
    public var reminderMinutes: Int?
    /// Nil derives the step from the goal. See `Tracker.quickLogStep`.
    public var quickLogIncrement: Double?

    public var profile: ProfileRecord?

    @Relationship(deleteRule: .cascade, inverse: \GoalVersionRecord.tracker)
    public var goals: [GoalVersionRecord]

    @Relationship(deleteRule: .cascade, inverse: \EntryRecord.tracker)
    public var entries: [EntryRecord]

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String = "",
        symbolName: String = "target",
        colorHex: String = "#0A84FF",
        kindRaw: String = TrackerKind.checkbox.rawValue,
        isArchived: Bool = false,
        sortIndex: Int = 0,
        createdAt: Date = .now,
        reminderMinutes: Int? = nil,
        quickLogIncrement: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.kindRaw = kindRaw
        self.isArchived = isArchived
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.reminderMinutes = reminderMinutes
        self.quickLogIncrement = quickLogIncrement
        self.goals = []
        self.entries = []
    }

    public convenience init(_ tracker: Tracker) {
        self.init(
            id: tracker.id,
            title: tracker.title,
            detail: tracker.detail,
            symbolName: tracker.symbolName,
            colorHex: tracker.colorHex,
            kindRaw: tracker.kind.rawValue,
            isArchived: tracker.isArchived,
            sortIndex: tracker.sortIndex,
            createdAt: tracker.createdAt,
            reminderMinutes: tracker.reminderMinutes,
            quickLogIncrement: tracker.quickLogIncrement
        )
    }

    public var value: Tracker {
        Tracker(
            id: id,
            profileID: profile?.id ?? UUID(),
            title: title,
            detail: detail,
            symbolName: symbolName,
            colorHex: colorHex,
            kind: TrackerKind(rawValue: kindRaw) ?? .checkbox,
            isArchived: isArchived,
            sortIndex: sortIndex,
            createdAt: createdAt,
            goalHistory: goals.map(\.value).sorted { $0.effectiveFrom < $1.effectiveFrom },
            reminderMinutes: reminderMinutes,
            quickLogIncrement: quickLogIncrement
        )
    }

    /// Copies presentation fields. Goal history is **never** touched here —
    /// goals are append-only and go through ``TrackerStore/setGoal(_:on:)``.
    public func apply(_ tracker: Tracker) {
        title = tracker.title
        detail = tracker.detail
        symbolName = tracker.symbolName
        colorHex = tracker.colorHex
        kindRaw = tracker.kind.rawValue
        isArchived = tracker.isArchived
        sortIndex = tracker.sortIndex
        reminderMinutes = tracker.reminderMinutes
        quickLogIncrement = tracker.quickLogIncrement
    }
}

// MARK: - GoalVersionRecord

@Model
public final class GoalVersionRecord {
    @Attribute(.unique) public var id: UUID
    public var effectiveFrom: Date
    public var target: Double
    public var cadenceRaw: String
    public var directionRaw: String
    public var unit: String
    public var aggregationRaw: String
    public var note: String?

    public var tracker: TrackerRecord?

    public init(
        id: UUID = UUID(),
        effectiveFrom: Date = .now,
        target: Double,
        cadenceRaw: String = Cadence.daily.rawValue,
        directionRaw: String = GoalDirection.atLeast.rawValue,
        unit: String = "",
        aggregationRaw: String = Aggregation.sum.rawValue,
        note: String? = nil
    ) {
        self.id = id
        self.effectiveFrom = effectiveFrom
        self.target = target
        self.cadenceRaw = cadenceRaw
        self.directionRaw = directionRaw
        self.unit = unit
        self.aggregationRaw = aggregationRaw
        self.note = note
    }

    public convenience init(_ goal: GoalVersion) {
        self.init(
            id: goal.id,
            effectiveFrom: goal.effectiveFrom,
            target: goal.target,
            cadenceRaw: goal.cadence.rawValue,
            directionRaw: goal.direction.rawValue,
            unit: goal.unit,
            aggregationRaw: goal.aggregation.rawValue,
            note: goal.note
        )
    }

    public var value: GoalVersion {
        GoalVersion(
            id: id,
            effectiveFrom: effectiveFrom,
            target: target,
            cadence: Cadence(rawValue: cadenceRaw) ?? .daily,
            direction: GoalDirection(rawValue: directionRaw) ?? .atLeast,
            unit: unit,
            aggregation: Aggregation(rawValue: aggregationRaw) ?? .sum,
            note: note
        )
    }
}

// MARK: - EntryRecord

@Model
public final class EntryRecord {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var value: Double
    public var note: String?
    public var createdAt: Date

    public var tracker: TrackerRecord?

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        value: Double = 1,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.value = value
        self.note = note
        self.createdAt = createdAt
    }

    public convenience init(_ entry: Entry) {
        self.init(
            id: entry.id,
            date: entry.date,
            value: entry.value,
            note: entry.note,
            createdAt: entry.createdAt
        )
    }

    public var entryValue: Entry {
        Entry(
            id: id,
            trackerID: tracker?.id ?? UUID(),
            profileID: tracker?.profile?.id ?? UUID(),
            date: date,
            value: value,
            note: note,
            createdAt: createdAt
        )
    }
}

// MARK: - LoginDayRecord

@Model
public final class LoginDayRecord {
    @Attribute(.unique) public var id: UUID
    /// Normalized to the start of the day.
    public var day: Date
    public var profile: ProfileRecord?

    public init(id: UUID = UUID(), day: Date) {
        self.id = id
        self.day = day
    }

    public var value: LoginDay {
        LoginDay(id: id, profileID: profile?.id ?? UUID(), day: day)
    }
}

// MARK: - ExportScheduleRecord

@Model
public final class ExportScheduleRecord {
    @Attribute(.unique) public var id: UUID
    public var isEnabled: Bool
    public var weekday: Int
    public var hour: Int
    public var minute: Int
    public var channelRaw: String
    public var formatRaw: String
    /// Stored joined by newline — SwiftData handles `[String]` but a plain
    /// scalar keeps the schema boring and diffable.
    public var recipientsJoined: String
    public var lookbackDays: Int
    public var lastDeliveredAt: Date?

    public var profile: ProfileRecord?

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        weekday: Int = 1,
        hour: Int = 18,
        minute: Int = 0,
        channelRaw: String = ExportChannel.email.rawValue,
        formatRaw: String = ReportFormat.html.rawValue,
        recipientsJoined: String = "",
        lookbackDays: Int = 7,
        lastDeliveredAt: Date? = nil
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.channelRaw = channelRaw
        self.formatRaw = formatRaw
        self.recipientsJoined = recipientsJoined
        self.lookbackDays = lookbackDays
        self.lastDeliveredAt = lastDeliveredAt
    }

    public convenience init(_ schedule: ExportSchedule) {
        self.init(
            id: schedule.id,
            isEnabled: schedule.isEnabled,
            weekday: schedule.weekday,
            hour: schedule.hour,
            minute: schedule.minute,
            channelRaw: schedule.channel.rawValue,
            formatRaw: schedule.format.rawValue,
            recipientsJoined: schedule.recipients.joined(separator: "\n"),
            lookbackDays: schedule.lookbackDays,
            lastDeliveredAt: schedule.lastDeliveredAt
        )
    }

    public var value: ExportSchedule {
        ExportSchedule(
            id: id,
            profileID: profile?.id ?? UUID(),
            isEnabled: isEnabled,
            weekday: weekday,
            hour: hour,
            minute: minute,
            channel: ExportChannel(rawValue: channelRaw) ?? .email,
            format: ReportFormat(rawValue: formatRaw) ?? .html,
            recipients: recipientsJoined
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
            lookbackDays: lookbackDays,
            lastDeliveredAt: lastDeliveredAt
        )
    }

    public func apply(_ schedule: ExportSchedule) {
        isEnabled = schedule.isEnabled
        weekday = schedule.weekday
        hour = schedule.hour
        minute = schedule.minute
        channelRaw = schedule.channel.rawValue
        formatRaw = schedule.format.rawValue
        recipientsJoined = schedule.recipients.joined(separator: "\n")
        lookbackDays = schedule.lookbackDays
        lastDeliveredAt = schedule.lastDeliveredAt
    }
}

// MARK: - Schema

/// The model container TrackerKit stores into.
public enum TrackerKitSchema {

    /// Every persisted type, in one place. Pass this to a host app's own
    /// `ModelContainer` if it already has one.
    public static let models: [any PersistentModel.Type] = [
        ProfileRecord.self,
        TrackerRecord.self,
        GoalVersionRecord.self,
        EntryRecord.self,
        LoginDayRecord.self,
        ExportScheduleRecord.self
    ]

    /// Builds a container for TrackerKit's models.
    ///
    /// - Parameters:
    ///   - inMemory: `true` for previews and tests — nothing touches disk.
    ///   - appGroupIdentifier: pass your App Group to put the store somewhere a
    ///     widget extension can also read. `nil` uses the app's own container.
    public static func container(
        inMemory: Bool = false,
        appGroupIdentifier: String? = nil
    ) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let appGroupIdentifier {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .identifier(appGroupIdentifier)
            )
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
