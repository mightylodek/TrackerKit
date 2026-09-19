// iOS-only. These screens assume a phone or tablet canvas: navigation stacks,
// menus, segmented pickers, keyboard types and edit modes that either don't
// exist on watchOS or are the wrong interaction at 45mm.
//
// A watch app gets its own UI built on the same portable core (Model, Engine,
// Store, Theme, Security), not these views shrunk down. See docs/WATCH.md.
#if os(iOS)

import SwiftUI
import SwiftData

/// The whole library as one view.
///
/// Drop this in and you get profiles, the PIN gate, the dashboard, the visual
/// gallery and export settings. Everything underneath is public, so a host app
/// that wants its own navigation can ignore this and compose the pieces directly.
///
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             TrackerKitRootView(configuration: .init(appGroupIdentifier: "group.com.example.app"))
///         }
///     }
/// }
/// ```
public struct TrackerKitRootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var store: TrackerStore
    @State private var session: ProfileSession
    @State private var deliveryRequest: ExportRequest?

    private let theme: TrackerTheme
    private let initialTab: TrackerKitTab
    private let showsHeroStyleSwitcher: Bool

    public init(configuration: TrackerKitConfiguration = .init()) {
        let store: TrackerStore

        do {
            let container = try TrackerKitSchema.container(
                inMemory: configuration.inMemory,
                appGroupIdentifier: configuration.appGroupIdentifier
            )
            store = TrackerStore(
                context: ModelContext(container),
                calculator: PeriodCalculator(calendar: configuration.calendar),
                stoplight: configuration.stoplight
            )
        } catch {
            // A store that can't open is not recoverable, but crashing the host
            // app on launch is worse than running in memory for this session.
            let container = try! TrackerKitSchema.container(inMemory: true)
            store = TrackerStore(context: ModelContext(container))
        }

        store.reload()

        if configuration.seedSampleDataWhenEmpty, store.profiles.isEmpty {
            SampleData.seed(into: store)
            store.reload()
        }

        let session = ProfileSession(
            store: store,
            appGroupIdentifier: configuration.appGroupIdentifier
        )
        session.autoLockInterval = configuration.autoLockInterval

        if let name = configuration.autoSelectProfileNamed,
           let profile = store.profiles.first(where: {
               $0.name.caseInsensitiveCompare(name) == .orderedSame && !$0.isPINProtected
           }) {
            session.select(profile)
        }

        _store = State(initialValue: store)
        _session = State(initialValue: session)
        self.theme = configuration.theme
        self.initialTab = configuration.initialTab
        self.showsHeroStyleSwitcher = configuration.showsHeroStyleSwitcher
    }

    public var body: some View {
        ProfileGateView(store: store, session: session) {
            TrackerKitTabs(
                store: store,
                session: session,
                initialTab: initialTab,
                showsHeroStyleSwitcher: showsHeroStyleSwitcher
            )
        }
        .trackerTheme(theme)
        .tint(theme.accent)
        .onAppear {
            ExportScheduler.registerCategory()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                session.lockIfIdle()
                store.reload()
            case .background:
                session.publishWidgets()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackerKitExportRequested)) { note in
            guard let userInfo = note.userInfo,
                  let request = ExportRequest(userInfo: userInfo)
            else { return }
            deliveryRequest = request
        }
        .sheet(item: $deliveryRequest) { request in
            if let report = store.buildReport(
                for: request.profileID,
                lookbackDays: request.lookbackDays
            ) {
                ExportDeliveryView(
                    report: report,
                    channel: request.channel,
                    format: request.format,
                    recipients: store.schedules
                        .first { $0.id == request.scheduleID }?.recipients ?? []
                ) {
                    if let scheduleID = request.scheduleID {
                        store.markScheduleDelivered(scheduleID)
                    }
                }
                .trackerTheme(theme)
            }
        }
    }
}

// MARK: - TrackerKitTabs

/// The signed-in shell.
public struct TrackerKitTabs: View {
    @Environment(\.trackerTheme) private var theme

    private let store: TrackerStore
    private let session: ProfileSession

    @State private var selection: TrackerKitTab
    @State private var todayPath = NavigationPath()

    private let showsHeroStyleSwitcher: Bool

    public init(
        store: TrackerStore,
        session: ProfileSession,
        initialTab: TrackerKitTab = .today,
        showsHeroStyleSwitcher: Bool = false
    ) {
        self.store = store
        self.session = session
        self.showsHeroStyleSwitcher = showsHeroStyleSwitcher
        _selection = State(initialValue: initialTab)
    }

    /// Routes a widget deep link to the tracker it names.
    ///
    /// Silently ignores links to trackers that no longer exist — a widget can
    /// outlive the thing it points at, and a crash or an error alert would both
    /// be worse than landing on the dashboard.
    public func handle(_ link: WidgetDeepLink) {
        guard let id = link.trackerID, let tracker = store.tracker(id) else {
            selection = .today
            return
        }
        selection = .today
        todayPath = NavigationPath()
        todayPath.append(tracker)
    }

