import SwiftUI
import SwiftData
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
            if ProcessInfo.processInfo.environment["TKDEMO_ONBOARD"] != nil {
                EmptyProfileDemo(
                    theme: Self.theme(named: ProcessInfo.processInfo.environment["TKDEMO_THEME"])
                )
            } else if ProcessInfo.processInfo.environment["TKDEMO_PINSETUP"] != nil {
                // Opens PIN setup directly. Reaching it by hand is four taps deep
                // in Settings, and the first-run bug lived in this flow.
                PINSetupDemo(
                    theme: Self.theme(named: ProcessInfo.processInfo.environment["TKDEMO_THEME"])
                )
            } else if ProcessInfo.processInfo.environment["TKDEMO_FRESH"] != nil {
                // A genuinely cold start: no profiles, no trackers, nothing
                // seeded. This is the only route that exercises the welcome
                // screen and the hand-off from profile creation to the wizard.
                TrackerKitRootView(
                    configuration: TrackerKitConfiguration(
                        inMemory: true,
                        seedSampleDataWhenEmpty: false,
                        theme: Self.theme(named: ProcessInfo.processInfo.environment["TKDEMO_THEME"]),
                        autoLockInterval: 0
                    )
                )
            } else if ProcessInfo.processInfo.environment["TKDEMO_SEEDLAYOUT"] != nil {
                // Screenshot aid: seeds a customised dashboard so the arranged
                // layout can be captured without driving the editor by hand.
                SeededLayoutDemo(
                    theme: Self.theme(named: ProcessInfo.processInfo.environment["TKDEMO_THEME"])
                )
            } else if let wanted = ProcessInfo.processInfo.environment["TKDEMO_DETAIL"] {
                DirectDetail(
                    trackerName: wanted,
                    theme: Self.theme(named: ProcessInfo.processInfo.environment["TKDEMO_THEME"])
                )
            } else {
                TrackerKitRootView(
                configuration: TrackerKitConfiguration(
                    // On-disk by default. The demo ran in-memory for most of its
                    // life, which meant the real SwiftData path — the one every
                    // actual user is on — had never once executed. Automated runs
                    // opt back into a clean slate with TKDEMO_INMEMORY=1; a device
                    // gets the storage a shipped app would use.
                    inMemory: ProcessInfo.processInfo.environment["TKDEMO_INMEMORY"] != nil,
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

/// A profile with no trackers, so the onboarding wizard runs for real.
private struct EmptyProfileDemo: View {
    let theme: TrackerTheme

    @State private var store: TrackerStore = {
        let container = try! TrackerKitSchema.container(inMemory: true)
        return TrackerStore(context: ModelContext(container))
    }()

    var body: some View {
        let session = ProfileSession(store: store)
        NavigationStack {
            TrackerDashboardView(store: store, session: session)
        }
        .trackerTheme(theme)
        .task {
            if store.profiles.isEmpty {
                let profile = store.addProfile(name: "Sam")
                session.select(profile)
            }
        }
    }
}

/// PIN setup on its own, for driving the enter-then-confirm flow.
private struct PINSetupDemo: View {
    let theme: TrackerTheme

    @State private var store = TrackerStore.preview()
    @State private var completed: String?

    var body: some View {
        VStack(spacing: 12) {
            if let completed {
                Text("PIN set: \(completed)")
                    .accessibilityIdentifier("pinsetup.result")
            }
            if let profile = store.profiles.first {
                PINSetupView(profile: profile) { completed = $0 }
            }
        }
        .trackerTheme(theme)
    }
}

/// A dashboard with extra cards already added.
private struct SeededLayoutDemo: View {
    let theme: TrackerTheme
    @State private var store = TrackerStore.preview()

    var body: some View {
        let session = ProfileSession(store: store)
        NavigationStack {
            TrackerDashboardView(store: store, session: session)
        }
        .trackerTheme(theme)
        .task {
            session.select(store.profiles[0])
            guard let focus = store.activeTrackers.first(where: { $0.title == "Focus Time" })
                    ?? store.activeTrackers.first else { return }
            store.setDashboardLayout([
                DashboardCard(kind: .hero, heroStyle: .compact),
                DashboardCard(kind: .heatmap, trackerID: focus.id),
                DashboardCard(kind: .streak),
                DashboardCard(kind: .trackerList)
            ])
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
