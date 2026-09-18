import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - WidgetTrackerLine

/// One tracker as it appears on a widget. Flattened and `Codable` on purpose: a
/// widget extension is a separate process that cannot open the SwiftData store
/// safely mid-timeline, so the app writes a small snapshot and the widget reads it.
public struct WidgetTrackerLine: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let symbolName: String
    public let colorHex: String
    public let actual: Double
    public let target: Double?
    public let unit: String
    public let statusRaw: String
    public let streak: Int
    /// Recent daily values for the widget's sparkline. Kept short — widget
    /// payloads are size-limited and nobody reads 90 bars at 150pt wide.
    public let recentValues: [Double]
    /// True for an `.atMost` goal that has been exceeded. Defaults to false so
    /// snapshots written by an older build still decode.
    public var breachesLimit: Bool = false

    public var status: StoplightStatus {
        StoplightStatus(rawValue: statusRaw) ?? .neutral
    }

    public var fraction: Double {
        guard let target, target != 0 else { return 0 }
        return actual / target
    }

    public var progressText: String {
        guard let target else { return Formatters.value(actual, unit: unit) }
        return "\(Formatters.value(actual, unit: unit)) / \(Formatters.value(target, unit: unit))"
    }

    public init(
        id: UUID,
        title: String,
        symbolName: String,
        colorHex: String,
        actual: Double,
        target: Double?,
        unit: String,
        status: StoplightStatus,
        streak: Int,
        recentValues: [Double],
        breachesLimit: Bool = false
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.actual = actual
        self.target = target
        self.unit = unit
        self.statusRaw = status.rawValue
        self.streak = streak
        self.recentValues = recentValues
        self.breachesLimit = breachesLimit
    }
}

// MARK: - WidgetSnapshot

/// Everything the widgets need for one profile, in one small `Codable` value.
public struct WidgetSnapshot: Codable, Sendable, Hashable {
    public let profileID: UUID
    public let profileName: String
    public let profileColorHex: String
    public let generatedAt: Date
    public let loginStreak: Int
    public let loginStreakIsAtRisk: Bool
    /// Recent days for the streak strip, most recent last.
    public let recentLoginFlags: [Bool]
    public let lines: [WidgetTrackerLine]

    public init(
        profileID: UUID,
        profileName: String,
        profileColorHex: String,
        generatedAt: Date = .now,
        loginStreak: Int,
        loginStreakIsAtRisk: Bool,
        recentLoginFlags: [Bool],
        lines: [WidgetTrackerLine]
    ) {
        self.profileID = profileID
        self.profileName = profileName
        self.profileColorHex = profileColorHex
        self.generatedAt = generatedAt
        self.loginStreak = loginStreak
        self.loginStreakIsAtRisk = loginStreakIsAtRisk
        self.recentLoginFlags = recentLoginFlags
        self.lines = lines
    }

    public var greenCount: Int { lines.filter { $0.status == .green }.count }
    public var scoredCount: Int { lines.filter { $0.status != .neutral }.count }

    public var worstStatus: StoplightStatus {
        lines.map(\.status).filter { $0 != .neutral }.max() ?? .neutral
    }

    public var headline: String {
        guard scoredCount > 0 else { return "No goals set" }
        return "\(greenCount) of \(scoredCount) on track"
    }

    /// Placeholder content for widget previews and the gallery.
    public static var placeholder: WidgetSnapshot {
        let palette = ChartPalette.standard
        return WidgetSnapshot(
            profileID: UUID(),
            profileName: "Alex",
            profileColorHex: palette.seriesHex(0),
            loginStreak: 12,
            loginStreakIsAtRisk: false,
            recentLoginFlags: [true, true, false, true, true, true, true],
            lines: [
                WidgetTrackerLine(
                    id: UUID(), title: "Focus Time", symbolName: "brain.head.profile",
                    colorHex: palette.seriesHex(0), actual: 48, target: 60, unit: "min",
                    status: .yellow, streak: 4,
                    recentValues: [55, 62, 40, 71, 58, 44, 48]
                ),
                WidgetTrackerLine(
                    id: UUID(), title: "Water", symbolName: "drop.fill",
                    colorHex: palette.seriesHex(2), actual: 8, target: 8, unit: "glasses",
                    status: .green, streak: 9,
                    recentValues: [6, 8, 8, 7, 9, 8, 8]
                ),
                WidgetTrackerLine(
                    id: UUID(), title: "Steps", symbolName: "shoeprints.fill",
                    colorHex: palette.seriesHex(1), actual: 3200, target: 8000, unit: "steps",
                    status: .red, streak: 0,
                    recentValues: [8400, 9100, 7600, 8800, 6200, 9400, 3200]
                )
            ]
        )
    }
}

