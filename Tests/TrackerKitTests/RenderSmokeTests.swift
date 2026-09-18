import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import TrackerKit

/// Forces every public visual through a real render pass.
///
/// A SwiftUI view that compiles can still trap at runtime — an empty array
/// indexed, a `Chart` given a degenerate domain, a layout that divides by a zero
/// width. `ImageRenderer` runs the actual body and layout, so these catch the
/// class of bug that only shows up when someone opens the screen.
@MainActor
struct RenderSmokeTests {

    // MARK: Fixtures

    private static func makeStore() -> TrackerStore {
        let store = TrackerStore.preview()
        return store
    }

    private func render(_ view: some View, size: CGSize = CGSize(width: 390, height: 700)) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width).trackerTheme(.standard))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }

    // MARK: Charts with data

    @Test("Every time-series chart renders with real data")
    func timeSeriesChartsRender() {
        let store = Self.makeStore()
        let tracker = store.activeTrackers[0]
        let daily = store.dailyValues(for: tracker.id, dayCount: 45)
        let history = store.history(for: tracker.id, periodCount: 12, cadence: .weekly)
        let series = store.activeTrackers.prefix(3).enumerated().map { index, item in
            ChartSeries.daily(
                store.dailyValues(for: item.id, dayCount: 21),
                name: item.title,
                colorIndex: index
            )
        }

        #expect(render(TrackerAreaChart(values: daily, name: "Area", unit: "min")) != nil)
        #expect(render(TrackerAreaChart(series: series)) != nil)
        #expect(render(TrackerLineChart(values: daily, name: "Line", movingAverageWindow: 7)) != nil)
        #expect(render(TrackerLineChart(series: series, showPoints: true, showTrendLine: true)) != nil)
        #expect(render(TrackerStackedBarChart(series: series)) != nil)
        #expect(render(TrackerGroupedBarChart(series: series)) != nil)
        #expect(render(TrackerPeriodBarChart(snapshots: history)) != nil)
        #expect(render(SparklineView(dailyValues: daily, color: .blue).frame(height: 40)) != nil)
        #expect(render(SparklineView(snapshots: history, color: .blue).frame(height: 40)) != nil)
    }

    @Test("Goal and status visuals render")
    func goalVisualsRender() {
        let store = Self.makeStore()
        let snapshots = store.currentProgressAll()

        #expect(render(BulletChartView(snapshot: snapshots[0], title: "Bullet", projected: 20)) != nil)
        #expect(render(BulletChartList(trackers: store.activeTrackers, snapshots: snapshots)) != nil)
        #expect(render(StoplightSummaryBar(snapshots: snapshots)) != nil)
        #expect(render(GaugeChartView(snapshot: snapshots[0], label: "Gauge")) != nil)
        #expect(render(MiniProgressBar(fraction: 1.4, status: .green)) != nil)

        for status in StoplightStatus.allCases {
            #expect(render(StoplightBadge(status: status)) != nil)
            #expect(render(StoplightDot(status: status)) != nil)
        }
    }

    @Test("Rings render, including overshoot past a full lap")
    func ringsRender() {
        let palette = ChartPalette.standard
        let rings = [
            RingData(label: "Over", fraction: 2.4, colorHex: palette.seriesHex(0)),
            RingData(label: "Exact", fraction: 1.0, colorHex: palette.seriesHex(1)),
            RingData(label: "Under", fraction: 0.3, colorHex: palette.seriesHex(2)),
            RingData(label: "Zero", fraction: 0, colorHex: palette.seriesHex(3))
        ]

        #expect(render(ProgressRingsView(rings: rings, size: 200)) != nil)
        #expect(render(ProgressRingsView(rings: rings, size: 200) { Text("42") }) != nil)
        for ring in rings {
            #expect(render(ProgressRing(ring: ring).frame(width: 90, height: 90)) != nil)
        }
        #expect(render(RadialProgressView(fraction: 0.66, color: .blue, valueText: "66%")) != nil)
    }

    @Test("Calendars, streaks and the 3-D field render")
    func calendarsAndDimensionalRender() {
        let store = Self.makeStore()
        let tracker = store.activeTrackers[0]
        let daily = store.dailyValues(for: tracker.id, dayCount: 112)
        let streak = store.loginStreak()
        let flags = store.streaks.activityFlags(days: store.loginDays.map(\.day), dayCount: 14)

        #expect(render(HeatmapCalendarView(values: daily, unit: "min")) != nil)
        #expect(render(StreakCalendarStrip(days: flags, color: .orange)) != nil)
        #expect(render(StreakCard(streak: streak, days: flags)) != nil)
        for size in [StreakBadge.Size.compact, .regular, .hero] {
            #expect(render(StreakBadge(streak: streak, size: size)) != nil)
        }
        #expect(render(Tracker3DChart(values: daily, unit: "min", height: 300)) != nil)
    }

    @Test("Widgets render at all three sizes")
    func widgetsRender() {
        let store = Self.makeStore()
        let snapshot = store.widgetSnapshot() ?? .placeholder

        for size in TrackerWidgetSize.allCases {
            let image = render(
                TrackerWidgetView(snapshot: snapshot, size: size),
                size: size.previewSize
            )
            #expect(image != nil, "\(size.displayName) widget failed to render")
        }
        #expect(render(TrackerWidgetView(snapshot: .placeholder, size: .large)) != nil)
    }

    @Test("Every hero style renders")
    func heroesRender() {
        let store = Self.makeStore()
        let tracker = store.activeTrackers[0]

        for style in HeroStyle.allCases {
            let view = HeroSectionView(
                style: style,
                profile: store.activeProfile,
                trackers: store.activeTrackers,
                snapshots: store.currentProgressAll(),
                loginStreak: store.loginStreak(),
                streakDays: store.streaks.activityFlags(
                    days: store.loginDays.map(\.day), dayCount: 14
                ),
                headlineTracker: tracker,
                headlineValues: store.dailyValues(for: tracker.id, dayCount: 30)
            )
            #expect(render(view) != nil, "\(style.rawValue) hero failed to render")
        }
    }

    @Test("Report pages render to PDF")
    func reportRenders() {
        let store = Self.makeStore()
        guard let report = store.buildReport(lookbackDays: 7) else {
            Issue.record("No report built")
            return
        }

        let pages = ReportDocumentView.pageCount(for: report)
        #expect(pages >= 1)
        #expect(render(ReportDocumentView(report: report), size: ReportDocumentView.pageSize) != nil)

        let pdf = PDFReportRenderer().render(report)
        #expect(pdf.count > 1000, "PDF looks empty at \(pdf.count) bytes")
        // A real PDF starts with %PDF-
        #expect(pdf.prefix(5) == Data("%PDF-".utf8))
    }

    // MARK: Degenerate input

    @Test("Charts survive empty and single-point data")
    func emptyDataRenders() {
        let empty: [DailyValue] = []
        let single = [DailyValue(date: .now, value: 5, entryCount: 1)]
        let flat = (0..<10).map {
            DailyValue(
                date: Date.now.addingTimeInterval(Double($0) * 86_400),
                value: 0,
                entryCount: 0
            )
        }

        for values in [empty, single, flat] {
            #expect(render(TrackerAreaChart(values: values, name: "X")) != nil)
            #expect(render(TrackerLineChart(values: values, name: "X")) != nil)
            #expect(render(HeatmapCalendarView(values: values)) != nil)
            #expect(render(SparklineView(dailyValues: values, color: .blue).frame(height: 30)) != nil)
            #expect(render(Tracker3DChart(values: values, height: 200)) != nil)
        }

        #expect(render(TrackerStackedBarChart(series: [])) != nil)
        #expect(render(TrackerPeriodBarChart(snapshots: [])) != nil)
        #expect(render(BulletChartView(actual: 0, target: nil)) != nil)
        #expect(render(BulletChartView(actual: 5, target: 0)) != nil)
        #expect(render(ProgressRingsView(rings: [])) != nil)
        #expect(render(StoplightSummaryBar(snapshots: [])) != nil)
        #expect(render(GaugeChartView(value: 0, target: 0)) != nil)
    }

    @Test("Screens render for a profile with nothing in it")
    func emptyProfileRenders() throws {
        let container = try TrackerKitSchema.container(inMemory: true)
        let store = TrackerStore(context: ModelContext(container))
        let profile = store.addProfile(name: "Empty")
        store.activeProfileID = profile.id
        let session = ProfileSession(store: store)

        #expect(render(TrackerDashboardView(store: store, session: session)) != nil)
        #expect(render(ChartGalleryView(store: store)) != nil)
        #expect(render(TrackerKitSettingsView(store: store, session: session)) != nil)
    }
}
