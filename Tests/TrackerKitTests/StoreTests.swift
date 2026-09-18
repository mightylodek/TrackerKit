import Testing
import Foundation
import SwiftData
@testable import TrackerKit

@MainActor
struct StoreTests {

    private func makeStore() throws -> TrackerStore {
        let container = try TrackerKitSchema.container(inMemory: true)
        return TrackerStore(context: ModelContext(container))
    }

    // MARK: Profiles

    @Test("Profiles are created, listed and scoped")
    func profileLifecycle() throws {
        let store = try makeStore()

        let alex = store.addProfile(name: "Alex", role: .owner)
        let jordan = store.addProfile(name: "Jordan")
        #expect(store.profiles.count == 2)

        store.activeProfileID = alex.id
        store.addTracker(title: "Water", kind: .count)
        #expect(store.trackers.count == 1)

        // Switching profiles swaps the whole scoped view.
        store.activeProfileID = jordan.id
        #expect(store.trackers.isEmpty)

        store.activeProfileID = alex.id
        #expect(store.trackers.count == 1)
    }

    @Test("Deleting a profile takes its trackers and entries with it")
    func cascadingDelete() throws {
        let store = try makeStore()
        let profile = store.addProfile(name: "Temp")
        store.activeProfileID = profile.id

        let tracker = store.addTracker(title: "Reps", kind: .count)
        #expect(tracker != nil)
        store.log(trackerID: tracker!.id, value: 10)
        #expect(store.entries.count == 1)

        store.deleteProfile(profile.id)
        #expect(store.profiles.isEmpty)
        #expect(store.trackers.isEmpty)
        #expect(store.entries.isEmpty)
    }

    // MARK: Entries

    @Test("A checkbox replaces its entry for the day rather than stacking")
    func checkboxIsSingleValue() throws {
        let store = try makeStore()
        let profile = store.addProfile(name: "A")
        store.activeProfileID = profile.id
        let tracker = try #require(store.addTracker(title: "Made bed", kind: .checkbox))

        store.log(trackerID: tracker.id, value: 1)
        store.log(trackerID: tracker.id, value: 1)
        store.log(trackerID: tracker.id, value: 1)

        #expect(store.entries(for: tracker.id).count == 1)
    }

