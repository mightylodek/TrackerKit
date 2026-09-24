// watchOS-only. See rule 17 in CLAUDE.md.
#if os(watchOS)

import SwiftUI
import SwiftData

// MARK: - WatchRootView

/// The whole watch app.
///
/// Standalone by design: the kids this is for have watches and no phones, so
/// nothing here waits on a companion. One profile, no picker and no PIN — the
/// watch is already behind the wearer's own passcode, and a 4-digit pad at 45mm
/// would be the worst screen in the app.
public struct WatchRootView: View {
    @Environment(\.trackerTheme) private var theme

    @State private var store: TrackerStore
    @State private var session: ProfileSession
    @State private var reportRequest: Tracker?

    private let theme_: TrackerTheme

    public init(configuration: TrackerKitConfiguration = TrackerKitConfiguration()) {
        let store: TrackerStore
        if let container = try? TrackerKitSchema.container(inMemory: configuration.inMemory) {
            store = TrackerStore(
                context: ModelContext(container),
                calculator: PeriodCalculator(calendar: configuration.calendar),
                stoplight: configuration.stoplight
            )
        } else {
            // A watch with no store is useless, but crashing on launch is worse
            // than running against memory until the next launch tries again.
            let container = try! TrackerKitSchema.container(inMemory: true)
            store = TrackerStore(context: ModelContext(container))
        }

        store.reload()

        let session = ProfileSession(store: store)
        if let only = store.profiles.first {
            session.enterWithoutAuthentication(only)
        }

        _store = State(initialValue: store)
        _session = State(initialValue: session)
        self.theme_ = configuration.theme
    }

    public var body: some View {
        Group {
            if store.activeProfileID == nil || store.activeTrackers.isEmpty {
                WatchOnboardingView(store: ensuredProfileStore())
            } else {
                habitPages
            }
        }
        .trackerTheme(theme_)
        .tint(theme_.accent)
        .sheet(item: $reportRequest) { tracker in
            WatchReportView(tracker: tracker, store: store)
        }
    }

    /// A watch has exactly one person on it. Make their profile on first launch
    /// so onboarding has somewhere to put the habits it creates.
    private func ensuredProfileStore() -> TrackerStore {
        if store.profiles.isEmpty {
            let me = store.addProfile(name: "Me")
            session.enterWithoutAuthentication(me)
        } else if store.activeProfileID == nil, let only = store.profiles.first {
            session.enterWithoutAuthentication(only)
        }
        return store
    }

    /// One habit per page, swipe between them.
    private var habitPages: some View {
        TabView {
            ForEach(store.activeTrackers) { tracker in
                NavigationStack {
                    WatchHabitPage(tracker: tracker, store: store) {
                        reportRequest = tracker
                    }
                }
                .tag(tracker.id)
            }
        }
        .tabViewStyle(.page)
    }
}

#endif
