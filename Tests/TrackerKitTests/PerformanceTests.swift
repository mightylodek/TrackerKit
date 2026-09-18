import Testing
import Foundation
import SwiftData
@testable import TrackerKit

/// Timing guards. These are not micro-benchmarks — they exist because the
/// dashboard once took ten seconds to appear, and the only way that doesn't
/// happen again is to assert it doesn't.
@MainActor
struct PerformanceTests {

    private func makeStore() throws -> TrackerStore {
        let container = try TrackerKitSchema.container(inMemory: true)
        return TrackerStore(context: ModelContext(container))
    }

    @Test("Seeding the full sample set stays under two seconds")
    func seedingIsFast() throws {
        let store = try makeStore()

        let start = Date.now
        SampleData.seed(into: store)
        let elapsed = Date.now.timeIntervalSince(start)

        store.reload()
        #expect(store.profiles.count == 3)
        #expect(elapsed < 2.0, "Seeding took \(String(format: "%.2f", elapsed))s")
    }

    @Test("A full dashboard pass stays under 150ms")
    func dashboardPassIsFast() throws {
        let store = try makeStore()
        SampleData.seed(into: store)
        store.reload()
        store.activeProfileID = store.profiles.first?.id

        // Warm the cache the way the first body pass would.
        _ = store.currentProgressAll()

        let start = Date.now
        for _ in 0..<5 {
            _ = store.currentProgressAll()
            for tracker in store.activeTrackers {
                _ = store.goalStreak(for: tracker.id)
                _ = store.dailyValues(for: tracker.id, dayCount: 21)
            }
        }
        let elapsed = Date.now.timeIntervalSince(start)

        #expect(elapsed < 0.15, "Five dashboard passes took \(String(format: "%.3f", elapsed))s")
    }

    @Test("History over a year of daily periods stays under 50ms")
    func historyIsFast() throws {
        let sample = SampleData.previewTracker()
        let engine = ProgressEngine()

        let start = Date.now
        let history = engine.history(
            tracker: sample.tracker,
            entries: sample.entries,
            periodCount: 365,
            cadence: .daily
        )
        let elapsed = Date.now.timeIntervalSince(start)

        #expect(history.count == 365)
        #expect(elapsed < 0.05, "365-period history took \(String(format: "%.3f", elapsed))s")
    }
}
