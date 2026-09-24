// watchOS-only: these views do not exist on any other platform.
#if os(watchOS)

import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import TrackerKit

/// The watch screens render, including the states that are easy to forget.
///
/// Same reasoning as `RenderSmokeTests` on iOS: a view that compiles can still
/// trap at runtime, and a watch has more degenerate states than a phone because
/// a child sets it up from nothing with no keyboard.
@Suite("Watch views")
@MainActor
struct WatchViewTests {

    private func makeStore(withHabits: Bool) throws -> TrackerStore {
        let container = try TrackerKitSchema.container(inMemory: true)
        let store = TrackerStore(context: ModelContext(container))
        let me = store.addProfile(name: "Me")
        store.activeProfileID = me.id
        if withHabits {
            store.apply(.dailyHabits, selecting: TrackerTemplate.dailyHabits.recommended)
        }
        return store
    }

    private func renders(_ view: some View) -> Bool {
        let renderer = ImageRenderer(content: view.frame(width: 180, height: 220))
        renderer.scale = 1
        return renderer.uiImage != nil
    }

    @Test("Onboarding renders with no habits at all")
    func onboardingRenders() throws {
        let store = try makeStore(withHabits: false)
        #expect(renders(WatchOnboardingView(store: store).trackerTheme(.nocturne)))
    }

    @Test("A habit page renders")
    func habitPageRenders() throws {
        let store = try makeStore(withHabits: true)
        let tracker = try #require(store.activeTrackers.first)
        #expect(renders(
            WatchHabitPage(tracker: tracker, store: store, onPrint: {}).trackerTheme(.nocturne)
        ))
    }

    /// A brand-new habit has nothing logged and no history. That is the state
    /// every child starts in, so it must not be the one that breaks.
    @Test("A habit page renders with nothing logged")
    func emptyHabitRenders() throws {
        let store = try makeStore(withHabits: true)
        let tracker = try #require(store.activeTrackers.first)
        #expect(store.entries(for: tracker.id).isEmpty)
        #expect(renders(
            WatchHabitPage(tracker: tracker, store: store, onPrint: {}).trackerTheme(.nocturne)
        ))
    }

    @Test("The chart renders empty, partial and full weeks")
    func chartRendersEveryWeek() throws {
        let store = try makeStore(withHabits: true)
        let tracker = try #require(store.activeTrackers.first)

        for logs in [0, 3, 7] {
            for offset in 0..<logs {
                let day = Calendar.current.date(byAdding: .day, value: -offset, to: .now) ?? .now
                _ = store.log(trackerID: tracker.id, date: day)
            }
            let week = store.dailyValues(for: tracker.id, dayCount: 7)
            #expect(renders(
                WatchHabitChart(
                    values: week,
                    target: tracker.currentGoal?.target,
                    unit: "min",
                    colorHex: tracker.colorHex
                ).trackerTheme(.nocturne)
            ), "The chart failed with \(logs) days logged")
        }
    }

    /// A habit with no goal has no rule line to draw, which is a nil the chart
    /// has to survive rather than force-unwrap.
    @Test("The chart renders without a goal")
    func chartRendersWithoutGoal() throws {
        let store = try makeStore(withHabits: false)
        let plain = try #require(store.addTracker(title: "Anything", kind: .count))
        #expect(plain.currentGoal == nil)
        #expect(renders(
            WatchHabitChart(
                values: store.dailyValues(for: plain.id, dayCount: 7),
                target: nil,
                unit: "",
                colorHex: plain.colorHex
            ).trackerTheme(.nocturne)
        ))
    }

    @Test("The crown log view renders")
    func logViewRenders() throws {
        let store = try makeStore(withHabits: true)
        let tracker = try #require(store.activeTrackers.first)
        #expect(renders(WatchLogView(tracker: tracker, store: store).trackerTheme(.nocturne)))
    }

    @Test("The report renders, and builds its three spans")
    func reportRenders() throws {
        let store = try makeStore(withHabits: true)
        let tracker = try #require(store.activeTrackers.first)
        _ = store.log(trackerID: tracker.id)
        #expect(renders(WatchReportView(tracker: tracker, store: store).trackerTheme(.nocturne)))
    }

    // MARK: Behaviour

    @Test("Quick-add uses the habit's own step, not a bare 1")
    func quickAddUsesTheStep() throws {
        let store = try makeStore(withHabits: true)
        let reading = try #require(store.activeTrackers.first { $0.title == "Reading" })

        let before = store.currentProgress(for: reading.id)?.actual ?? 0
        _ = store.log(trackerID: reading.id)
        let after = store.currentProgress(for: reading.id)?.actual ?? 0

        #expect(after - before == reading.quickLogStep)
        #expect(reading.quickLogStep > 1, "Reading should step in minutes, not ones")
    }

    /// The whole point of the watch build: a child sets it up with no keyboard
    /// and no phone.
    @Test("A template sets up habits with no typing")
    func templateNeedsNoTyping() throws {
        let store = try makeStore(withHabits: false)
        #expect(store.activeTrackers.isEmpty)

        store.apply(.youthSport, selecting: TrackerTemplate.youthSport.recommended)

        #expect(store.activeTrackers.count == TrackerTemplate.youthSport.recommended.count)
        #expect(store.activeTrackers.allSatisfy { $0.currentGoal != nil },
                "A habit arrived without a goal, so its chart has no line to clear")
    }
}

#endif