    @Test("A count accumulates through the day")
    func countAccumulates() throws {
        let store = try makeStore()
        let profile = store.addProfile(name: "A")
        store.activeProfileID = profile.id
        let tracker = try #require(store.addTracker(
            title: "Water", kind: .count,
            goal: GoalVersion(target: 8, cadence: .daily, unit: "glasses")
        ))

        for _ in 0..<3 { store.log(trackerID: tracker.id, value: 2) }

        #expect(store.entries(for: tracker.id).count == 3)
        let progress = try #require(store.currentProgress(for: tracker.id))
        #expect(progress.actual == 6)
        #expect(!progress.isMet)
    }

    @Test("Toggling adds then removes the day's entry")
    func toggling() throws {
        let store = try makeStore()
        let profile = store.addProfile(name: "A")
        store.activeProfileID = profile.id
        let tracker = try #require(store.addTracker(title: "Stretch", kind: .checkbox))

        store.toggle(trackerID: tracker.id)
        #expect(store.entries(for: tracker.id).count == 1)

        store.toggle(trackerID: tracker.id)
        #expect(store.entries(for: tracker.id).isEmpty)
    }

    @Test("Caches invalidate on write, so progress reflects the latest entry")
    func cacheInvalidation() throws {
        let store = try makeStore()
        let profile = store.addProfile(name: "A")
        store.activeProfileID = profile.id
        let tracker = try #require(store.addTracker(
            title: "Reps", kind: .count,
            goal: GoalVersion(target: 10, cadence: .daily, unit: "reps")
        ))

        store.log(trackerID: tracker.id, value: 4)
        #expect(store.currentProgress(for: tracker.id)?.actual == 4)

        // A stale cache would keep reporting 4 here.
        store.log(trackerID: tracker.id, value: 6)
        #expect(store.currentProgress(for: tracker.id)?.actual == 10)
        #expect(store.currentProgress(for: tracker.id)?.isMet == true)
    }

    // MARK: Goals

    @Test("Setting a goal appends a version and leaves the old one standing")
    func goalsAreAppendOnly() throws {
        let store = try makeStore()
        let profile = store.addProfile(name: "A")
        store.activeProfileID = profile.id

        let tracker = try #require(store.addTracker(
            title: "Workouts", kind: .count,
            goal: GoalVersion(
                effectiveFrom: Date.now.addingTimeInterval(-60 * 86_400),
                target: 3, cadence: .weekly, unit: "x"
            )
        ))

        store.setGoal(
            GoalVersion(target: 5, cadence: .weekly, unit: "x", note: "Raised it"),
            on: tracker.id
        )

        let updated = try #require(store.tracker(tracker.id))
        #expect(updated.goalHistory.count == 2)
        #expect(updated.currentGoal?.target == 5)
        #expect(updated.goalHistory.first?.target == 3)
        #expect(updated.goalHistory.last?.note == "Raised it")
    }

    @Test("Re-setting a goal on the same day edits it instead of splitting history")
    func sameDayGoalIsAnEdit() throws {
        let store = try makeStore()
        let profile = store.addProfile(name: "A")
        store.activeProfileID = profile.id
        let tracker = try #require(store.addTracker(
            title: "Pages", kind: .count,
            goal: GoalVersion(target: 10, cadence: .daily, unit: "pages")
        ))

        store.setGoal(GoalVersion(target: 20, cadence: .daily, unit: "pages"), on: tracker.id)
        store.setGoal(GoalVersion(target: 25, cadence: .daily, unit: "pages"), on: tracker.id)

        let updated = try #require(store.tracker(tracker.id))
        #expect(updated.goalHistory.count == 1, "Typo fixes shouldn't each become a chapter")
        #expect(updated.currentGoal?.target == 25)
    }

    // MARK: Login streak

    @Test("Recording a login twice in one day counts once")
    func loginIsIdempotent() throws {
        let store = try makeStore()
        let profile = store.addProfile(name: "A")
        store.activeProfileID = profile.id

        store.recordLogin()
        store.recordLogin()
        store.recordLogin()

        #expect(store.loginDays.count == 1)
        #expect(store.loginStreak().current == 1)
    }

    // MARK: Batching

    @Test("A batch saves once and still lands every write")
    func batching() throws {
        let store = try makeStore()
        let profile = store.addProfile(name: "A")
        store.activeProfileID = profile.id
        let tracker = try #require(store.addTracker(title: "Reps", kind: .count))

        store.performBatch {
            for _ in 0..<50 {
                store.log(trackerID: tracker.id, value: 1)
            }
        }

        #expect(store.entries(for: tracker.id).count == 50)
        #expect(store.currentProgress(for: tracker.id)?.actual == 50)
    }

    // MARK: Reports

    @Test("A weekly report scales daily targets to the window")
    func reportScalesTargets() throws {
        let store = try makeStore()
        let profile = store.addProfile(name: "Alex")
        store.activeProfileID = profile.id

        let tracker = try #require(store.addTracker(
            title: "Water", kind: .count,
            goal: GoalVersion(
                effectiveFrom: Date.now.addingTimeInterval(-30 * 86_400),
                target: 8, cadence: .daily, unit: "glasses"
            )
        ))
        for offset in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
            store.log(trackerID: tracker.id, value: 8, date: date)
        }

        let report = try #require(store.buildReport(lookbackDays: 7))
        let item = try #require(report.items.first)

        // 8 a day over 7 days is a 56 target, not 8.
        #expect(item.target == 56)
        #expect(item.actual == 56)
        #expect(item.status == .green)
        #expect(report.profileName == "Alex")
    }

    @Test("A report flags goals that moved inside the window")
    func reportFlagsGoalChanges() throws {
        let store = try makeStore()
        let profile = store.addProfile(name: "Alex")
        store.activeProfileID = profile.id

        let tracker = try #require(store.addTracker(
            title: "Focus", kind: .duration,
            goal: GoalVersion(
                effectiveFrom: Date.now.addingTimeInterval(-40 * 86_400),
                target: 45, cadence: .daily, unit: "min"
            )
        ))
        store.setGoal(
            GoalVersion(
                effectiveFrom: Date.now.addingTimeInterval(-2 * 86_400),
                target: 60, cadence: .daily, unit: "min", note: "Raised"
            ),
            on: tracker.id
        )
        store.log(trackerID: tracker.id, value: 50)

        let report = try #require(store.buildReport(lookbackDays: 7))
        #expect(report.items.first?.goalChangedInWindow == true)
    }

    @Test("Every report format produces non-empty output")
    func reportFormats() throws {
        let store = TrackerStore.preview()
        let report = try #require(store.buildReport(lookbackDays: 7))

        let csv = CSVReportRenderer().render(report)
        let markdown = MarkdownReportRenderer().render(report)
        let html = HTMLReportRenderer().render(report)

        #expect(csv.count > 100)
        #expect(markdown.count > 100)
        #expect(html.count > 500)

        let htmlText = String(data: html, encoding: .utf8) ?? ""
        #expect(htmlText.hasPrefix("<!doctype html>"))
        #expect(htmlText.contains(report.profileName))
        // Status must never ride on color alone.
        #expect(htmlText.contains("On track") || htmlText.contains("Off track"))
    }

    @Test("CSV escapes fields that would otherwise break a row")
    func csvEscaping() throws {
        let store = try makeStore()
        let profile = store.addProfile(name: "Alex")
        store.activeProfileID = profile.id
        store.addTracker(
            title: "Reading, daily \"pages\"",
            kind: .count,
            goal: GoalVersion(target: 10, cadence: .daily, unit: "pages")
        )

        let report = try #require(store.buildReport(lookbackDays: 7))
        let csv = String(data: CSVReportRenderer().render(report), encoding: .utf8) ?? ""

        #expect(csv.contains("\"Reading, daily \"\"pages\"\"\""))
    }

    // MARK: Widgets

    @Test("The widget snapshot leads with what needs attention")
    func widgetSnapshotOrdering() throws {
        let store = TrackerStore.preview()
        let snapshot = try #require(store.widgetSnapshot(trackerLimit: 4))

        #expect(!snapshot.lines.isEmpty)
        #expect(snapshot.lines.count <= 4)
        #expect(snapshot.recentLoginFlags.count == 7)

        // Worst status first.
        let statuses = snapshot.lines.map(\.status).filter { $0 != .neutral }
        #expect(statuses == statuses.sorted(by: >))
    }

    @Test("The widget snapshot round-trips through JSON")
    func widgetSnapshotCodable() throws {
        let original = WidgetSnapshot.placeholder
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        #expect(decoded.profileName == original.profileName)
        #expect(decoded.lines.count == original.lines.count)
        #expect(decoded.loginStreak == original.loginStreak)
    }
}

