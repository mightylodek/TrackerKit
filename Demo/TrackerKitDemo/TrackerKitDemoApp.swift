import SwiftUI
import TrackerKit

/// Demo host for TrackerKit.
///
/// Deliberately thin — every screen you see comes from the library. If this file
/// ever grows past a few dozen lines, something that belongs in TrackerKit has
/// leaked into the app.
/// Identifiers shared between the app and its extensions.
///
/// Kept in one place because an App Group that disagrees by a character between
/// two targets fails silently — the container just comes back nil and the widget
/// shows placeholder data forever.
enum TrackerDashIDs {
    static let appGroup = "group.com.mightylodek.software.trackerkit"
}

@main
struct TrackerKitDemoApp: App {

    init() {
        // Registers the export-reminder notification category and the router that
        // turns a tapped reminder into a pre-filled composer.
        TrackerKit.configure()
    }

    static func theme(named name: String?) -> TrackerTheme {
        switch name?.lowercased() {
        case "editorial": .editorial
        case "vivid": .vivid
        case "standard": .standard
        case "nocturne": .nocturne
        default: .nocturne
        }
    }

    var body: some Scene {
        WindowGroup {
            // TKDEMO_DETAIL=<tracker name> opens a tracker detail screen directly.
            // Glass is composited at display time and cannot be captured from an
            // offscreen render, so verifying the floating action bar means seeing
            // it on a real screen. Every type used here is public library API.
            if let wanted = ProcessInfo.processInfo.environment["TKDEMO_DETAIL"] {
                DirectDetail(
                    trackerName: wanted,
                    theme: Self.theme(named: ProcessInfo.processInfo.environment["TKDEMO_THEME"])
                )
            } else {
                TrackerKitRootView(
                configuration: TrackerKitConfiguration(
                    // In-memory so the demo starts from the same seeded state every
                    // launch. Flip to `false` (and drop `seedSampleDataWhenEmpty`)
                    // to get a real persistent store.
                    inMemory: true,
                    // Shared container for the widget extension. Both the app and
                    // the widget declare this in their entitlements; without it
                    // the app runs fine and widgets simply never update, which
                    // `SharedSnapshotStore.isConfigured` reports honestly.
                    appGroupIdentifier: TrackerDashIDs.appGroup,
                    seedSampleDataWhenEmpty: true,
                    // TKDEMO_THEME=editorial|vivid swaps the entire visual identity.
                    // Same views, same data — only the tokens change.
                    theme: Self.theme(named: ProcessInfo.processInfo.environment["TKDEMO_THEME"]),
                    autoLockInterval: 0,
                    // Set TKDEMO_PROFILE=Alex to skip the picker — handy for
                    // demoing one screen repeatedly, or for capturing screenshots.
                    autoSelectProfileNamed: ProcessInfo.processInfo.environment["TKDEMO_PROFILE"],
                    // TKDEMO_TAB=gallery opens straight into the visual gallery.
                    initialTab: ProcessInfo.processInfo.environment["TKDEMO_TAB"]
                        .flatMap(TrackerKitTab.init(rawValue:)) ?? .today,
                    // Showcase control — on for the demo, off in a real app.
                    showsHeroStyleSwitcher: true
                    )
                )
            }
        }
    }
}

/// Opens straight onto one tracker's detail screen.
private struct DirectDetail: View {
    let trackerName: String
    let theme: TrackerTheme

    @State private var store = TrackerStore.preview()

    var body: some View {
        let session = ProfileSession(store: store)
        let tracker = store.activeTrackers.first {
            $0.title.localizedCaseInsensitiveContains(trackerName)
        } ?? store.activeTrackers[0]

        NavigationStack {
            TrackerDetailView(tracker: tracker, store: store, session: session)
        }
        .trackerTheme(theme)
    }
}
