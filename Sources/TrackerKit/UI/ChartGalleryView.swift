import SwiftUI

/// Every visual in the library, rendered against real data from the store.
///
/// This is documentation you can touch. It exists so that picking a chart is a
/// matter of scrolling until something looks right, and so that a regression in
/// any visual shows up the moment someone opens the app.
public struct ChartGalleryView: View {
    @Environment(\.trackerTheme) private var theme

    private let store: TrackerStore

    @State private var section: Section
    @State private var pendingKind: DashboardCard.Kind?
    @State private var addedKind: DashboardCard.Kind?

    public enum Section: String, CaseIterable, Identifiable {
        case timeSeries = "Time series"
        case goals = "Goals"
        case rings = "Rings & dials"
        case calendars = "Calendars"
        case dimensional = "3-D"
        case widgets = "Widgets"
        case heroes = "Heroes"

        public var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .timeSeries: "chart.xyaxis.line"
            case .goals: "target"
            case .rings: "circle.circle"
            case .calendars: "calendar"
            case .dimensional: "cube"
            case .widgets: "square.grid.2x2"
            case .heroes: "rectangle.topthird.inset.filled"
            }
        }
    }

    public init(store: TrackerStore, initialSection: Section = .timeSeries) {
        self.store = store
        _section = State(initialValue: initialSection)
    }

    // MARK: Data

    private var primaryTracker: Tracker? {
        store.activeTrackers.first { $0.kind == .duration } ?? store.activeTrackers.first
    }

    private var dailyValues: [DailyValue] {
        guard let primaryTracker else { return [] }
        return store.dailyValues(for: primaryTracker.id, dayCount: 60)
    }

    private var longDailyValues: [DailyValue] {
        guard let primaryTracker else { return [] }
        return store.dailyValues(for: primaryTracker.id, dayCount: 112)
    }

    private var weeklyHistory: [ProgressSnapshot] {
        guard let primaryTracker else { return [] }
        return store.history(for: primaryTracker.id, periodCount: 14, cadence: .weekly)
    }

    /// Trackers that can honestly share one y-axis.
    ///
    /// Stacking or overlaying series with different units is one of the easiest
    /// ways to draw a lie: 8,000 steps stacked on 8 glasses of water renders the
    /// water as a hairline and says "water is negligible", which is not a fact
    /// about the data, it is a fact about the units. So the gallery groups by
    /// unit and demonstrates on the largest compatible group.
    private var comparableTrackers: [Tracker] {
        let grouped = Dictionary(grouping: store.activeTrackers) { $0.unit }
        let best = grouped
            .filter { $0.value.count >= 2 }
            .max { $0.value.count < $1.value.count }?
            .value
        return Array((best ?? store.activeTrackers).prefix(4))
    }

    private var multiSeries: [ChartSeries] {
        comparableTrackers.enumerated().map { index, tracker in
            ChartSeries.daily(
                store.dailyValues(for: tracker.id, dayCount: 21),
                name: tracker.title,
                colorIndex: index,
                colorHex: theme.identityColor(for: tracker).hexString,
                unit: tracker.unit
            )
        }
    }

    /// The unit the multi-series examples are drawn in, for their captions.
    /// The showcase tracker's colour, resolved through the theme so a monochrome
    /// identity mode reaches the single-series charts too.
    private var primaryColorHex: String? {
        primaryTracker.map { theme.identityColor(for: $0).hexString }
    }

    private var comparableUnit: String {
        let unit = comparableTrackers.first?.unit ?? ""
        return unit.isEmpty ? "the same unit" : unit
    }

    private var snapshots: [ProgressSnapshot] { store.currentProgressAll() }

    public var body: some View {
        VStack(spacing: 0) {
            sectionPicker

            ScrollView {
                LazyVStack(spacing: 18) {
                    switch section {
                    case .timeSeries: timeSeriesSection
                    case .goals: goalsSection
                    case .rings: ringsSection
                    case .calendars: calendarsSection
                    case .dimensional: dimensionalSection
                    case .widgets: widgetsSection
                    case .heroes: heroesSection
                    }
                }
                .padding()
            }
        }
        .background(theme.plane)
        .navigationTitle("Visual gallery")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingKind) { kind in
            TrackerPickerView(store: store, kind: kind) { tracker in
                store.addDashboardCard(DashboardCard(kind: kind, trackerID: tracker.id))
                addedKind = kind
            }
        }
        .overlay(alignment: .bottom) {
            if let addedKind {
                Label("\(addedKind.displayName) added to your dashboard", systemImage: "checkmark.circle.fill")
                    .font(theme.typography.labelEmphasis)
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, theme.spacing.lg)
                    .padding(.vertical, theme.spacing.sm)
                    .trackerControlSurface(shape: theme.radii.actionShape)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: addedKind) {
                        try? await Task.sleep(for: .seconds(2.5))
                        self.addedKind = nil
                    }
            }
        }
        .animation(theme.motion.snappyAnimation, value: addedKind)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Section.allCases) { option in
                    Button {
                        withAnimation(theme.motion.snappyAnimation) { section = option }
                    } label: {
                        Label(option.rawValue, systemImage: option.symbolName)
                            .font(theme.typography.subheadline.weight(.medium))
                            .foregroundStyle(
                                section == option ? theme.onAccent : theme.textSecondary
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(section == option ? theme.accent : theme.surface)
                            )
                            .overlay {
                                if section != option {
                                    Capsule().strokeBorder(theme.border, lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(theme.plane)
    }

    // MARK: Sections

    @ViewBuilder
    private var timeSeriesSection: some View {
        galleryCard(
            "Area chart",
            "Volume over time. The mass under the curve is the message.",
            addable: .areaChart
        ) {
            TrackerAreaChart(
                values: dailyValues,
                name: primaryTracker?.title ?? "Values",
                colorHex: primaryColorHex,
                unit: primaryTracker?.unit ?? "",
                goalLine: primaryTracker?.currentGoal?.target,
                height: 190
            )
        }

        galleryCard(
            "Stacked area",
            "Several trackers composed into one total, all measured in \(comparableUnit). Drag to inspect any day."
        ) {
            TrackerAreaChart(series: multiSeries, height: 200)
        }

        galleryCard(
            "Line chart with moving average",
            "The level, not the volume. The thick line is a 7-day average.",
            addable: .lineChart
        ) {
            TrackerLineChart(
                values: dailyValues,
                name: primaryTracker?.title ?? "Values",
                colorHex: primaryColorHex,
                unit: primaryTracker?.unit ?? "",
                goalLine: primaryTracker?.currentGoal?.target,
                movingAverageWindow: 7,
                height: 190
            )
        }

        galleryCard(
            "Multi-series line",
            "Comparison across one shared scale. Colors are fixed to each tracker, never reassigned."
        ) {
            TrackerLineChart(series: multiSeries, height: 200)
        }

        galleryCard(
            "Stacked bars",
            "Composition per day in \(comparableUnit), with a real 2pt gap between segments."
        ) {
            TrackerStackedBarChart(series: multiSeries, height: 200, showTotals: true)
        }

        galleryCard(
            "Grouped bars",
            "Side-by-side comparison. Capped at four series on purpose."
        ) {
            TrackerGroupedBarChart(
                series: multiSeries.map { series in
                    var trimmed = series
                    trimmed.points = Array(series.points.suffix(6))
                    return trimmed
                },
                height: 200
            )
        }

        galleryCard(
            "Sparklines",
            "Canvas-drawn, cheap enough for a list of fifty rows."
        ) {
            VStack(spacing: 14) {
                ForEach(Array(store.activeTrackers.prefix(4)), id: \.id) { tracker in
                    HStack(spacing: 12) {
                        Text(tracker.title)
                            .font(theme.typography.label)
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 92, alignment: .leading)
                            .lineLimit(1)
                        SparklineView(
                            dailyValues: store.dailyValues(for: tracker.id, dayCount: 30),
                            color: theme.identityColor(for: tracker),
                            style: .filledLine
                        )
                        .frame(height: 34)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var goalsSection: some View {
        galleryCard(
            "Period bars with stoplight",
            "Each period against the goal that was in force then. The dashed line steps when the target changed.",
            addable: .periodBars
        ) {
            TrackerPeriodBarChart(
                snapshots: weeklyHistory,
                seriesColorHex: primaryColorHex,
                height: 200
            )
        }

        galleryCard(
            "Bullet charts",
            "The densest honest way to show many goals at once. Tick is the target; the wash is the projection.",
            addable: .bullets
        ) {
            BulletChartList(trackers: store.activeTrackers, snapshots: snapshots)
        }

        galleryCard(
            "Stoplight rollup",
            "One bar, every goal. Icon and word carry the status, not just color.",
            addable: .stoplightRollup
        ) {
            StoplightSummaryBar(snapshots: snapshots)
        }

        galleryCard("Status badges", "Every status, at three sizes.") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach([StoplightBadge.Size.large, .medium, .small], id: \.self) { size in
                    FlowLayout(spacing: 8) {
                        ForEach(StoplightStatus.allCases, id: \.self) { status in
                            StoplightBadge(status: status, size: size)
                        }
                    }
                }
                HStack(spacing: 14) {
                    ForEach(StoplightStatus.allCases, id: \.self) { status in
                        StoplightDot(status: status, size: 14)
                    }
                }
            }
        }

        galleryCard(
            "Progress replay",
            "History drawing itself, with goal changes called out as they happen.",
            addable: .replay
        ) {
            ProgressReplayView(
                snapshots: weeklyHistory,
                colorHex: primaryColorHex,
                height: 190,
                autoPlays: false
            )
        }
    }

    @ViewBuilder
    private var ringsSection: some View {
        galleryCard("Activity rings", "Overshoot draws a second lap instead of capping.", addable: .rings) {
            ProgressRingsView(rings: ringData, size: 210) {
                VStack(spacing: -2) {
                    Text("\(snapshots.filter { $0.status == .green }.count)")
                        .font(theme.typography.displaySize(34))
                        .foregroundStyle(theme.textPrimary)
                    Text("met")
                        .font(theme.typography.micro)
                        .foregroundStyle(theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity)
        }

        galleryCard("Radial progress", "The compact ring, for rows and widgets.") {
            HStack(spacing: 20) {
                ForEach(Array(snapshots.prefix(4).enumerated()), id: \.offset) { index, snapshot in
                    RadialProgressView(
                        fraction: snapshot.fraction ?? 0,
                        color: theme.palette.series(index),
                        valueText: Formatters.percent(snapshot.clampedFraction),
                        size: 68
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }

        galleryCard(
            "Gauge",
            "Included because it's asked for. A bullet chart says the same in a fifth of the space."
        ) {
            HStack(spacing: 24) {
                if let snapshot = snapshots.first {
                    GaugeChartView(snapshot: snapshot, label: "Today", size: 160)
                }
                if snapshots.count > 1 {
                    GaugeChartView(snapshot: snapshots[1], label: "Also today", size: 160)
                }
            }
            .frame(maxWidth: .infinity)
        }

        galleryCard("Progress bars", "Bar, with the overflow pip when a goal is beaten.") {
            VStack(spacing: 12) {
                ForEach(Array(snapshots.prefix(5).enumerated()), id: \.offset) { index, snapshot in
                    MiniProgressBar(
                        fraction: snapshot.fraction ?? 0,
                        status: snapshot.status,
                        color: theme.palette.series(index),
                        height: 8
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var calendarsSection: some View {
        galleryCard(
            "Contribution heatmap",
            "One hue, light to dark. No-entry days are outlined, never the palest step.",
            addable: .heatmap
        ) {
            HeatmapCalendarView(
                values: longDailyValues,
                colorHex: primaryColorHex,
                unit: primaryTracker?.unit ?? ""
            )
        }

        galleryCard("Streak card", "The chain, the number, and the nudge.", addable: .streak) {
            StreakCard(
                streak: store.loginStreak(),
                days: store.streaks.activityFlags(days: store.loginDays.map(\.day), dayCount: 14),
                color: store.activeProfile.map { theme.identityColor(for: $0) }
            )
        }

        galleryCard("Streak badges", "Three sizes. Pulses when the streak is at risk.") {
            HStack(spacing: 28) {
                StreakBadge(streak: store.loginStreak(), size: .compact)
                StreakBadge(streak: store.loginStreak(), size: .regular)
                StreakBadge(streak: store.loginStreak(), size: .hero)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var dimensionalSection: some View {
        galleryCard(
            "Weekday × week",
            "Where rhythm hides. Native Chart3D on iOS 26, a hand-rolled projection below it. Drag to rotate either way.",
            addable: .rhythm3D
        ) {
            Tracker3DChart(
                data: .weekdayByWeek(values: longDailyValues, unit: primaryTracker?.unit ?? ""),
                height: 320
            )
        }

        galleryCard(
            "Series × time",
            "Several trackers in depth. Rotate to resolve what's hidden behind what."
        ) {
            Tracker3DChart(
                data: .seriesByTime(series: multiSeries),
                height: 320
            )
        }
    }

    @ViewBuilder
    private var widgetsSection: some View {
        if let snapshot = store.widgetSnapshot() {
            ForEach(TrackerWidgetSize.allCases, id: \.self) { size in
                TrackerCard(
                    title: "\(size.displayName) widget",
                    subtitle: widgetNote(for: size)
                ) {
                    HStack {
                        Spacer()
                        TrackerWidgetView(snapshot: snapshot, size: size)
                            .frame(width: size.previewSize.width, height: size.previewSize.height)
                            .background(theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(theme.border, lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                        Spacer()
                    }
                }
            }
        } else {
            ChartEmptyState(message: "No widget data for this profile yet")
        }
    }

    private func widgetNote(for size: TrackerWidgetSize) -> String {
        switch size {
        case .small: "One ring, one number. Readable at arm's length."
        case .medium: "Rings plus the three goals that need attention."
        case .large: "The full glance: streak chain, five goals, sparklines."
        }
    }

    @ViewBuilder
    private var heroesSection: some View {
        ForEach(HeroStyle.allCases, id: \.self) { style in
            VStack(alignment: .leading, spacing: 8) {
                Text(style.rawValue.capitalized)
                    .font(theme.typography.heading)
                    .foregroundStyle(theme.textPrimary)

                HeroSectionView(
                    style: style,
                    profile: store.activeProfile,
                    trackers: store.activeTrackers,
                    snapshots: snapshots,
                    loginStreak: store.loginStreak(),
                    streakDays: store.streaks.activityFlags(
                        days: store.loginDays.map(\.day), dayCount: 14
                    ),
                    headlineTracker: primaryTracker,
                    headlineValues: dailyValues
                )
            }
        }
    }

    // MARK: Helpers

    private var ringData: [RingData] {
        let byID = Dictionary(uniqueKeysWithValues: store.activeTrackers.map { ($0.id, $0) })
        return snapshots
            .filter { $0.goal != nil }
            .prefix(3)
            .compactMap { snapshot in
                byID[snapshot.trackerID].map { RingData.from(snapshot: snapshot, tracker: $0) }
            }
    }

    /// A gallery entry, with the means to put it on the dashboard.
    ///
    /// The gallery was a showroom with no way to take anything home — you could
    /// admire the consistency calendar and then had to come back here every time
    /// you wanted to look at it. `addable` is what makes it a catalogue.
    private func galleryCard<Content: View>(
        _ title: String,
        _ note: String,
        addable: DashboardCard.Kind? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        TrackerCard(title: title, subtitle: note) {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                content()

                if let addable {
                    addToDashboardButton(for: addable)
                }
            }
        }
    }

    @ViewBuilder
    private func addToDashboardButton(for kind: DashboardCard.Kind) -> some View {
        let alreadyOn = kind.isSingleton
            && store.dashboardLayout.contains { $0.kind == kind }

        Button {
            guard !alreadyOn else { return }
            if kind.needsTracker {
                pendingKind = kind
            } else {
                store.addDashboardCard(DashboardCard(kind: kind))
                addedKind = kind
            }
        } label: {
            Label(
                alreadyOn ? "On your dashboard" : "Add to dashboard",
                systemImage: alreadyOn ? "checkmark" : "plus"
            )
            .font(theme.typography.labelEmphasis)
            .foregroundStyle(alreadyOn ? theme.textMuted : theme.accent)
            .padding(.vertical, theme.spacing.xs)
            .frame(minHeight: theme.metrics.minimumTouchTarget)
        }
        .buttonStyle(.plain)
        .disabled(alreadyOn)
        .accessibilityIdentifier("gallery.add.\(kind.rawValue)")
    }
}

#Preview("Gallery") {
    let store = TrackerStore.preview()
    return NavigationStack {
        ChartGalleryView(store: store)
    }
}
