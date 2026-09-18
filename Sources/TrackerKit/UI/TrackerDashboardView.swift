import SwiftUI

/// The home screen.
///
/// Composed from the profile's own ``DashboardCard`` layout rather than a fixed
/// arrangement, so the visuals in the gallery can actually be put here. Two kids
/// sharing an iPad get genuinely different dashboards.
public struct TrackerDashboardView: View {
    @Environment(\.trackerTheme) private var theme

    private let store: TrackerStore
    private let session: ProfileSession
    private let showsHeroStyleSwitcher: Bool

    @State private var isAddingTracker = false
    @State private var isCustomising = false
    @State private var loggingTracker: Tracker?

    public init(
        store: TrackerStore,
        session: ProfileSession,
        showsHeroStyleSwitcher: Bool = false
    ) {
        self.store = store
        self.session = session
        self.showsHeroStyleSwitcher = showsHeroStyleSwitcher
    }

    /// Cards that can actually be drawn — one pointing at a deleted tracker is
    /// skipped rather than rendering an empty frame.
    private var cards: [DashboardCard] {
        store.dashboardLayout.filter { store.canRender($0) }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: theme.spacing.sectionGap) {
                ForEach(cards) { card in
                    DashboardCardView(
                        card: card,
                        store: store,
                        session: session,
                        showsHeroStyleSwitcher: showsHeroStyleSwitcher,
                        onLog: quickLog,
                        onDetailedLog: { loggingTracker = $0 }
                    )
                    .padding(.horizontal, theme.spacing.screenMargin)
                }

                if store.activeTrackers.isEmpty {
                    emptyState
                        .padding(.horizontal, theme.spacing.screenMargin)
                }

                footerActions
                    .padding(.horizontal, theme.spacing.screenMargin)
            }
            .padding(.vertical)
            // Clearance for the floating tab bar. Without it the last rows sit
            // permanently underneath it and their quick-log buttons cannot be
            // tapped at all — the bar is ~83pt and content scrolls beneath it.
            .padding(.bottom, theme.spacing.xxl * 2)
        }
        .background(theme.plane)
        .trackerUndoBar(store: store)
        .navigationTitle(store.activeProfile?.name ?? "Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add tracker", systemImage: "plus") { isAddingTracker = true }
                    Button("Customise dashboard", systemImage: "square.grid.2x2") {
                        isCustomising = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("dashboard.menu")
            }
        }
        .sheet(isPresented: $isAddingTracker) {
            TrackerEditorView(store: store, tracker: nil)
        }
        .sheet(isPresented: $isCustomising) {
            DashboardEditorView(store: store)
        }
        .sheet(item: $loggingTracker) { tracker in
            LogEntryView(tracker: tracker, store: store, session: session)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing tracked yet", systemImage: "target")
        } description: {
            Text("Add the first habit or goal for \(store.activeProfile?.name ?? "this profile").")
        } actions: {
            Button("Add tracker") { isAddingTracker = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var footerActions: some View {
        HStack(spacing: theme.spacing.md) {
            Button {
                isAddingTracker = true
            } label: {
                Label("Add tracker", systemImage: "plus")
                    .font(theme.typography.heading)
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, theme.spacing.md)
                    .background {
                        theme.radii.controlShape
                            .stroke(theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
            }
            .buttonStyle(.plain)

            Button {
                isCustomising = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(theme.typography.heading)
                    .foregroundStyle(theme.textSecondary)
                    .trackerTouchTarget(52)
                    .background {
                        theme.radii.controlShape.stroke(theme.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customise dashboard")
            .accessibilityIdentifier("dashboard.customise")
        }
    }

    private func quickLog(_ tracker: Tracker) {
        if tracker.kind == .checkbox {
            store.toggle(trackerID: tracker.id)
        } else {
            store.log(trackerID: tracker.id)
        }
        session.touch()
        session.publishWidgets()
    }
}

// MARK: - HeroCardSection

/// The hero, with the demo's style switcher optionally attached.
public struct HeroCardSection: View {
    @Environment(\.trackerTheme) private var theme

    private let store: TrackerStore
    private let showsSwitcher: Bool
    @State private var style: HeroStyle

    public init(style: HeroStyle, store: TrackerStore, showsSwitcher: Bool) {
        self.store = store
        self.showsSwitcher = showsSwitcher
        _style = State(initialValue: style)
    }

    private var snapshots: [ProgressSnapshot] { store.currentProgressAll() }

    private var headlineTracker: Tracker? {
        let byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.trackerID, $0) })
        return store.activeTrackers
            .filter { byID[$0.id]?.goal != nil }
            .max { (byID[$0.id]?.status ?? .neutral) < (byID[$1.id]?.status ?? .neutral) }
    }

    public var body: some View {
        VStack(spacing: theme.spacing.sm) {
            HeroSectionView(
                style: style,
                profile: store.activeProfile,
                trackers: store.activeTrackers,
                snapshots: snapshots,
                loginStreak: store.loginStreak(),
                streakDays: store.streaks.activityFlags(
                    days: store.loginDays.map(\.day), dayCount: 14
                ),
                headlineTracker: headlineTracker,
                headlineValues: headlineTracker.map {
                    store.dailyValues(for: $0.id, dayCount: 30)
                } ?? []
            )

            if showsSwitcher {
                Picker("Hero style", selection: $style.animation(theme.motion.snappyAnimation)) {
                    ForEach(HeroStyle.allCases, id: \.self) { option in
                        Text(option.rawValue.capitalized).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

// MARK: - TrackerListSection

/// Every tracker in one container, with sorting and the archived toggle.
public struct TrackerListSection: View {
    @Environment(\.trackerTheme) private var theme

    private let store: TrackerStore
    private let session: ProfileSession
    private let onLog: (Tracker) -> Void
    private let onDetailedLog: (Tracker) -> Void

    @State private var showArchived = false
    @State private var sortMode: SortMode = .attention

    public enum SortMode: String, CaseIterable, Identifiable {
        case attention = "Needs attention"
        case custom = "My order"
        case name = "Name"
        public var id: String { rawValue }
    }

    public init(
        store: TrackerStore,
        session: ProfileSession,
        onLog: @escaping (Tracker) -> Void,
        onDetailedLog: @escaping (Tracker) -> Void
    ) {
        self.store = store
        self.session = session
        self.onLog = onLog
        self.onDetailedLog = onDetailedLog
    }

    private var snapshotsByID: [UUID: ProgressSnapshot] {
        Dictionary(uniqueKeysWithValues: store.currentProgressAll().map { ($0.trackerID, $0) })
    }

    private var visibleTrackers: [Tracker] {
        let base = showArchived ? store.trackers : store.activeTrackers
        let byID = snapshotsByID

        switch sortMode {
        case .custom:
            return base
        case .name:
            return base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .attention:
            return base.sorted { lhs, rhs in
                let left = byID[lhs.id]?.status ?? .neutral
                let right = byID[rhs.id]?.status ?? .neutral
                if left != right { return left > right }
                return lhs.sortIndex < rhs.sortIndex
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            HStack {
                Picker("Sort", selection: $sortMode.animation(theme.motion.snappyAnimation)) {
                    ForEach(SortMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.menu)
                .font(theme.typography.subheadline)

                Spacer()

                Toggle("Archived", isOn: $showArchived.animation())
                    .toggleStyle(.button)
                    .font(theme.typography.subheadline)
            }

            if !visibleTrackers.isEmpty {
                list
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleTrackers.enumerated()), id: \.element.id) { index, tracker in
                // The link and the quick-log button are siblings, never nested.
                // A Button inside a NavigationLink's label doesn't reliably get
                // the tap — the link takes it — so logging silently did nothing.
                HStack(spacing: 0) {
                    NavigationLink(value: tracker) {
                        TrackerRowCard(
                            tracker: tracker,
                            snapshot: snapshotsByID[tracker.id],
                            streak: store.goalStreak(for: tracker.id),
                            sparkline: store.dailyValues(for: tracker.id, dayCount: 21),
                            isGrouped: true,
                            showsLogButton: false,
                            onQuickLog: { onLog(tracker) },
                            onDetailedLog: { onDetailedLog(tracker) }
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("row.\(tracker.title)")

                    TrackerQuickLogButton(
                        tracker: tracker,
                        snapshot: snapshotsByID[tracker.id],
                        onQuickLog: { onLog(tracker) },
                        onLogAmount: { amount in
                            store.log(trackerID: tracker.id, value: amount)
                            session.touch()
                            session.publishWidgets()
                        },
                        onDetailedLog: { onDetailedLog(tracker) }
                    )
                    .padding(.trailing, theme.spacing.cardPadding)
                }

                if index < visibleTrackers.count - 1 {
                    Divider()
                        .overlay(theme.gridline)
                        .padding(.leading, theme.spacing.cardPadding + 50)
                }
            }
        }
        .clipShape(theme.radii.cardShape)
        .trackerCardSurface()
    }
}

// MARK: - TrackerQuickLogButton

/// One-tap logging.
///
/// Deliberately a standalone view rather than part of the row, because it must
/// be a **sibling** of any `NavigationLink`, never a child of one. A `Button`
/// inside a link's label doesn't reliably receive taps — SwiftUI routes them to
/// the link — which is exactly how a quick-log button ends up doing nothing.
public struct TrackerQuickLogButton: View {
    @Environment(\.trackerTheme) private var theme

    private let tracker: Tracker
    private let snapshot: ProgressSnapshot?
    private let onQuickLog: () -> Void
    private let onLogAmount: (Double) -> Void
    private let onDetailedLog: () -> Void

    public init(
        tracker: Tracker,
        snapshot: ProgressSnapshot?,
        onQuickLog: @escaping () -> Void,
        onLogAmount: @escaping (Double) -> Void = { _ in },
        onDetailedLog: @escaping () -> Void
    ) {
        self.tracker = tracker
        self.snapshot = snapshot
        self.onQuickLog = onQuickLog
        self.onLogAmount = onLogAmount
        self.onDetailedLog = onDetailedLog
    }

    private var isDoneToday: Bool {
        guard tracker.kind == .checkbox, let snapshot else { return false }
        return snapshot.actual > 0
    }

    public var body: some View {
        Button(action: onQuickLog) {
            Image(systemName: tracker.kind == .checkbox
                  ? (isDoneToday ? "checkmark.circle.fill" : "circle")
                  : "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(
                    isDoneToday ? theme.statusColor(.green) : theme.identityColor(for: tracker)
                )
                .contentTransition(.symbolEffect(.replace))
                .trackerTouchTarget()
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.increase, trigger: snapshot?.actual ?? 0)
        // A context menu rather than a bare `simultaneousGesture` long-press:
        // the gesture competed with the button's own tap recognition, and a
        // hidden long-press is undiscoverable besides.
        // Multiples of the step, so a bigger session isn't twenty taps, and so
        // the amount one tap adds is stated somewhere a person can find it.
        .contextMenu {
            if tracker.kind != .checkbox {
                ForEach([1.0, 2.0, 4.0], id: \.self) { multiple in
                    let amount = tracker.quickLogStep * multiple
                    Button("Add \(Formatters.value(amount, unit: tracker.unit))") {
                        onLogAmount(amount)
                    }
                }
                Divider()
            }
            Button("Log a specific amount…", systemImage: "slider.horizontal.3") {
                onDetailedLog()
            }
        }
        .accessibilityLabel(
            tracker.kind == .checkbox
                ? "Toggle \(tracker.title)"
                : "Add \(Formatters.value(tracker.quickLogStep, unit: tracker.unit)) to \(tracker.title)"
        )
        .accessibilityIdentifier("quickLog.\(tracker.title)")
    }
}

// MARK: - TrackerRowCard

/// A tracker on the dashboard: identity, standing, a sparkline, and logging in one tap.
public struct TrackerRowCard: View {
    @Environment(\.trackerTheme) private var theme

    private let tracker: Tracker
    private let snapshot: ProgressSnapshot?
    private let streak: StreakSummary
    private let sparkline: [DailyValue]
    private let onQuickLog: () -> Void
    private let onDetailedLog: () -> Void
    private let isGrouped: Bool
    private let showsLogButton: Bool

    /// - Parameter showsLogButton: set false when the caller places a
    ///   ``TrackerQuickLogButton`` alongside the row instead. Required whenever
    ///   the row is wrapped in a `NavigationLink`.
    /// - Parameter isGrouped: when true the row draws no surface of its own,
    ///   because it sits inside a shared list container. A list of eight
    ///   individually-shadowed cards reads as clutter; one container with
    ///   separators reads as a list, which is what it is.
    public init(
        tracker: Tracker,
        snapshot: ProgressSnapshot?,
        streak: StreakSummary,
        sparkline: [DailyValue],
        isGrouped: Bool = false,
        showsLogButton: Bool = true,
        onQuickLog: @escaping () -> Void,
        onDetailedLog: @escaping () -> Void
    ) {
        self.tracker = tracker
        self.snapshot = snapshot
        self.streak = streak
        self.sparkline = sparkline
        self.isGrouped = isGrouped
        self.showsLogButton = showsLogButton
        self.onQuickLog = onQuickLog
        self.onDetailedLog = onDetailedLog
    }

    /// A whisper of the status colour behind rows that need attention.
    ///
    /// Carries information rather than decorating: scanning the list, the rows
    /// that need you are the ones sitting on warm ground. Kept far below the
    /// threshold where it would compete with the status badge or the bar.
    private var rowGround: Color {
        guard let snapshot, snapshot.status == .red || snapshot.status == .yellow else {
            return .clear
        }
        return theme.statusColor(snapshot.status).opacity(snapshot.status == .red ? 0.07 : 0.05)
    }

    private var isDoneToday: Bool {
        guard tracker.kind == .checkbox, let snapshot else { return false }
        return snapshot.actual > 0
    }

    public var body: some View {
        if isGrouped {
            rowContent
                .padding(.horizontal, theme.spacing.cardPadding)
                .padding(.vertical, theme.spacing.rowGap)
                .background(rowGround)
                .contentShape(Rectangle())
        } else {
            TrackerCard { rowContent }
                .contentShape(Rectangle())
        }
    }

    private var rowContent: some View {
        VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tracker.symbolName)
                        .font(.body)
                        .foregroundStyle(theme.identityColor(for: tracker))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(theme.identityColor(for: tracker).opacity(0.14)))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(tracker.title)
                                .font(theme.typography.heading)
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)

                            if tracker.isArchived {
                                Text("ARCHIVED")
                                    .font(theme.typography.eyebrow.weight(.heavy))
                                    .foregroundStyle(theme.textMuted)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(theme.plane))
                            }
                        }

                        if let snapshot {
                            Text(snapshot.progressTextWithTarget)
                                .font(theme.typography.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(theme.textSecondary)
                                .contentTransition(.numericText())
                        }
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 6) {
                        if let snapshot, snapshot.status != .neutral {
                            StoplightBadge(status: snapshot.status, size: .small, showsLabel: false)
                        }
                        if streak.current > 1 {
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill").font(.system(size: 9))
                                Text("\(streak.current)")
                                    .font(theme.typography.micro.weight(.bold))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(theme.identityColor(for: tracker))
                        }
                    }

                    if showsLogButton {
                        TrackerQuickLogButton(
                            tracker: tracker,
                            snapshot: snapshot,
                            onQuickLog: onQuickLog,
                            onDetailedLog: onDetailedLog
                        )
                    }
                }

                if let snapshot, snapshot.target != nil {
                    MiniProgressBar(
                        fraction: snapshot.fraction ?? 0,
                        status: snapshot.status,
                        color: theme.identityColor(for: tracker),
                        height: 6,
                        breachesLimit: snapshot.breachesLimit
                    )
                }

            if sparkline.count > 2 {
                SparklineView(
                    dailyValues: sparkline,
                    color: theme.identityColor(for: tracker),
                    style: .bars
                )
                .frame(height: 26)
            }
        }
    }
}

#Preview("Dashboard") {
    let store = TrackerStore.preview()
    let session = ProfileSession(store: store)
    session.select(store.profiles[0])

    return NavigationStack {
        TrackerDashboardView(store: store, session: session)
    }
}
