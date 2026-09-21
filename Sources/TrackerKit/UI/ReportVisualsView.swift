// iOS-only. See rule 17 in CLAUDE.md.
#if os(iOS)

import SwiftUI

// MARK: - ReportVisualsView

/// The charts a report carries, drawn from its filtered data.
///
/// Every chart here reads from the built ``CustomReport`` rather than the store,
/// which is the whole point: what you see is exactly the range, weekday filter
/// and habit selection the report says it is.
public struct ReportVisualsView: View {
    @Environment(\.trackerTheme) private var theme

    /// How the charts sit on the page.
    public enum Layout: Sendable, Hashable {
        /// One per row, full width. Right for a phone, where width is scarce and
        /// vertical scrolling is free.
        case stacked
        /// Two across. Right for paper, where the opposite is true — a page is
        /// wide and every new sheet costs something.
        case grid
    }

    private let report: CustomReport
    private let layout: Layout

    public init(report: CustomReport, layout: Layout = .stacked) {
        self.report = report
        self.layout = layout
    }

    /// Sized so four tiles fill a Letter page under the header.
    ///
    /// 792pt tall, less 36pt margins each side and roughly 90 for the header,
    /// leaves about 630 for two rows.
    private var tileHeight: CGFloat { layout == .grid ? 300 : 260 }
    private var chartHeight: CGFloat { layout == .grid ? 190 : 220 }

    public var body: some View {
        switch layout {
        case .stacked:
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                ForEach(report.chartTiles) { tile in
                    tileCard(tile)
                }
            }
        case .grid:
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: theme.spacing.md, alignment: .top),
                    GridItem(.flexible(), spacing: theme.spacing.md, alignment: .top),
                ],
                spacing: theme.spacing.md
            ) {
                ForEach(report.chartTiles) { tile in
                    tileCard(tile)
                        .frame(height: tileHeight)
                }
            }
        }
    }

    // MARK: A tile

    @ViewBuilder
    private func tileCard(_ tile: ReportChartTile) -> some View {
        TrackerCard(title: tile.title, subtitle: tile.subtitle) {
            chart(for: tile)
        }
    }

    @ViewBuilder
    private func chart(for tile: ReportChartTile) -> some View {
        if let tracker = report.tracker(tile.trackerID) {
            perTracker(tile.visual, tracker: tracker)
        } else {
            combined(tile.visual)
        }
    }

    @ViewBuilder
    private func combined(_ visual: ReportVisual) -> some View {
        switch visual {
        case .line:
            TrackerLineChart(series: report.chartSeries)
                .frame(height: chartHeight)

        case .rings:
            ProgressRingsView(rings: rings)
                .frame(height: chartHeight)

        case .bullets:
            VStack(spacing: theme.spacing.sm) {
                ForEach(report.trackers) { tracker in
                    BulletChartView(
                        title: tracker.title,
                        actual: tracker.total,
                        target: tracker.target,
                        unit: tracker.unit,
                        // An .atMost goal must draw its overshoot as a breach,
                        // never as a full bar reading like success.
                        direction: tracker.goal?.direction ?? .atLeast
                    )
                }
            }

        case .sparkline:
            VStack(spacing: theme.spacing.sm) {
                ForEach(report.trackers) { tracker in
                    HStack(spacing: theme.spacing.sm) {
                        Text(tracker.title)
                            .font(theme.typography.label)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .frame(width: 90, alignment: .leading)
                        SparklineView(
                            dailyValues: tracker.dailyValues,
                            color: theme.identityColor(hex: tracker.colorHex)
                        )
                        .frame(height: 24)
                        Text(tracker.totalText)
                            .font(theme.typography.label)
                            .foregroundStyle(theme.textPrimary)
                            .monospacedDigit()
                    }
                }
            }

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func perTracker(_ visual: ReportVisual, tracker: CustomReportTracker) -> some View {
        switch visual {
        case .area:
            TrackerAreaChart(
                values: tracker.dailyValues,
                name: tracker.title,
                colorHex: tracker.colorHex,
                unit: tracker.unit
            )
            .frame(height: chartHeight)
        case .bars:
            TrackerGroupedBarChart(series: [tracker.chartSeries(colorIndex: 0)])
                .frame(height: chartHeight)
        case .heatmap:
            HeatmapCalendarView(values: tracker.dailyValues, unit: tracker.unit)
        default:
            EmptyView()
        }
    }

    // MARK: Goal-derived input

    /// Rings need a target. A habit with no goal in the window is left out
    /// rather than drawn as a ring against nothing.
    private var rings: [RingData] {
        report.trackers.compactMap { tracker in
            guard let target = tracker.target, target > 0 else { return nil }
            let fraction = tracker.total / target
            return RingData(
                label: tracker.title,
                fraction: fraction,
                colorHex: tracker.colorHex,
                symbolName: tracker.symbolName,
                valueText: tracker.totalText,
                status: fraction >= 1 ? .green : (fraction >= 0.6 ? .yellow : .red),
                breachesLimit: tracker.goal?.direction == .atMost && fraction > 1
            )
        }
    }
}

#endif
