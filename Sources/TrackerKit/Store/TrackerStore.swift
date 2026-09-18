import Foundation
import SwiftData
import SwiftUI
import Observation

/// The single read/write surface over TrackerKit's data.
///
/// Views never touch `ModelContext` directly. They read the published value-type
/// arrays on this store and call its mutating methods, which keeps SwiftData in
/// one file and keeps every view testable against plain structs.
///
/// ```swift
/// let container = try TrackerKitSchema.container()
/// let store = TrackerStore(context: ModelContext(container))
/// store.reload()
/// ```
@MainActor
@Observable
public final class TrackerStore {

    // MARK: Published state

    /// Every profile on the device, in picker order.
    public private(set) var profiles: [Profile] = []
    /// Trackers belonging to ``activeProfileID``, sorted.
    public private(set) var trackers: [Tracker] = []
    /// Entries for the active profile inside ``historyWindowDays``.
    public private(set) var entries: [Entry] = []
    /// Login days for the active profile.
    public private(set) var loginDays: [LoginDay] = []
    /// Export schedules for the active profile.
    public private(set) var schedules: [ExportSchedule] = []

    /// Whose data is currently loaded. Setting it reloads everything below it.
    public var activeProfileID: UUID? {
        didSet {
            guard oldValue != activeProfileID else { return }
            reloadProfileScopedData()
        }
    }

    /// How far back entries are loaded. A year of daily data is a few thousand
    /// rows — cheap — and anything older is report territory, fetched on demand.
    public var historyWindowDays: Int = 400

    /// Set when a write fails, so a view can surface it instead of failing silently.
    public private(set) var lastError: String?

    /// The most recent reversible logging action, or `nil` if there is nothing
    /// to undo. Views observe this to offer an undo affordance.
    public private(set) var lastAction: LoggedAction?

    // MARK: Derived-value cache

    // Dashboards read the same derived values many times per SwiftUI body pass —
    // once for the row, once for the sort, once for the hero. Recomputing them
    // each time is what makes a tracker list feel slow.
    //
    // `@ObservationIgnored` is load bearing: without it, filling a cache from
    // inside a view's body would register as a mutation and kick off another
    // render, which is an infinite loop rather than a slow screen.
    @ObservationIgnored private var progressCache: [UUID: ProgressSnapshot] = [:]
    @ObservationIgnored private var streakCache: [UUID: StreakSummary] = [:]
    @ObservationIgnored private var dailyCache: [String: [DailyValue]] = [:]
    @ObservationIgnored private var historyCache: [String: [ProgressSnapshot]] = [:]
    /// The day the cache was filled on. Rolling past midnight invalidates it,
    /// because "today" moved and every current-period figure with it.
    @ObservationIgnored private var cacheDay: Date = .distantPast

    /// Drops every derived value. Called on any write and on a date rollover.
    public func invalidateCache() {
        progressCache.removeAll()
        streakCache.removeAll()
        dailyCache.removeAll()
        historyCache.removeAll()
        entryIndex = nil
        profileRecordCache = profileRecordCache.filter { !$0.value.isDeleted }
        trackerRecordCache = trackerRecordCache.filter { !$0.value.isDeleted }
        cacheDay = calculator.startOfDay(.now)
    }

    /// Ensures the cache belongs to today before anything reads it.
    private func validateCacheDay() {
        let today = calculator.startOfDay(.now)
        if cacheDay != today { invalidateCache() }
    }

    /// Touches the observed state that every derived value is computed from.
    ///
    /// This exists because the caches above are `@ObservationIgnored`, and that
    /// combination has a trap in it: on a cache *hit* an accessor returns
    /// without ever reading `entries` or `trackers`, so SwiftUI registers no
    /// dependency on them. The next mutation then notifies nobody and the view
    /// silently never refreshes — the data is correct, the screen is stale.
    ///
    /// That shipped. Logging from the dashboard updated the store and left the
    /// row showing the old number, because the row's snapshot was computed
    /// during a body pass that only hit caches.
    ///
    /// So every cached accessor registers first and answers second. The reads
    /// are free; the registration is the point.
    private func registerObservation() {
        _ = entries.count
        _ = trackers.count
    }

