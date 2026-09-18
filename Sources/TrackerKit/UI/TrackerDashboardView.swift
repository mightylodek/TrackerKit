import SwiftUI

/// The home screen: hero, rollup, and every tracker with one-tap logging.
///
/// Ordering is deliberate. Trackers that need attention float up, met goals sink.
/// A dashboard sorted by creation date makes the user do the scanning that the
/// software should have done for them.
public struct TrackerDashboardView: View {
    @Environment(\.trackerTheme) private var theme

    private let store: TrackerStore
    private let session: ProfileSession
    private let showsHeroStyleSwitcher: Bool

    @State private var heroStyle: HeroStyle
    @State private var isAddingTracker = false
    @State private var loggingTracker: Tracker?
    @State private var showArchived = false
    @State private var sortMode: SortMode = .attention

    public enum SortMode: String, CaseIterable, Identifiable {
        case attention = "Needs attention"
        case custom = "My order"
        case name = "Name"

        public var id: String { rawValue }
    }

    /// - Parameter showsHeroStyleSwitcher: puts a live hero-style picker on the
    ///   screen. Off by default — it is a showcase control, and shipping one in
    ///   a production dashboard reads as an unfinished setting rather than a
    ///   feature. The demo app turns it on.
    public init(
        store: TrackerStore,
        session: ProfileSession,
        heroStyle: HeroStyle = .rings,
        showsHeroStyleSwitcher: Bool = false
    ) {
        self.store = store
        self.session = session
        self.showsHeroStyleSwitcher = showsHeroStyleSwitcher
        _heroStyle = State(initialValue: heroStyle)
    }

    // MARK: Data

    private var snapshots: [ProgressSnapshot] {
        store.currentProgressAll()
    }

    private var snapshotsByID: [UUID: ProgressSnapshot] {
        Dictionary(uniqueKeysWithValues: snapshots.map { ($0.trackerID, $0) })
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

    private var loginStreak: StreakSummary { store.loginStreak() }

    private var streakDays: [(date: Date, isActive: Bool)] {
        store.streaks.activityFlags(days: store.loginDays.map(\.day), dayCount: 14)
    }

    private var headlineTracker: Tracker? {
        // The one most worth featuring: worst status that still has a goal.
        let byID = snapshotsByID
        return store.activeTrackers
            .filter { byID[$0.id]?.goal != nil }
            .max { lhs, rhs in
                (byID[lhs.id]?.status ?? .neutral) < (byID[rhs.id]?.status ?? .neutral)
            }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                hero
                    .padding(.horizontal)

                if !snapshots.isEmpty {
                    TrackerCard(title: "Where everything stands") {
                        StoplightSummaryBar(snapshots: snapshots)
                    }
                    .padding(.horizontal)
                }

                controls
                    .padding(.horizontal)

                if !visibleTrackers.isEmpty {
                    trackerList
                        .padding(.horizontal, theme.spacing.screenMargin)
                }

                if visibleTrackers.isEmpty {
                    emptyState
                        .padding(.horizontal)
                }

                addButton
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            .padding(.vertical)
        }
        .background(theme.plane)
        .navigationTitle(store.activeProfile?.name ?? "Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAddingTracker) {
            TrackerEditorView(store: store, tracker: nil)
        }
        .sheet(item: $loggingTracker) { tracker in
            LogEntryView(tracker: tracker, store: store, session: session)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 10) {
            HeroSectionView(
                style: heroStyle,
                profile: store.activeProfile,
                trackers: store.activeTrackers,
                snapshots: snapshots,
                loginStreak: loginStreak,
                streakDays: streakDays,
                headlineTracker: headlineTracker,
                headlineValues: headlineTracker.map {
                    store.dailyValues(for: $0.id, dayCount: 30)
                } ?? []
            )

            if showsHeroStyleSwitcher {
                Picker("Hero style", selection: $heroStyle.animation(theme.motion.snappyAnimation)) {
                    ForEach(HeroStyle.allCases, id: \.self) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack {
            Picker("Sort", selection: $sortMode.animation(theme.motion.snappyAnimation)) {
                ForEach(SortMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .font(theme.typography.subheadline)

            Spacer()

            Toggle("Archived", isOn: $showArchived.animation())
                .toggleStyle(.button)
                .font(theme.typography.subheadline)
        }
        .tint(theme.accent)
    }

    // MARK: Tracker list

    /// One container, hairline separators, no per-row shadow.
    ///
    /// The previous version gave every tracker its own elevated card, which at
    /// eight trackers turned the dashboard into a stack of floating rectangles
    /// competing with the hero. A list of things is a list, and drawing it as one
    /// leaves the hero as the only object on the screen asking for attention.
    private var trackerList: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleTrackers.enumerated()), id: \.element.id) { index, tracker in
                // Value-based so a widget deep link can push the identical
                // destination by appending to the navigation path.
                NavigationLink(value: tracker) {
                    TrackerRowCard(
                        tracker: tracker,
                        snapshot: snapshotsByID[tracker.id],
                        streak: store.goalStreak(for: tracker.id),
                        sparkline: store.dailyValues(for: tracker.id, dayCount: 21),
                        isGrouped: true,
                        onQuickLog: { quickLog(tracker) },
                        onDetailedLog: { loggingTracker = tracker }
                    )
                }
                .buttonStyle(.plain)
                .staggeredAppear(index: min(index, 8))

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

    // MARK: Empty and add

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "target")
                .font(theme.typography.display(.largeTitle))
                .foregroundStyle(theme.textMuted)
            Text("Nothing tracked yet")
                .font(theme.typography.heading)
                .foregroundStyle(theme.textPrimary)
            Text("Add the first habit or goal for \(store.activeProfile?.name ?? "this profile").")
                .font(theme.typography.callout)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var addButton: some View {
        Button {
            isAddingTracker = true
        } label: {
            Label("Add tracker", systemImage: "plus")
                .font(theme.typography.heading)
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            theme.accent.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                }
        }
        .buttonStyle(.plain)
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
        onQuickLog: @escaping () -> Void,
        onDetailedLog: @escaping () -> Void
    ) {
        self.tracker = tracker
        self.snapshot = snapshot
        self.streak = streak
        self.sparkline = sparkline
        self.isGrouped = isGrouped
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

                    logButton
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

    private var logButton: some View {
        Button(action: onQuickLog) {
            Image(systemName: tracker.kind == .checkbox
                  ? (isDoneToday ? "checkmark.circle.fill" : "circle")
                  : "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(isDoneToday ? theme.statusColor(.green) : theme.identityColor(for: tracker))
                .contentTransition(.symbolEffect(.replace))
                .trackerTouchTarget()
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.increase, trigger: snapshot?.actual ?? 0)
        .accessibilityLabel(tracker.kind == .checkbox ? "Toggle \(tracker.title)" : "Add to \(tracker.title)")
        .simultaneousGesture(
            LongPressGesture().onEnded { _ in onDetailedLog() }
        )
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