// MARK: - PIN

@MainActor
struct PINManagerTests {

    /// In-memory storage: a test bundle with no host app has no keychain
    /// container, so a real `KeychainStore` here would fail on entitlements
    /// rather than on anything to do with PIN logic.
    private func makeManager() -> PINManager {
        PINManager.inMemory()
    }

    @Test("A correct PIN verifies and a wrong one doesn't")
    func verification() throws {
        let manager = makeManager()
        let profileID = UUID()

        #expect(!manager.hasPIN(for: profileID))
        #expect(manager.verify("1357", for: profileID) == .noPINSet)

        try manager.setPIN("1357", for: profileID)
        #expect(manager.hasPIN(for: profileID))
        #expect(manager.verify("1357", for: profileID) == .success)

        if case .incorrect = manager.verify("2468", for: profileID) {
            // expected
        } else {
            Issue.record("A wrong PIN should report incorrect")
        }

        manager.removePIN(for: profileID)
        #expect(!manager.hasPIN(for: profileID))
    }

    @Test("Malformed PINs are rejected before they're stored")
    func malformedRejected() {
        let manager = makeManager()
        let profileID = UUID()

        #expect(throws: PINError.self) { try manager.setPIN("12", for: profileID) }
        #expect(throws: PINError.self) { try manager.setPIN("abcd", for: profileID) }
        #expect(throws: PINError.self) { try manager.setPIN("12345", for: profileID) }
        #expect(!manager.hasPIN(for: profileID))
    }