    public var body: some View {
        TabView(selection: $selection) {
            NavigationStack(path: $todayPath) {
                TrackerDashboardView(
                    store: store,
                    session: session,
                    showsHeroStyleSwitcher: showsHeroStyleSwitcher
                )
                .navigationDestination(for: Tracker.self) { tracker in
                    TrackerDetailView(tracker: tracker, store: store, session: session)
                }
                .toolbar { profileMenu }
            }
            .tabItem { Label("Today", systemImage: "chart.bar.doc.horizontal") }
            .tag(TrackerKitTab.today)

            NavigationStack {
                ChartGalleryView(store: store)
                    .toolbar { profileMenu }
            }
            .tabItem { Label("Gallery", systemImage: "square.grid.2x2") }
            .tag(TrackerKitTab.gallery)

            NavigationStack {
                TrackerKitSettingsView(store: store, session: session)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(TrackerKitTab.settings)
        }
        .onOpenURL { url in
            guard let link = WidgetDeepLink(url: url) else { return }
            handle(link)
        }
    }

    @ToolbarContentBuilder
    private var profileMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                ForEach(store.profiles) { profile in
                    Button {
                        session.select(profile)
                    } label: {
                        Label(
                            profile.name,
                            systemImage: profile.id == store.activeProfileID
                                ? "checkmark"
                                : (profile.isPINProtected ? "lock" : "person")
                        )
                    }
                }
                Divider()
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                    session.signOut()
                }
            } label: {
                ProfileAvatar(profile: store.activeProfile, size: 30)
            }
            .accessibilityLabel("Switch profile")
        }
    }
}

// MARK: - TrackerKitSettingsView

/// Profiles, exports, appearance and the data reset.
public struct TrackerKitSettingsView: View {
    @Environment(\.trackerTheme) private var theme

    private let store: TrackerStore
    private let session: ProfileSession

    /// Which profile editor is open, if any.
    ///
    /// One piece of state rather than two booleans, because two `.sheet`
    /// modifiers on one view silently cancel each other out.
    private enum ProfileSheet: Identifiable {
        case edit(Profile)
        case add

        var id: String {
            switch self {
            case .edit(let profile): profile.id.uuidString
            case .add: "add"
            }
        }

        var profile: Profile? {
            switch self {
            case .edit(let profile): profile
            case .add: nil
            }
        }
    }

    @State private var profileSheet: ProfileSheet?
    @State private var showResetConfirmation = false

    public init(store: TrackerStore, session: ProfileSession) {
        self.store = store
        self.session = session
    }

    public var body: some View {
        List {
            Section("Profiles") {
                ForEach(store.profiles) { profile in
                    let mayEdit = session.authority(over: profile) != .none
                    Button {
                        profileSheet = .edit(profile)
                    } label: {
                        HStack(spacing: 12) {
                            ProfileAvatar(profile: profile, size: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(profile.name)
                                    .font(.body)
                                    .foregroundStyle(theme.textPrimary)
                                Text(profileSubtitle(profile))
                                    .font(theme.typography.label)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            if profile.isPINProtected {
                                Image(systemName: "lock.fill")
                                    .font(theme.typography.label)
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                        // `.buttonStyle(.plain)` draws no background, so the gap
                        // the Spacer opens up is not hit-testable and a tap in
                        // the middle of the row falls straight through. The row
                        // is the target, not just the words in it.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // A member opening someone else's editor could rename them,
                    // change their colour, or switch their PIN off entirely.
                    .disabled(!mayEdit)
                    .opacity(mayEdit ? 1 : 0.5)
                    .accessibilityIdentifier("settings.profile.\(profile.name)")
                }

                Button {
                    profileSheet = .add
                } label: {
                    Label("Add profile", systemImage: "person.badge.plus")
                }
                .accessibilityIdentifier("settings.addProfile")
            }

            Section("Exports") {
                NavigationLink {
                    ExportSettingsView(store: store)
                } label: {
                    Label("Weekly reports", systemImage: "envelope")
                }
            }

            Section {
                LabeledContent("Trackers", value: "\(store.trackers.count)")
                LabeledContent("Entries", value: "\(store.entries.count)")
                LabeledContent("Days logged in", value: "\(store.loginDays.count)")
                LabeledContent("Login streak", value: store.loginStreak().displayText)
            } header: {
                Text("This profile")
            }

            Section {
                // Wiping every profile — and every PIN with them — is an owner's
                // call. A member could otherwise clear the device to get past a
                // lock they couldn't open.
                Button("Reset all data", role: .destructive) {
                    showResetConfirmation = true
                }
                .disabled(!session.activeProfileIsOwner)
            } footer: {
                Text("Removes every profile, tracker, goal and entry on this device. PINs are cleared too.")
            }

            Section {
                EmptyView()
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TrackerKit \(TrackerKit.version)")
                    Text("Charts use a colorblind-validated palette: worst adjacent CVD ΔE 9.1 in light, 8.4 in dark.")
                }
                .font(theme.typography.micro)
            }
        }
        .navigationTitle("Settings")
        // One sheet, not two. Stacking `.sheet(item:)` and `.sheet(isPresented:)`
        // on the same view leaves only one of them working — tapping a profile
        // here did nothing at all, silently, while "Add profile" worked fine.
        .sheet(item: $profileSheet) { sheet in
            ProfileEditorView(store: store, session: session, profile: sheet.profile)
        }
        .confirmationDialog(
            "Reset everything?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete all data", role: .destructive) {
                for profile in store.profiles {
                    PINManager.shared.removePIN(for: profile.id)
                }
                store.deleteEverything()
                ExportScheduler.cancelAll()
                session.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every profile and everything under it is removed. There is no undo.")
        }
    }

    private func profileSubtitle(_ profile: Profile) -> String {
        var parts = [profile.role.displayName]
        if profile.id == store.activeProfileID {
            parts.append("\(store.activeTrackers.count) trackers")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Root") {
    TrackerKitRootView(configuration: .init(inMemory: true, seedSampleDataWhenEmpty: true))
}

#endif
