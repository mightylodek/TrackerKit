// iOS-only. See rule 17 in CLAUDE.md.
#if os(iOS)

import SwiftUI

// MARK: - ReportChartTileView

/// One chart in its card.
///
/// The single place a report chart is built, so the screen and the printed page
/// draw the same thing rather than two implementations that drift apart.
public struct ReportChartTileView: View {
    @Environment(\.trackerTheme) private var theme

    private let report: CustomReport
    private let tile: ReportChartTile
    private let chartHeight: CGFloat

    public init(report: CustomReport, tile: ReportChartTile, chartHeight: CGFloat) {
        self.report = report
        self.tile = tile
        self.chartHeight = chartHeight
    }

    public var body: some View {
        TrackerCard(title: tile.title, subtitle: tile.subtitle) {
            Group {
                if let tracker = report.tracker(tile.trackerID) {
                    perTracker(tile.visual, tracker: tracker)
                } else {
                    combined(tile.visual)
                }
            }
            // The topmost y-axis label sits flush with the plot edge and was
            // colliding with the card's subtitle above it.
            .padding(.top, theme.spacing.xs)
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
                            .frame(width: 80, alignment: .leading)
                        SparklineView(
                            dailyValues: tracker.dailyValues,
                            color: theme.identityColor(hex: tracker.colorHex)
                        )
                        .frame(height: 22)
                        Text(tracker.totalText)
                            .font(theme.typography.label)
                            .foregroundStyle(theme.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
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

// MARK: - ReportVisualsView

/// A report's charts, drawn from its filtered data.
///
/// Every chart reads from the built ``CustomReport`` rather than the store,
/// which is the point: what you see is exactly the range, weekday filter and
/// habit selection the report says it is.
public struct ReportVisualsView: View {
    @Environment(\.trackerTheme) private var theme

    /// How the charts sit.
    public enum Layout: Sendable, Hashable {
        /// One per row, full width. Right for a phone, where width is scarce and
        /// vertical scrolling is free.
        case stacked
        /// Two across. Right for paper, where the opposite is true.
        case grid
    }

    private let report: CustomReport
    private let layout: Layout

    public init(report: CustomReport, layout: Layout = .stacked) {
        self.report = report
        self.layout = layout
    }

    private var tileHeight: CGFloat { 300 }
    private var chartHeight: CGFloat { layout == .grid ? 190 : 220 }

    public var body: some View {
        switch layout {
        case .stacked:
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                ForEach(report.chartTiles) { tile in
                    ReportChartTileView(report: report, tile: tile, chartHeight: chartHeight)
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
                    ReportChartTileView(report: report, tile: tile, chartHeight: chartHeight)
                        .frame(height: tileHeight)
                }
            }
        }
    }
}

#endif