    @Test("Repeated failures trigger a lockout")
    func lockout() {
        let manager = makeManager()
        let profileID = UUID()
        try? manager.setPIN("1357", for: profileID)

        var lockedOut = false
        for _ in 0..<manager.maxAttempts {
            if case .lockedOut = manager.verify("0000", for: profileID) {
                lockedOut = true
            }
        }

        #expect(lockedOut, "Brute forcing 10,000 combinations must not be free")
        #expect(manager.isLockedOut(for: profileID))

        // Even the right PIN is refused while locked.
        if case .lockedOut = manager.verify("1357", for: profileID) {
            // expected
        } else {
            Issue.record("A lockout should hold regardless of what's entered")
        }

        manager.administrativeUnlock(for: profileID)
        #expect(!manager.isLockedOut(for: profileID))
        #expect(manager.verify("1357", for: profileID) == .success)
    }

    @Test("A correct PIN clears the failure count")
    func successResetsAttempts() {
        let manager = makeManager()
        let profileID = UUID()
        try? manager.setPIN("1357", for: profileID)

        _ = manager.verify("0000", for: profileID)
        _ = manager.verify("0000", for: profileID)
        #expect(manager.remainingAttempts(for: profileID) < manager.maxAttempts)

        #expect(manager.verify("1357", for: profileID) == .success)
        #expect(manager.remainingAttempts(for: profileID) == manager.maxAttempts)
    }

    @Test("Obvious PINs are flagged as weak")
    func weakPINs() {
        let manager = makeManager()
        #expect(manager.isWeak("1234"))
        #expect(manager.isWeak("0000"))
        #expect(!manager.isWeak("7391"))
    }

    @Test("Two profiles with the same PIN store different hashes")
    func saltsDiffer() throws {
        let storage = InMemorySecretStorage()
        let manager = PINManager(
            keychain: storage,
            defaults: UserDefaults(suiteName: "trackerkit.salt.\(UUID().uuidString)") ?? .standard
        )
        manager.iterations = 1_000

        let first = UUID()
        let second = UUID()
        try manager.setPIN("1357", for: first)
        try manager.setPIN("1357", for: second)

        #expect(manager.verify("1357", for: first) == .success)
        #expect(manager.verify("1357", for: second) == .success)

        // Same PIN, different profiles: salting must make the stored bytes differ,
        // otherwise cracking one profile cracks every profile that shares a PIN.
        let firstHash = try #require(storage.data(account: "pin.hash.\(first.uuidString)"))
        let secondHash = try #require(storage.data(account: "pin.hash.\(second.uuidString)"))
        #expect(firstHash != secondHash)

        let firstSalt = try #require(storage.data(account: "pin.salt.\(first.uuidString)"))
        let secondSalt = try #require(storage.data(account: "pin.salt.\(second.uuidString)"))
        #expect(firstSalt != secondSalt)
    }

    @Test("A PIN is never stored in the clear")
    func pinIsNotStoredInTheClear() throws {
        let storage = InMemorySecretStorage()
        let manager = PINManager(
            keychain: storage,
            defaults: UserDefaults(suiteName: "trackerkit.clear.\(UUID().uuidString)") ?? .standard
        )
        manager.iterations = 1_000

        let profileID = UUID()
        try manager.setPIN("7391", for: profileID)

        let stored = try #require(storage.data(account: "pin.hash.\(profileID.uuidString)"))
        #expect(stored != Data("7391".utf8))
        #expect(String(data: stored, encoding: .utf8) != "7391")
        #expect(stored.count == 32, "Expected a SHA-256 digest")
    }
}

