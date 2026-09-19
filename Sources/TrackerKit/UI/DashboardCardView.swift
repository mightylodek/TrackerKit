// iOS-only. These screens assume a phone or tablet canvas: navigation stacks,
// menus, segmented pickers, keyboard types and edit modes that either don't
// exist on watchOS or are the wrong interaction at 45mm.
//
// A watch app gets its own UI built on the same portable core (Model, Engine,
// Store, Theme, Security), not these views shrunk down. See docs/WATCH.md.
#if os(iOS)

import SwiftUI

/// Renders one ``DashboardCard``.
///
/// Every visual here already existed in the gallery — this is the adapter that
/// lets the same view be placed on the dashboard, which is the whole point of
/// making the gallery more than a showroom.
public struct DashboardCardView: View {
    @Environment(\.trackerTheme) private var theme

    private let card: DashboardCard
    private let store: TrackerStore
    private let session: ProfileSession
    private let showsHeroStyleSwitcher: Bool
    private let onLog: (Tracker) -> Void
    private let onDetailedLog: (Tracker) -> Void

    public init(
        card: DashboardCard,
        store: TrackerStore,
        session: ProfileSession,
        showsHeroStyleSwitcher: Bool = false,
        onLog: @escaping (Tracker) -> Void,
        onDetailedLog: @escaping (Tracker) -> Void
    ) {
        self.card = card
        self.store = store
        self.session = session
        self.showsHeroStyleSwitcher = showsHeroStyleSwitcher
        self.onLog = onLog
        self.onDetailedLog = onDetailedLog
    }

    private var tracker: Tracker? {
        card.trackerID.flatMap { store.tracker($0) }
    }

    private var snapshots: [ProgressSnapshot] { store.currentProgressAll() }

    public var body: some View {
        switch card.kind {
        case .hero:
            HeroCardSection(
                style: card.heroStyle ?? .rings,
                store: store,
                showsSwitcher: showsHeroStyleSwitcher
            )

        case .stoplightRollup:
            TrackerCard(title: "Where everything stands") {
                StoplightSummaryBar(snapshots: snapshots)
            }

        case .trackerList:
            TrackerListSection(
                store: store,
                session: session,
                onLog: onLog,
                onDetailedLog: onDetailedLog
            )

        case .heatmap:
            trackerCard { tracker in
                HeatmapCalendarView(
                    values: store.dailyValues(for: tracker.id, dayCount: card.dayCount),
                    colorHex: theme.identityColor(for: tracker).hexString,
                    unit: tracker.unit
                )
            }

        case .periodBars:
            trackerCard { tracker in
                TrackerPeriodBarChart(
                    snapshots: store.history(for: tracker.id, periodCount: 14),
                    seriesColorHex: theme.identityColor(for: tracker).hexString,
                    height: 190
                )
            }

        case .areaChart:
            trackerCard { tracker in
                TrackerAreaChart(
                    values: store.dailyValues(for: tracker.id, dayCount: min(card.dayCount, 60)),
                    name: tracker.title,
                    colorHex: theme.identityColor(for: tracker).hexString,
                    unit: tracker.unit,
                    goalLine: tracker.currentGoal?.target,
                    height: 180
                )
            }

        case .lineChart:
            trackerCard { tracker in
                TrackerLineChart(
                    values: store.dailyValues(for: tracker.id, dayCount: min(card.dayCount, 60)),
                    name: tracker.title,
                    colorHex: theme.identityColor(for: tracker).hexString,
                    unit: tracker.unit,
                    goalLine: tracker.currentGoal?.target,
                    movingAverageWindow: 7,
                    height: 180
                )
            }

        case .rings:
            TrackerCard(title: "Today") {
                ProgressRingsView(rings: ringData, size: 190)
                    .frame(maxWidth: .infinity)
            }

        case .bullets:
            TrackerCard(title: "All goals") {
                BulletChartList(trackers: store.activeTrackers, snapshots: snapshots)
            }

        case .streak:
            StreakCard(
                streak: store.loginStreak(),
                days: store.streaks.activityFlags(days: store.loginDays.map(\.day), dayCount: 14),
                color: store.activeProfile.map { theme.identityColor(for: $0) }
            )

        case .replay:
            trackerCard { tracker in
                ProgressReplayView(
                    snapshots: store.history(for: tracker.id, periodCount: 14),
                    title: tracker.title,
                    colorHex: theme.identityColor(for: tracker).hexString,
                    height: 180,
                    autoPlays: false
                )
            }

        case .rhythm3D:
            trackerCard { tracker in
                Tracker3DChart(
                    data: .weekdayByWeek(
                        values: store.dailyValues(for: tracker.id, dayCount: card.dayCount),
                        unit: tracker.unit
                    ),
                    height: 280
                )
            }
        }
    }

    /// Wraps a tracker-scoped visual, naming the tracker so a dashboard with
    /// several of these doesn't become a wall of unlabelled charts.
    @ViewBuilder
    private func trackerCard<Content: View>(
        @ViewBuilder content: (Tracker) -> Content
    ) -> some View {
        if let tracker {
            TrackerCard(title: tracker.title, subtitle: card.kind.displayName) {
                content(tracker)
            }
        }
    }

    private var ringData: [RingData] {
        let byID = Dictionary(uniqueKeysWithValues: store.activeTrackers.map { ($0.id, $0) })
        return snapshots
            .filter { $0.goal != nil }
            .prefix(3)
            .compactMap { snapshot in
                byID[snapshot.trackerID].map {
                    RingData.from(snapshot: snapshot, tracker: $0, color: theme.identityColor(for: $0))
                }
            }
    }
}

#endif
