import Testing
import Foundation
@testable import TrackerKit

/// The deep-link contract is shared between two separately-compiled binaries —
/// the app and the widget extension — so nothing but a test enforces that they
/// agree. A malformed link doesn't crash; it silently does nothing, which is the
/// hardest kind of bug to notice.
struct WidgetDeepLinkTests {

    @Test("Every link round-trips through its URL")
    func roundTrip() throws {
        let id = UUID()
        for link in [WidgetDeepLink.tracker(id), .log(id), .profile(id)] {
            let parsed = try #require(WidgetDeepLink(url: link.url))
            #expect(parsed == link)
        }
    }

    @Test("Links use the registered scheme")
    func scheme() {
        #expect(WidgetDeepLink.tracker(UUID()).url.scheme == "trackerdash")
        #expect(WidgetDeepLink.scheme == "trackerdash")
    }

    @Test("Foreign and malformed URLs are rejected rather than half-parsed")
    func rejectsForeign() {
        #expect(WidgetDeepLink(url: URL(string: "https://example.com/tracker/x")!) == nil)
        #expect(WidgetDeepLink(url: URL(string: "trackerdash://unknown/\(UUID().uuidString)")!) == nil)
        #expect(WidgetDeepLink(url: URL(string: "trackerdash://tracker/not-a-uuid")!) == nil)
        #expect(WidgetDeepLink(url: URL(string: "trackerdash://tracker")!) == nil)
    }

    @Test("Tracker links expose their target; profile links don't claim to")
    func trackerID() {
        let id = UUID()
        #expect(WidgetDeepLink.tracker(id).trackerID == id)
        #expect(WidgetDeepLink.log(id).trackerID == id)
        #expect(WidgetDeepLink.profile(id).trackerID == nil)
    }

    @Test("A snapshot's line IDs are real tracker IDs, so its links resolve")
    @MainActor
    func snapshotLinksResolve() throws {
        let store = TrackerStore.preview()
        let snapshot = try #require(store.widgetSnapshot())

        for line in snapshot.lines {
            let link = WidgetDeepLink.tracker(line.id)
            let parsed = try #require(WidgetDeepLink(url: link.url))
            let id = try #require(parsed.trackerID)
            // The widget builds links from these ids; if they don't resolve back
            // to a tracker the tap lands nowhere.
            #expect(store.tracker(id) != nil, "Widget line \(line.title) links to a missing tracker")
        }
    }
}