// MARK: - SharedSnapshotStore

/// Moves ``WidgetSnapshot`` between the app and its widget extension.
///
/// Uses an App Group container, which is the only storage both processes can see.
/// Without a group identifier this degrades to the app's own defaults — the app
/// still works, the widget just won't update, and ``isConfigured`` says so rather
/// than failing silently.
public struct SharedSnapshotStore: Sendable {

    public let appGroupIdentifier: String?
    private let defaults: UserDefaults

    public init(appGroupIdentifier: String?) {
        self.appGroupIdentifier = appGroupIdentifier
        self.defaults = appGroupIdentifier
            .flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// Whether a real App Group is backing this store. `false` means widgets
    /// cannot see what the app writes.
    public var isConfigured: Bool {
        guard let appGroupIdentifier else { return false }
        return UserDefaults(suiteName: appGroupIdentifier) != nil
    }

    private func key(for profileID: UUID) -> String {
        "trackerkit.widget.snapshot.\(profileID.uuidString)"
    }

    private static let currentProfileKey = "trackerkit.widget.currentProfile"

    /// Writes a snapshot and asks WidgetKit to refresh.
    public func save(_ snapshot: WidgetSnapshot, makeCurrent: Bool = true) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key(for: snapshot.profileID))
        if makeCurrent {
            defaults.set(snapshot.profileID.uuidString, forKey: Self.currentProfileKey)
        }
        reloadWidgets()
    }

    public func snapshot(for profileID: UUID) -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: key(for: profileID)) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// The profile the widget should show by default — whoever used the app last.
    public func currentSnapshot() -> WidgetSnapshot? {
        guard let raw = defaults.string(forKey: Self.currentProfileKey),
              let id = UUID(uuidString: raw)
        else { return nil }
        return snapshot(for: id)
    }

    public func removeSnapshot(for profileID: UUID) {
        defaults.removeObject(forKey: key(for: profileID))
        reloadWidgets()
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

// MARK: - Store bridge

public extension TrackerStore {

    /// Builds the widget payload for a profile from live data.
    @MainActor
    func widgetSnapshot(
        for profileID: UUID? = nil,
        trackerLimit: Int = 4,
        sparklineDays: Int = 7,
        now: Date = .now
    ) -> WidgetSnapshot? {
        guard let id = profileID ?? activeProfileID,
              let profile = profiles.first(where: { $0.id == id })
        else { return nil }

        let snapshots = currentProgressAll(now: now)
        let byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.trackerID, $0) })

        // Show the goals that need attention first — a widget has room for a few
        // lines and they should be the ones worth glancing at.
        let ordered = activeTrackers.sorted { lhs, rhs in
            let left = byID[lhs.id]?.status ?? .neutral
            let right = byID[rhs.id]?.status ?? .neutral
            if left != right { return left > right }
            return lhs.sortIndex < rhs.sortIndex
        }

        let lines = ordered.prefix(trackerLimit).compactMap { tracker -> WidgetTrackerLine? in
            guard let snapshot = byID[tracker.id] else { return nil }
            let daily = dailyValues(for: tracker.id, dayCount: sparklineDays, now: now)
            return WidgetTrackerLine(
                id: tracker.id,
                title: tracker.title,
                symbolName: tracker.symbolName,
                colorHex: tracker.colorHex,
                actual: snapshot.actual,
                target: snapshot.target,
                unit: snapshot.unit,
                status: snapshot.status,
                streak: goalStreak(for: tracker.id, now: now).current,
                recentValues: daily.map(\.value),
                breachesLimit: snapshot.breachesLimit
            )
        }

        let streak = loginStreak(for: id, asOf: now)
        let flags = streaks.activityFlags(
            days: loginDays.map(\.day),
            dayCount: 7,
            endingAt: now
        ).map(\.isActive)

        return WidgetSnapshot(
            profileID: profile.id,
            profileName: profile.name,
            profileColorHex: profile.colorHex,
            generatedAt: now,
            loginStreak: streak.current,
            loginStreakIsAtRisk: streak.isAtRisk,
            recentLoginFlags: flags,
            lines: Array(lines)
        )
    }

    /// Builds and publishes the widget payload in one call. Call after any change
    /// worth surfacing on the home screen.
    @MainActor
    func publishWidgetSnapshot(appGroupIdentifier: String?, profileID: UUID? = nil) {
        guard let snapshot = widgetSnapshot(for: profileID) else { return }
        SharedSnapshotStore(appGroupIdentifier: appGroupIdentifier).save(snapshot)
    }
}