// MARK: - Undo

@MainActor
struct UndoTests {

    private func makeStore() throws -> TrackerStore {
        let container = try TrackerKitSchema.container(inMemory: true)
        let store = TrackerStore(context: ModelContext(container))
        let profile = store.addProfile(name: "A")
        store.activeProfileID = profile.id
        return store
    }

    @Test("Undo reverses an accidental double-tap")
    func undoDoubleTap() throws {
        let store = try makeStore()
        let tracker = try #require(store.addTracker(
            title: "Water", kind: .count,
            goal: GoalVersion(target: 8, cadence: .daily, unit: "glasses")
        ))

        store.log(trackerID: tracker.id)
        store.log(trackerID: tracker.id)   // the slip
        #expect(store.currentProgress(for: tracker.id)?.actual == 2)

        #expect(store.undoLastAction())
        #expect(store.currentProgress(for: tracker.id)?.actual == 1, "Undo should remove only the last entry")
    }

    @Test("Undo can only be applied once per action")
    func undoIsNotRepeatable() throws {
        let store = try makeStore()
        let tracker = try #require(store.addTracker(title: "Reps", kind: .count))

        store.log(trackerID: tracker.id)
        store.log(trackerID: tracker.id)

        #expect(store.undoLastAction())
        // A double-tap on Undo itself must not eat a second, legitimate entry.
        #expect(store.undoLastAction() == false)
        #expect(store.entries(for: tracker.id).count == 1)
    }

    @Test("Undoing a checkbox toggle puts the entry back")
    func undoToggleOff() throws {
        let store = try makeStore()
        let tracker = try #require(store.addTracker(title: "Stretch", kind: .checkbox))

        store.toggle(trackerID: tracker.id)
        #expect(store.entries(for: tracker.id).count == 1)

        store.toggle(trackerID: tracker.id)          // accidentally un-did it
        #expect(store.entries(for: tracker.id).isEmpty)

        #expect(store.undoLastAction())
        #expect(store.entries(for: tracker.id).count == 1, "Toggling off should be reversible")
    }

    @Test("Undoing a rating restores the previous value, not nothing")
    func undoReplacedValue() throws {
        let store = try makeStore()
        let tracker = try #require(store.addTracker(
            title: "Mood", kind: .rating,
            goal: GoalVersion(target: 4, cadence: .daily, unit: "/5")
        ))

        store.log(trackerID: tracker.id, value: 4)
        store.log(trackerID: tracker.id, value: 2)   // mis-tap
        #expect(store.currentProgress(for: tracker.id)?.actual == 2)

        #expect(store.undoLastAction())
        #expect(store.currentProgress(for: tracker.id)?.actual == 4, "Should restore 4, not delete the day")
    }

    @Test("There is nothing to undo before anything is logged")
    func nothingToUndo() throws {
        let store = try makeStore()
        #expect(store.lastAction == nil)
        #expect(store.undoLastAction() == false)
    }

    @Test("Only the most recent action is offered")
    func onlyOneOffer() throws {
        let store = try makeStore()
        let water = try #require(store.addTracker(title: "Water", kind: .count))
        let reps = try #require(store.addTracker(title: "Reps", kind: .count))

        store.log(trackerID: water.id)
        store.log(trackerID: reps.id)

        #expect(store.lastAction?.trackerTitle == "Reps")
        store.undoLastAction()
        // The earlier Water entry survives — undo is one-deep by design.
        #expect(store.entries(for: water.id).count == 1)
        #expect(store.entries(for: reps.id).isEmpty)
    }
}

// MARK: - Dashboard layout

@MainActor
struct DashboardLayoutTests {