    // MARK: Dependencies

    public let context: ModelContext
    public var calculator: PeriodCalculator
    public var progress: ProgressEngine
    public var streaks: StreakEngine
    public var trends: TrendEngine

    // MARK: Init

    public init(
        context: ModelContext,
        calculator: PeriodCalculator = PeriodCalculator(),
        stoplight: StoplightEngine = .standard
    ) {
        self.context = context
        self.calculator = calculator
        self.progress = ProgressEngine(calculator: calculator, stoplight: stoplight)
        self.streaks = StreakEngine(calculator: calculator)
        self.trends = TrendEngine(calculator: calculator)
    }

    /// An in-memory store seeded with sample data. For previews and the demo app.
    public static func preview(seeded: Bool = true) -> TrackerStore {
        do {
            let container = try TrackerKitSchema.container(inMemory: true)
            let store = TrackerStore(context: ModelContext(container))
            if seeded {
                SampleData.seed(into: store)
            }
            store.reload()
            store.activeProfileID = store.profiles.first?.id
            return store
        } catch {
            fatalError("Could not build preview store: \(error)")
        }
    }

    public var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    // MARK: Loading

    /// Reloads everything. Call after any mutation that bypasses this store.
    public func reload() {
        loadProfiles()
        reloadProfileScopedData()
    }

