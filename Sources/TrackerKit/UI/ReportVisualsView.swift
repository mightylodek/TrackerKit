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

    private let report: CustomReport
    /// Charts render at a fixed height on a PDF page and a flexible one on screen.
    private let isPaged: Bool

    public init(report: CustomReport, isPaged: Bool = false) {
        self.report = report
        self.isPaged = isPaged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
            ForEach(report.definition.visuals, id: \.self) { visual in
                visualBlock(visual)
            }
        }
    }

    @ViewBuilder
    private func visualBlock(_ visual: ReportVisual) -> some View {
        TrackerCard(title: visual.displayName, subtitle: caption(for: visual)) {
            if visual.combinesTrackers {
                combined(visual)
            } else {
                VStack(alignment: .leading, spacing: theme.spacing.lg) {
                    ForEach(report.trackers) { tracker in
                        perTracker(visual, tracker: tracker)
                    }
                }
            }
        }
    }

    /// Says out loud when a combined chart is showing mixed units, rather than
    /// letting one axis quietly imply they're comparable.
    private func caption(for visual: ReportVisual) -> String? {
        guard visual.combinesTrackers, !report.sharesOneUnit else { return nil }
        return "Different units (\(report.unitSummary)) — compare shapes, not heights."
    }

    private var chartHeight: CGFloat { isPaged ? 180 : 220 }

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
            VStack(spacing: theme.spacing.md) {
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
                    HStack(spacing: theme.spacing.md) {
                        Text(tracker.title)
                            .font(theme.typography.label)
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 110, alignment: .leading)
                        SparklineView(
                            dailyValues: tracker.dailyValues,
                            color: theme.identityColor(hex: tracker.colorHex)
                        )
                        .frame(height: 28)
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
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(tracker.title)
                .font(theme.typography.label)
                .foregroundStyle(theme.textSecondary)

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
