import SwiftUI

/// One tracker in depth: current standing, a switchable chart, streaks, and the
/// raw entries behind the numbers.
///
/// The chart picker is not a gimmick — the same data answers different questions
/// in different forms, and which form is right depends on what the user is asking.
/// "Am I consistent?" is a heatmap question; "am I improving?" is a line question.
public struct TrackerDetailView: View {
    @Environment(\.trackerTheme) private var theme

    public enum ChartMode: String, CaseIterable, Identifiable {
        case periods = "Goal"
        case line = "Trend"
        case area = "Volume"
        case heatmap = "Consistency"
        case rhythm = "Rhythm"
        case replay = "Replay"

        public var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .periods: "chart.bar.fill"
            case .line: "chart.xyaxis.line"
            case .area: "chart.line.uptrend.xyaxis"
            case .heatmap: "square.grid.3x3.fill"
            case .rhythm: "cube.fill"
            case .replay: "play.circle.fill"
            }
        }

        /// What this form is good at — shown under the chart so the picker teaches.
        var explanation: String {
            switch self {
            case .periods: "Each period against the goal that was in force then."
            case .line: "The level over time, with a 7-point average."
            case .area: "How much accumulated, day by day."
            case .heatmap: "Which days you showed up. Gaps are the story."
            case .rhythm: "Weekday against week — where the pattern hides."
            case .replay: "History drawing itself, goal changes and all."
            }
        }
    }

    private let tracker: Tracker
    private let store: TrackerStore
    private let session: ProfileSession?

    @State private var mode: ChartMode = .periods
    @State private var range: HistoryRange = .ninetyDays
    @State private var isLogging = false
    @State private var isEditing = false

    public enum HistoryRange: String, CaseIterable, Identifiable {
        case thirtyDays = "30D"
        case ninetyDays = "90D"
        case year = "1Y"

        public var id: String { rawValue }
        var days: Int {
            switch self {
            case .thirtyDays: 30
            case .ninetyDays: 90
            case .year: 365
            }
        }
        var periodCount: Int {
            switch self {
            case .thirtyDays: 30
            case .ninetyDays: 13
            case .year: 12
            }
        }
        var periodCadence: Cadence {
            switch self {
            case .thirtyDays: .daily
            case .ninetyDays: .weekly
            case .year: .monthly
            }
        }
    }

    public init(tracker: Tracker, store: TrackerStore, session: ProfileSession? = nil) {
        self.tracker = tracker
        self.store = store
        self.session = session
    }

    // MARK: Derived data

    private var current: ProgressSnapshot? {
        store.currentProgress(for: tracker.id)
    }

    private var history: [ProgressSnapshot] {
        store.history(
            for: tracker.id,
            periodCount: range.periodCount,
            cadence: tracker.currentGoal?.cadence ?? range.periodCadence
        )
    }

    private var daily: [DailyValue] {
        store.dailyValues(for: tracker.id, dayCount: range.days)
    }

    private var streak: StreakSummary {
        store.goalStreak(for: tracker.id)
    }

    private var trend: Trend? {
        store.trends.trend(from: history)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                standingCard
                chartCard
                streakCard
                goalCard
                entriesCard
            }
            .padding(theme.spacing.screenMargin)
        }
        .background(theme.plane)
        .navigationTitle(tracker.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Log entry", systemImage: "plus.circle") { isLogging = true }
                    Button("Edit tracker", systemImage: "pencil") { isEditing = true }
                    NavigationLink {
                        GoalHistoryView(tracker: tracker, store: store)
                    } label: {
                        Label("Goal history", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isLogging) {
            LogEntryView(tracker: tracker, store: store, session: session)
        }
        .sheet(isPresented: $isEditing) {
            TrackerEditorView(store: store, tracker: tracker)
        }
        .safeAreaInset(edge: .bottom) {
            logBar
        }
    }

    // MARK: Standing

    private var standingCard: some View {
        TrackerCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: tracker.symbolName)
                        .font(.title2)
                        .foregroundStyle(theme.identityColor(for: tracker))
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(theme.identityColor(for: tracker).opacity(0.14)))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(current?.period.label() ?? "Today")
                            .font(theme.typography.subheadline)
                            .foregroundStyle(theme.textSecondary)

                        if let current {
                            CountUpText(
                                value: current.actual,
                                unit: current.unit,
                                font: theme.typography.displaySize(38),
                                color: theme.textPrimary
                            )
                            .accessibilityIdentifier("detail.actual")
                            .tracking(theme.typography.displayTracking)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        }
                    }

                    Spacer()

                    if let current {
                        VStack(alignment: .trailing, spacing: 8) {
                            StoplightBadge(status: current.status)
                            if let trend {
                                TrendBadge(
                                    trend: trend,
                                    direction: current.direction,
                                    unit: current.unit
                                )
                            }
                        }
                    }
                }

                if let current, current.target != nil {
                    BulletChartView(
                        snapshot: current,
                        projected: store.trends.projectedTotal(for: current),
                        barHeight: 16,
                        showsValue: false
                    )

                    Text(store.progress.stoplight.explanation(
                        status: current.status,
                        actual: current.actual,
                        target: current.target,
                        direction: current.direction,
                        unit: current.unit,
                        daysRemaining: store.calculator.daysRemaining(in: current.period)
                    ))
                    .font(theme.typography.label)
                    .foregroundStyle(theme.textSecondary)
                }

                if !tracker.detail.isEmpty {
                    Text(tracker.detail)
                        .font(theme.typography.label)
                        .foregroundStyle(theme.textMuted)
                }
            }
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        TrackerCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Range", selection: $range) {
                        ForEach(HistoryRange.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)

                    Spacer()

                    Menu {
                        ForEach(ChartMode.allCases) { option in
                            Button {
                                withAnimation(theme.motion.snappyAnimation) { mode = option }
                            } label: {
                                Label(option.rawValue, systemImage: option.symbolName)
                            }
                        }
                    } label: {
                        Label(mode.rawValue, systemImage: mode.symbolName)
                            .font(theme.typography.subheadline.weight(.medium))
                    }
                }

                chartBody
                    .id(mode)

                Text(mode.explanation)
                    .font(theme.typography.label)
                    .foregroundStyle(theme.textMuted)
            }
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        switch mode {
        case .periods:
            TrackerPeriodBarChart(
                snapshots: history,
                seriesColorHex: tracker.colorHex,
                height: 210
            )

        case .line:
            TrackerLineChart(
                values: daily,
                name: tracker.title,
                colorHex: theme.identityColor(for: tracker).hexString,
                unit: tracker.unit,
                goalLine: dailyEquivalentTarget,
                movingAverageWindow: 7,
                height: 210
            )

        case .area:
            TrackerAreaChart(
                values: daily,
                name: tracker.title,
                colorHex: theme.identityColor(for: tracker).hexString,
                unit: tracker.unit,
                goalLine: dailyEquivalentTarget,
                height: 210
            )

        case .heatmap:
            HeatmapCalendarView(
                values: daily,
                colorHex: theme.identityColor(for: tracker).hexString,
                unit: tracker.unit
            )

        case .rhythm:
            Tracker3DChart(
                data: .weekdayByWeek(values: daily, unit: tracker.unit),
                height: 300
            )

        case .replay:
            ProgressReplayView(
                snapshots: history,
                title: tracker.title,
                colorHex: theme.identityColor(for: tracker).hexString,
                height: 210
            )
        }
    }

    /// A weekly goal expressed per day, so a daily chart has a meaningful line.
    private var dailyEquivalentTarget: Double? {
        guard let goal = tracker.currentGoal else { return nil }
        switch goal.cadence {
        case .daily: return goal.target
        case .total: return nil
        default:
            guard goal.aggregation == .sum else { return goal.target }
            return goal.target / goal.cadence.approximateDayCount
        }
    }

    // MARK: Streak

    private var streakCard: some View {
        let flags = store.streaks.activityFlags(
            days: store.entries(for: tracker.id).map(\.date),
            dayCount: 14
        )

        return StreakCard(
            streak: streak,
            days: flags,
            color: theme.identityColor(for: tracker),
            title: "Streak"
        )
    }

    // MARK: Goal

    @ViewBuilder
    private var goalCard: some View {
        if let goal = tracker.currentGoal {
            NavigationLink {
                GoalHistoryView(tracker: tracker, store: store)
            } label: {
                TrackerCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Current goal")
                                .font(theme.typography.label)
                                .foregroundStyle(theme.textMuted)
                            Text(goal.summary)
                                .font(theme.typography.heading)
                                .foregroundStyle(theme.textPrimary)
                            Text(
                                tracker.goalHistory.count > 1
                                    ? "\(tracker.goalHistory.count) versions on record"
                                    : "Set \(goal.effectiveFrom.formatted(date: .abbreviated, time: .omitted))"
                            )
                            .font(theme.typography.label)
                            .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.textMuted)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Entries

    private var entriesCard: some View {
        let recent = store.entries(for: tracker.id)
            .sorted { $0.date > $1.date }
            .prefix(12)

        return TrackerCard(title: "Recent entries") {
            if recent.isEmpty {
                Text("Nothing logged yet.")
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.textMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Formatters.friendlyDay(entry.date))
                                    .font(theme.typography.subheadline)
                                    .foregroundStyle(theme.textPrimary)
                                Text(entry.date.formatted(date: .omitted, time: .shortened))
                                    .font(theme.typography.micro)
                                    .foregroundStyle(theme.textMuted)
                            }

                            if let note = entry.note, !note.isEmpty {
                                Text(note)
                                    .font(theme.typography.label)
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(Formatters.value(entry.value, unit: tracker.unit))
                                .font(theme.typography.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(theme.textPrimary)

                            Button {
                                store.deleteEntry(entry.id)
                                session?.publishWidgets()
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(theme.textMuted)
                                    .trackerTouchTarget()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete entry")
                        }
                        .padding(.vertical, 9)

                        if index < recent.count - 1 {
                            Divider().overlay(theme.gridline)
                        }
                    }
                }
            }
        }
    }

    // MARK: Log bar

    /// The floating action cluster.
    ///
    /// This is the one surface in the detail screen that genuinely sits *above*
    /// the content, so it is the one that earns Liquid Glass. The primary action
    /// takes the accent tint; the secondary stays untinted so the hierarchy is
    /// readable without reading the labels.
    private var logBar: some View {
        GlassEffectContainer(spacing: theme.spacing.md) {
            HStack(spacing: theme.spacing.sm) {
                if tracker.kind == .checkbox {
                    checkboxAction
                } else {
                    quickAddAction
                    detailedLogAction
                }
            }
        }
        .padding(.horizontal, theme.spacing.screenMargin)
        .padding(.bottom, theme.spacing.sm)
    }

    private var isDoneToday: Bool {
        store.entries(for: tracker.id)
            .contains { store.calculator.isSameDay($0.date, .now) }
    }

    private var checkboxAction: some View {
        Button {
            store.toggle(trackerID: tracker.id)
            session?.touch()
            session?.publishWidgets()
        } label: {
            Label(
                isDoneToday ? "Done today" : "Mark done",
                systemImage: isDoneToday ? "checkmark.circle.fill" : "circle"
            )
            .font(theme.typography.heading)
            .foregroundStyle(
                isDoneToday ? theme.statusColor(.green) : theme.inkOnControl(isProminent: true)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.spacing.md)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .trackerControlSurface(shape: theme.radii.actionShape, isProminent: !isDoneToday)
        .sensoryFeedback(.success, trigger: isDoneToday)
        .accessibilityLabel(isDoneToday ? "Mark \(tracker.title) not done" : "Mark \(tracker.title) done")
    }

    private var quickAddAction: some View {
        Button {
            store.log(trackerID: tracker.id)
            session?.touch()
            session?.publishWidgets()
        } label: {
            Label(
                "Add \(Formatters.value(tracker.quickLogStep, unit: tracker.unit))",
                systemImage: "plus"
            )
            .font(theme.typography.heading)
            .foregroundStyle(theme.inkOnControl(isProminent: true))
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.spacing.md)
        }
        .buttonStyle(.plain)
        .trackerControlSurface(shape: theme.radii.actionShape, isProminent: true)
        .sensoryFeedback(.increase, trigger: current?.actual ?? 0)
        .accessibilityIdentifier("detail.quickAdd")
    }

    private var detailedLogAction: some View {
        Button {
            isLogging = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(theme.typography.heading)
                .foregroundStyle(theme.textPrimary)
                .trackerTouchTarget(theme.metrics.minimumTouchTarget + 8)
        }
        .buttonStyle(.plain)
        .trackerControlSurface(shape: theme.radii.actionAccessoryShape)
        .accessibilityLabel("Log a specific amount")
    }
}

#Preview("Tracker detail") {
    let store = TrackerStore.preview()
    return NavigationStack {
        TrackerDetailView(tracker: store.activeTrackers[1], store: store)
    }
}