    private func makeStore() throws -> TrackerStore {
        let container = try TrackerKitSchema.container(inMemory: true)
        let store = TrackerStore(context: ModelContext(container))
        let profile = store.addProfile(name: "A")
        store.activeProfileID = profile.id
        return store
    }

    @Test("A new profile gets the original composition")
    func defaultLayout() throws {
        let store = try makeStore()
        #expect(store.dashboardLayout.map(\.kind) == [.hero, .stoplightRollup, .trackerList])
    }

    @Test("Cards can be added, reordered and removed")
    func editing() throws {
        let store = try makeStore()
        let tracker = try #require(store.addTracker(title: "Water", kind: .count))

        store.addDashboardCard(DashboardCard(kind: .heatmap, trackerID: tracker.id))
        #expect(store.dashboardLayout.count == 4)
        #expect(store.dashboardLayout.last?.kind == .heatmap)

        store.moveDashboardCards(from: IndexSet(integer: 3), to: 0)
        #expect(store.dashboardLayout.first?.kind == .heatmap)

        let id = try #require(store.dashboardLayout.first?.id)
        store.removeDashboardCard(id: id)
        #expect(store.dashboardLayout.count == 3)
    }

    @Test("Layouts survive a reload — they're persisted, not in memory")
    func persistence() throws {
        let store = try makeStore()
        let tracker = try #require(store.addTracker(title: "Water", kind: .count))
        store.addDashboardCard(DashboardCard(kind: .heatmap, trackerID: tracker.id))

        store.reload()
        #expect(store.dashboardLayout.map(\.kind).contains(.heatmap))
    }

    @Test("Each profile keeps its own dashboard")
    func perProfile() throws {
        let store = try makeStore()
        let first = try #require(store.profiles.first)
        let second = store.addProfile(name: "B")

        store.addDashboardCard(DashboardCard(kind: .rings))
        #expect(store.dashboardLayout.map(\.kind).contains(.rings))

        store.activeProfileID = second.id
        #expect(!store.dashboardLayout.map(\.kind).contains(.rings), "B inherited A's dashboard")

        store.activeProfileID = first.id
        #expect(store.dashboardLayout.map(\.kind).contains(.rings), "A lost its dashboard")
    }

    @Test("Singleton cards can't be added twice")
    func noDuplicateSingletons() throws {
        let store = try makeStore()
        store.addDashboardCard(DashboardCard(kind: .rings))
        store.addDashboardCard(DashboardCard(kind: .rings))
        #expect(store.dashboardLayout.filter { $0.kind == .rings }.count == 1)

        #expect(!DashboardCard.addableKinds(given: store.dashboardLayout).contains(.rings))
        // Tracker-scoped cards are fine more than once — two heatmaps for two
        // different trackers is a reasonable dashboard.
        #expect(DashboardCard.addableKinds(given: store.dashboardLayout).contains(.heatmap))
    }

    @Test("A card pointing at a deleted tracker is skipped, not fatal")
    func orphanedCard() throws {
        let store = try makeStore()
        let tracker = try #require(store.addTracker(title: "Water", kind: .count))
        store.addDashboardCard(DashboardCard(kind: .heatmap, trackerID: tracker.id))

        store.deleteTracker(tracker.id)

        let orphan = try #require(store.dashboardLayout.first { $0.kind == .heatmap })
        #expect(store.canRender(orphan) == false)
        // It stays in the layout so the editor can explain it, but never draws.
        #expect(store.dashboardLayout.contains { $0.id == orphan.id })
    }

    @Test("Reset restores the default without touching data")
    func reset() throws {
        let store = try makeStore()
        let tracker = try #require(store.addTracker(title: "Water", kind: .count))
        store.log(trackerID: tracker.id)
        store.addDashboardCard(DashboardCard(kind: .rings))

        store.resetDashboardLayout()
        #expect(store.dashboardLayout.map(\.kind) == [.hero, .stoplightRollup, .trackerList])
        #expect(store.entries(for: tracker.id).count == 1, "Reset must not touch entries")
    }
}