    private func loadProfiles() {
        guard !isBatching else { return }
        let descriptor = FetchDescriptor<ProfileRecord>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]
        )
        profiles = (try? context.fetch(descriptor))?.map(\.value) ?? []
    }

    private func reloadProfileScopedData() {
        guard !isBatching else { return }
        invalidateCache()

        guard let activeProfileID else {
            trackers = []
            entries = []
            loginDays = []
            schedules = []
            return
        }

        guard let record = profileRecord(activeProfileID) else {
            trackers = []
            entries = []
            loginDays = []
            schedules = []
            return
        }

        trackers = record.trackers
            .map(\.value)
            .sorted { lhs, rhs in
                lhs.sortIndex == rhs.sortIndex
                    ? lhs.createdAt < rhs.createdAt
                    : lhs.sortIndex < rhs.sortIndex
            }

        let cutoff = calculator.calendar.date(
            byAdding: .day,
            value: -historyWindowDays,
            to: calculator.startOfDay(.now)
        ) ?? .distantPast

        entries = record.trackers
            .flatMap(\.entries)
            .filter { $0.date >= cutoff }
            .map(\.entryValue)
            .sorted { $0.date < $1.date }

        loginDays = record.loginDays.map(\.value).sorted { $0.day < $1.day }
        schedules = record.schedules.map(\.value).sorted { $0.weekday < $1.weekday }
    }

    // MARK: Record lookup

    // Record lookups are the hot path for writes: every log, toggle and goal
    // change resolves its record by id first. A predicate fetch each time is
    // fine for one tap and quadratic for an import loop, so resolved records are
    // memoized and checked for liveness before reuse.
    @ObservationIgnored private var profileRecordCache: [UUID: ProfileRecord] = [:]
    @ObservationIgnored private var trackerRecordCache: [UUID: TrackerRecord] = [:]

    private func profileRecord(_ id: UUID) -> ProfileRecord? {
        if let cached = profileRecordCache[id], !cached.isDeleted { return cached }

        var descriptor = FetchDescriptor<ProfileRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let found = try? context.fetch(descriptor).first
        profileRecordCache[id] = found
        return found
    }

    private func trackerRecord(_ id: UUID) -> TrackerRecord? {
        if let cached = trackerRecordCache[id], !cached.isDeleted { return cached }

        var descriptor = FetchDescriptor<TrackerRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let found = try? context.fetch(descriptor).first
        trackerRecordCache[id] = found
        return found
    }

    private func entryRecord(_ id: UUID) -> EntryRecord? {
        var descriptor = FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() {
        guard !isBatching else { return }
        do {
            try context.save()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Batching

    @ObservationIgnored private var isBatching = false

    /// Runs many writes as one unit, saving and reloading once at the end.
    ///
    /// Every mutating method here saves and reloads on its own, which is right for
    /// a user tapping a button and very wrong for a loop. Seeding a few thousand
    /// entries one-at-a-time means a few thousand context saves and a few thousand
    /// full reloads — quadratic work that turns a demo launch into a ten-second
    /// stare at a blank screen.
    ///
    /// ```swift
    /// store.performBatch {
    ///     for entry in imported { store.log(trackerID: entry.trackerID, value: entry.value) }
    /// }
    /// ```
    public func performBatch(_ work: () -> Void) {
        let wasBatching = isBatching
        isBatching = true
        work()
        isBatching = wasBatching

        guard !isBatching else { return }
        save()
        loadProfiles()
        reloadProfileScopedData()
    }

    // MARK: - Profiles

    @discardableResult
    public func addProfile(
        name: String,
        colorHex: String? = nil,
        symbolName: String = "person.fill",
        role: ProfileRole = .member
    ) -> Profile {
        let palette = ChartPalette.standard
        let profile = Profile(
            name: name,
            colorHex: colorHex ?? palette.seriesHex(profiles.count),
            symbolName: symbolName,
            role: role,
            sortIndex: profiles.count
        )
        let record = ProfileRecord(profile)
        context.insert(record)
        profileRecordCache[profile.id] = record
        save()
        loadProfiles()
        return profile
    }

    public func update(_ profile: Profile) {
        guard let record = profileRecord(profile.id) else { return }
        record.apply(profile)
        save()
        loadProfiles()
        if profile.id == activeProfileID { reloadProfileScopedData() }
    }

    /// Deletes a profile and, by cascade, every tracker, goal, entry and schedule
    /// under it. Also clears its PIN. There is no undo — confirm before calling.
    public func deleteProfile(_ id: UUID, pinManager: PINManager? = nil) {
        guard let record = profileRecord(id) else { return }
        // Cancel any scheduled exports before the rows disappear.
        let scheduleIDs = record.schedules.map(\.value.notificationIdentifier)
        ExportScheduler.cancel(identifiers: scheduleIDs)

        context.delete(record)
        save()
        (pinManager ?? PINManager.shared).removePIN(for: id)

        loadProfiles()
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }
    }

    public func reorderProfiles(_ ordered: [Profile]) {
        for (index, profile) in ordered.enumerated() {
            guard let record = profileRecord(profile.id) else { continue }
            record.sortIndex = index
        }
        save()
        loadProfiles()
    }

    // MARK: - Login streak

    /// Records that the active profile showed up today. Idempotent — calling it
    /// repeatedly in one day writes a single row.
    public func recordLogin(for profileID: UUID? = nil, on date: Date = .now) {
        guard let id = profileID ?? activeProfileID,
              let record = profileRecord(id)
        else { return }

        let day = calculator.startOfDay(date)
        let alreadyLogged = record.loginDays.contains { calculator.isSameDay($0.day, day) }
        guard !alreadyLogged else { return }

        let login = LoginDayRecord(day: day)
        login.profile = record
        context.insert(login)
        save()

        if id == activeProfileID { reloadProfileScopedData() }
    }

    /// The daily login streak for a profile, defaulting to the active one.
    public func loginStreak(for profileID: UUID? = nil, asOf now: Date = .now) -> StreakSummary {
        guard let id = profileID ?? activeProfileID else { return .empty }
        let days: [LoginDay]
        if id == activeProfileID {
            days = loginDays
        } else {
            days = profileRecord(id)?.loginDays.map(\.value) ?? []
        }
        return streaks.loginStreak(days, asOf: now)
    }

    // MARK: - Trackers

    @discardableResult
    public func addTracker(
        title: String,
        kind: TrackerKind = .checkbox,
        detail: String = "",
        symbolName: String = "target",
        colorHex: String? = nil,
        goal: GoalVersion? = nil,
        profileID: UUID? = nil
    ) -> Tracker? {
        guard let id = profileID ?? activeProfileID,
              let profile = profileRecord(id)
        else { return nil }

        let palette = ChartPalette.standard
        let record = TrackerRecord(
            title: title,
            detail: detail,
            symbolName: symbolName,
            colorHex: colorHex ?? palette.seriesHex(profile.trackers.count),
            kindRaw: kind.rawValue,
            sortIndex: profile.trackers.count
        )
        record.profile = profile
        context.insert(record)
        trackerRecordCache[record.id] = record

        if let goal {
            let goalRecord = GoalVersionRecord(goal)
            goalRecord.tracker = record
            context.insert(goalRecord)
        }

        save()
        if id == activeProfileID { reloadProfileScopedData() }
        return record.value
    }

    public func update(_ tracker: Tracker) {
        guard let record = trackerRecord(tracker.id) else { return }
        record.apply(tracker)
        save()
        reloadProfileScopedData()
    }

    public func deleteTracker(_ id: UUID) {
        guard let record = trackerRecord(id) else { return }
        context.delete(record)
        save()
        reloadProfileScopedData()
    }

    /// Archiving keeps the history but drops the tracker off the dashboard —
    /// almost always what someone means by "delete".
    public func setArchived(_ archived: Bool, trackerID: UUID) {
        guard let record = trackerRecord(trackerID) else { return }
        record.isArchived = archived
        save()
        reloadProfileScopedData()
    }

    public func reorderTrackers(_ ordered: [Tracker]) {
        for (index, tracker) in ordered.enumerated() {
            trackerRecord(tracker.id)?.sortIndex = index
        }
        save()
        reloadProfileScopedData()
    }

    // MARK: - Goals

    /// Appends a new goal version, leaving every earlier one intact.
    ///
    /// This is the only way goals change. Editing a target in place would rewrite
    /// history and make old charts lie about what was being aimed for.
    public func setGoal(
        _ goal: GoalVersion,
        on trackerID: UUID,
        effectiveFrom: Date? = nil
    ) {
        guard let record = trackerRecord(trackerID) else { return }

        var version = goal
        if let effectiveFrom { version.effectiveFrom = effectiveFrom }

        // Replacing a goal that starts the same day is an edit, not a new chapter.
        if let sameDay = record.goals.first(where: {
            calculator.isSameDay($0.effectiveFrom, version.effectiveFrom)
        }) {
            sameDay.target = version.target
            sameDay.cadenceRaw = version.cadence.rawValue
            sameDay.directionRaw = version.direction.rawValue
            sameDay.unit = version.unit
            sameDay.aggregationRaw = version.aggregation.rawValue
            sameDay.note = version.note
        } else {
            let goalRecord = GoalVersionRecord(version)
            goalRecord.tracker = record
            context.insert(goalRecord)
        }

        save()
        reloadProfileScopedData()
    }

    /// Removes a goal version outright. Use sparingly — this is the one operation
    /// that *does* rewrite history, and it exists for correcting a typo.
    public func deleteGoalVersion(_ goalID: UUID, from trackerID: UUID) {
        guard let record = trackerRecord(trackerID),
              let goal = record.goals.first(where: { $0.id == goalID })
        else { return }
        context.delete(goal)
        save()
        reloadProfileScopedData()
    }

    // MARK: - Entries

    /// Logs a value. For single-value kinds (checkbox, rating) an existing entry
    /// on the same day is replaced rather than stacked.
    @discardableResult
    public func log(
        trackerID: UUID,
        value: Double? = nil,
        date: Date = .now,
        note: String? = nil
    ) -> Entry? {
        guard let record = trackerRecord(trackerID) else { return nil }
        let kind = TrackerKind(rawValue: record.kindRaw) ?? .checkbox
        // The tracker's own step, which is derived from its goal — not the
        // kind's constant, which cannot tell 8,000 steps from 8 glasses.
        let resolved = value ?? record.value.quickLogStep

        let tracker = record.value

        if kind.isSingleValuePerDay,
           let existing = record.entries.first(where: { calculator.isSameDay($0.date, date) }) {
            let previous = existing.value
            existing.value = resolved
            existing.note = note ?? existing.note
            save()
            lastAction = LoggedAction(
                trackerID: trackerID,
                trackerTitle: tracker.title,
                summary: "Set to \(Formatters.value(resolved, unit: tracker.unit))",
                reversal: .replaced(entryID: existing.id, previousValue: previous)
            )
            reloadProfileScopedData()
            return existing.entryValue
        }

        let entry = EntryRecord(date: date, value: resolved, note: note)
        entry.tracker = record
        context.insert(entry)
        save()
        lastAction = LoggedAction(
            trackerID: trackerID,
            trackerTitle: tracker.title,
            summary: "Added \(Formatters.value(resolved, unit: tracker.unit))",
            reversal: .inserted(entryID: entry.id)
        )
        reloadProfileScopedData()
        return entry.entryValue
    }

    /// Toggles a checkbox tracker for a given day.
    public func toggle(trackerID: UUID, on date: Date = .now) {
        guard let record = trackerRecord(trackerID) else { return }
        if let existing = record.entries.first(where: { calculator.isSameDay($0.date, date) }) {
            let snapshot = existing.entryValue
            context.delete(existing)
            save()
            lastAction = LoggedAction(
                trackerID: trackerID,
                trackerTitle: record.value.title,
                summary: "Marked not done",
                reversal: .removed(entry: snapshot)
            )
            reloadProfileScopedData()
        } else {
            log(trackerID: trackerID, value: 1, date: date)
            if lastAction != nil {
                lastAction = LoggedAction(
                    trackerID: trackerID,
                    trackerTitle: record.value.title,
                    summary: "Marked done",
                    reversal: lastAction!.reversal
                )
            }
        }
    }

    public func updateEntry(_ entry: Entry) {
        guard let record = entryRecord(entry.id) else { return }
        record.date = entry.date
        record.value = entry.value
        record.note = entry.note
        save()
        reloadProfileScopedData()
    }

    public func deleteEntry(_ id: UUID) {
        guard let record = entryRecord(id) else { return }
        context.delete(record)
        save()
        reloadProfileScopedData()
    }

    // MARK: - Undo

    /// Reverses the most recent logging action.
    ///
    /// Safe to call when there is nothing to undo, and safe to call twice — the
    /// action is cleared as soon as it is applied, so a double-tap on Undo
    /// cannot reverse two things.
    @discardableResult
    public func undoLastAction() -> Bool {
        guard let action = lastAction else { return false }
        lastAction = nil

        switch action.reversal {
        case .inserted(let entryID):
            guard let record = entryRecord(entryID) else { return false }
            context.delete(record)

        case .replaced(let entryID, let previousValue):
            guard let record = entryRecord(entryID) else { return false }
            record.value = previousValue

        case .removed(let entry):
            guard let tracker = trackerRecord(entry.trackerID) else { return false }
            let restored = EntryRecord(entry)
            restored.tracker = tracker
            context.insert(restored)
        }

        save()
        reloadProfileScopedData()
        return true
    }

    /// Drops the undo offer without reversing anything — used when it expires.
    public func clearLastAction() {
        lastAction = nil
    }

    /// Entries for one tracker, oldest first.
    ///
    /// Indexed rather than filtered: this is called once per tracker per derived
    /// value, and a linear scan of every entry each time adds up fast.
    public func entries(for trackerID: UUID) -> [Entry] {
        validateCacheDay()
        registerObservation()

        if let index = entryIndex {
            return index[trackerID] ?? []
        }
        let index = Dictionary(grouping: entries, by: \.trackerID)
        entryIndex = index
        return index[trackerID] ?? []
    }

    @ObservationIgnored private var entryIndex: [UUID: [Entry]]?

    /// Entries for one tracker regardless of the loaded history window — used by
    /// reports and all-time charts.
    public func allEntries(for trackerID: UUID) -> [Entry] {
        trackerRecord(trackerID)?.entries
            .map(\.entryValue)
            .sorted { $0.date < $1.date } ?? []
    }

    // MARK: - Derived reads

    /// Trackers to show on the dashboard: active profile, not archived.
    public var activeTrackers: [Tracker] {
        trackers.filter { !$0.isArchived }
    }

    public func tracker(_ id: UUID) -> Tracker? {
        trackers.first { $0.id == id }
    }

    /// Current-period progress for one tracker.
    public func currentProgress(for trackerID: UUID, now: Date = .now) -> ProgressSnapshot? {
        registerObservation()
        guard let tracker = tracker(trackerID) else { return nil }
        validateCacheDay()

        if let cached = progressCache[trackerID] { return cached }

        let snapshot = progress.currentSnapshot(
            tracker: tracker,
            entries: entries(for: trackerID),
            now: now
        )
        progressCache[trackerID] = snapshot
        return snapshot
    }

    /// Current-period progress for every active tracker, dashboard order.
    public func currentProgressAll(now: Date = .now) -> [ProgressSnapshot] {
        activeTrackers.map {
            progress.currentSnapshot(tracker: $0, entries: entries(for: $0.id), now: now)
        }
    }

    /// Period history for one tracker.
    public func history(
        for trackerID: UUID,
        periodCount: Int = 12,
        cadence: Cadence? = nil,
        now: Date = .now
    ) -> [ProgressSnapshot] {
        guard let tracker = tracker(trackerID) else { return [] }
        validateCacheDay()
        registerObservation()

        let key = "\(trackerID.uuidString)-\(periodCount)-\(cadence?.rawValue ?? "auto")"
        if let cached = historyCache[key] { return cached }

        let result = progress.history(
            tracker: tracker,
            entries: entries(for: trackerID),
            periodCount: periodCount,
            cadence: cadence,
            endingAt: now
        )
        historyCache[key] = result
        return result
    }

    /// Daily values for one tracker over a trailing window.
    public func dailyValues(
        for trackerID: UUID,
        dayCount: Int = 30,
        now: Date = .now
    ) -> [DailyValue] {
        guard let tracker = tracker(trackerID) else { return [] }
        validateCacheDay()
        registerObservation()

        let key = "\(trackerID.uuidString)-\(dayCount)"
        if let cached = dailyCache[key] { return cached }

        let result = progress.dailyValues(
            tracker: tracker,
            entries: entries(for: trackerID),
            dayCount: dayCount,
            endingAt: now
        )
        dailyCache[key] = result
        return result
    }

    public func goalStreak(for trackerID: UUID, now: Date = .now) -> StreakSummary {
        registerObservation()
        guard let tracker = tracker(trackerID) else { return .empty }
        validateCacheDay()

        if let cached = streakCache[trackerID] { return cached }

        let summary = streaks.goalStreak(
            tracker: tracker,
            entries: entries(for: trackerID),
            asOf: now,
            progress: progress
        )
        streakCache[trackerID] = summary
        return summary
    }

    // MARK: - Export schedules

    @discardableResult
    public func addSchedule(_ schedule: ExportSchedule) -> ExportSchedule? {
        guard let profile = profileRecord(schedule.profileID) else { return nil }
        let record = ExportScheduleRecord(schedule)
        record.profile = profile
        context.insert(record)
        save()
        reloadProfileScopedData()
        return record.value
    }

    public func update(_ schedule: ExportSchedule) {
        var descriptor = FetchDescriptor<ExportScheduleRecord>(
            predicate: #Predicate { $0.id == schedule.id }
        )
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return }
        record.apply(schedule)
        save()
        reloadProfileScopedData()
    }

    public func deleteSchedule(_ id: UUID) {
        var descriptor = FetchDescriptor<ExportScheduleRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return }
        ExportScheduler.cancel(identifiers: [record.value.notificationIdentifier])
        context.delete(record)
        save()
        reloadProfileScopedData()
    }

    public func markScheduleDelivered(_ id: UUID, at date: Date = .now) {
        var descriptor = FetchDescriptor<ExportScheduleRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return }
        record.lastDeliveredAt = date
        save()
        reloadProfileScopedData()
    }

    // MARK: - Maintenance

    /// Deletes every row in the store. Used by the demo app's reset and by tests.
    public func deleteEverything() {
        for record in (try? context.fetch(FetchDescriptor<ProfileRecord>())) ?? [] {
            context.delete(record)
        }
        profileRecordCache.removeAll()
        trackerRecordCache.removeAll()
        save()
        activeProfileID = nil
        reload()
    }
}