@MainActor
struct BatchUndoTests {
    @Test("A bulk import leaves nothing to undo")
    func batchClearsUndo() throws {
        let container = try TrackerKitSchema.container(inMemory: true)
        let store = TrackerStore(context: ModelContext(container))
        SampleData.seed(into: store)
        store.reload()

        // Seeding logs over a thousand entries; offering to undo one arbitrary
        // entry the user never created is worse than offering nothing.
        #expect(store.lastAction == nil)
    }
}

// MARK: - Templates

@MainActor
struct TemplateTests {

    private func makeStore() throws -> TrackerStore {
        let container = try TrackerKitSchema.container(inMemory: true)
        let store = TrackerStore(context: ModelContext(container))
        let profile = store.addProfile(name: "A")
        store.activeProfileID = profile.id
        return store
    }

    @Test("A fresh profile needs onboarding; a set-up one doesn't")
    func needsOnboarding() throws {
        let store = try makeStore()
        #expect(store.needsOnboarding)

        store.apply(.youthSport)
        #expect(!store.needsOnboarding)
    }

    @Test("Applying a template creates its trackers with goals and steps")
    func appliesBlueprints() throws {
        let store = try makeStore()
        let created = store.apply(.youthSport)

        #expect(created.count == TrackerTemplate.youthSport.recommended.count)
        #expect(store.activeTrackers.contains { $0.title == "Practice" })

        let practice = try #require(store.activeTrackers.first { $0.title == "Practice" })
        #expect(practice.currentGoal?.target == 150)
        #expect(practice.currentGoal?.cadence == .weekly)
        // The template's explicit step must survive, not be re-derived.
        #expect(practice.quickLogStep == 15)
    }

    @Test("Unticked trackers are not created")
    func respectsSelection() throws {
        let store = try makeStore()
        let template = TrackerTemplate.youthSport
        let onlyWater = template.blueprints.filter { $0.title == "Water" }

        store.apply(template, selecting: onlyWater)
        #expect(store.activeTrackers.count == 1)
        #expect(store.activeTrackers.first?.title == "Water")
    }

    @Test("The template's dashboard is bound to the trackers actually created")
    func bindsLayout() throws {
        let store = try makeStore()
        store.apply(.youthSport)

        let heatmap = try #require(store.dashboardLayout.first { $0.kind == .heatmap })
        let bound = try #require(heatmap.trackerID.flatMap { store.tracker($0) })
        #expect(bound.title == "Practice")
        #expect(store.canRender(heatmap))
    }

    @Test("A layout slot whose tracker wasn't selected is dropped, not dangling")
    func dropsUnboundSlots() throws {
        let store = try makeStore()
        let template = TrackerTemplate.youthSport
        // Practice is what the heatmap slot points at — leave it out.
        let withoutPractice = template.recommended.filter { $0.title != "Practice" }

        store.apply(template, selecting: withoutPractice)
        #expect(!store.dashboardLayout.contains { $0.kind == .heatmap })
        #expect(store.dashboardLayout.allSatisfy { store.canRender($0) })
    }

    @Test("The blank template creates nothing")
    func blankTemplate() throws {
        let store = try makeStore()
        store.apply(.blank)
        #expect(store.activeTrackers.isEmpty)
    }

    @Test("Every built-in template is coherent")
    func templatesAreWellFormed() {
        for template in TrackerTemplate.all {
            #expect(!template.name.isEmpty)
            #expect(!template.summary.isEmpty)

            for slot in template.layout where slot.kind.needsTracker {
                let title = slot.trackerTitle
                #expect(title != nil, "\(template.name): a tracker-scoped slot names no tracker")
                #expect(
                    template.blueprints.contains { $0.title == title },
                    "\(template.name): layout points at '\(title ?? "")', which it never creates"
                )
            }

            for blueprint in template.blueprints where blueprint.target != nil {
                #expect(blueprint.target! > 0, "\(template.name)/\(blueprint.title) has a non-positive target")
            }
        }
    }
}
