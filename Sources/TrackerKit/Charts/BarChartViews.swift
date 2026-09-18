import SwiftUI
import Charts

// MARK: - TrackerStackedBarChart

/// Stacked bars — composition over time. Each band is a contribution; the full
/// bar is the total.
///
/// **Only stack series that share a unit.** A stack asserts that its bands add up
/// to something meaningful. Stacking 8,000 steps on 8 glasses of water produces a
/// total that means nothing and renders the water as a hairline — which reads as
/// "water is negligible" when it actually says "these units are different". Two
/// scales want two charts.
///
/// A real 2pt gap is punched between segments so the bands read as separate marks
/// rather than one blurred column. Swift Charts has no inter-segment spacing, so
/// the stack is computed by hand and the gap is converted from points into data
/// units using the chart's own height and domain.
public struct TrackerStackedBarChart: View {
    @Environment(\.trackerTheme) private var theme
    @State private var selectedDate: Date?

    private let series: [ChartSeries]
    private let height: CGFloat
    private let showAxes: Bool
    private let showTotals: Bool

    public init(
        series: [ChartSeries],
        height: CGFloat? = nil,
        showAxes: Bool = true,
        showTotals: Bool = false
    ) {
        // Eight identity colors is the ceiling; past that, fold the tail into "Other".
        self.series = series.capped(at: 8)
        self.height = height ?? 220
        self.showAxes = showAxes
        self.showTotals = showTotals
    }

    private var dates: [Date] { series.allDates }
    private var peak: Double { series.stackedPeak }

    private var domain: ClosedRange<Double> {
        ChartScale.domain(values: [peak])
    }

    /// 2pt expressed in data units, so the visual gap is constant regardless of
    /// how tall the values are.
    private var gapInValueUnits: Double {
        let span = domain.upperBound - domain.lowerBound
        guard height > 0, span > 0 else { return 0 }
        return (theme.metrics.surfaceGap / height) * span
    }

    /// Precomputed segments with the gap already subtracted.
    private var segments: [StackSegment] {
        var result: [StackSegment] = []
        let gap = gapInValueUnits

        for date in dates {
            var cursor = 0.0
            for item in series {
                let value = item.points.first { $0.date == date }?.value ?? 0
                guard value > 0 else { continue }

                let isFirst = cursor == 0
                let start = cursor + (isFirst ? 0 : gap / 2)
                let end = cursor + value - gap / 2

                // A segment thinner than the gap would invert; draw it hairline instead.
                let safeEnd = max(end, start + gap * 0.25)

                result.append(
                    StackSegment(
                        date: date,
                        seriesID: item.id,
                        seriesName: item.name,
                        start: start,
                        end: safeEnd,
                        value: value,
                        color: item.color(in: theme.palette)
                    )
                )
                cursor += value
            }
        }
        return result
    }

    private struct StackSegment: Identifiable, Hashable {
        let date: Date
        let seriesID: UUID
        let seriesName: String
        let start: Double
        let end: Double
        let value: Double
        let color: Color

        var id: String { "\(date.timeIntervalSince1970)-\(seriesID.uuidString)" }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if series.allSatisfy(\.isEmpty) {
                ChartEmptyState(message: "Nothing to stack yet", symbolName: "chart.bar.fill")
                    .frame(height: height)
            } else {
                chart
                ChartLegend(series: series, showValues: showTotals)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(segments) { segment in
                BarMark(
                    x: .value("Date", segment.date, unit: .day),
                    yStart: .value("Start", segment.start),
                    yEnd: .value("End", segment.end),
                    width: .ratio(0.7)
                )
                .foregroundStyle(segment.color)
                .cornerRadius(theme.metrics.markCornerRadius * 0.5)
            }

            if let selectedDate, let nearest = nearestDate(to: selectedDate) {
                RuleMark(x: .value("Selected", nearest))
                    .foregroundStyle(theme.axis.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        tooltip(for: nearest)
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXSelection(value: $selectedDate)
        .trackerAxes(showX: showAxes, showY: showAxes)
        .frame(height: height)
    }

    private func nearestDate(to date: Date) -> Date? {
        dates.min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }
    }

    private func tooltip(for date: Date) -> some View {
        var rows = series.compactMap { item -> ChartTooltip.Row? in
            guard let point = item.points.first(where: { $0.date == date }), point.value > 0 else {
                return nil
            }
            return ChartTooltip.Row(
                label: item.name,
                value: Formatters.value(point.value, unit: item.unit),
                color: item.color(in: theme.palette)
            )
        }
        let total = series.reduce(0.0) { sum, item in
            sum + (item.points.first { $0.date == date }?.value ?? 0)
        }
        rows.append(ChartTooltip.Row(label: "Total", value: Formatters.compact(total)))
        return ChartTooltip(title: Formatters.friendlyDay(date), rows: rows)
    }
}

// MARK: - TrackerPeriodBarChart

/// Bars per period, colored by whether that period's goal was met.
///
/// This is the "did I hit it?" chart. Status is carried by color **and** by the
/// dashed goal line the bars sit against, so the pass/fail reading survives
/// grayscale and colorblindness.
public struct TrackerPeriodBarChart: View {
    @Environment(\.trackerTheme) private var theme
    @State private var selectedDate: Date?

    private let snapshots: [ProgressSnapshot]
    private let colorByStatus: Bool
    private let seriesColorHex: String?
    private let height: CGFloat
    private let showAxes: Bool

    /// - Parameter colorByStatus: when off, every bar uses the tracker's own
    ///   color and only the goal line communicates pass/fail. Turn it off when the
    ///   chart sits next to other charts whose colors mean identity — a green bar
    ///   meaning "met" beside a green bar meaning "reading" is a collision.
    public init(
        snapshots: [ProgressSnapshot],
        colorByStatus: Bool = true,
        seriesColorHex: String? = nil,
        height: CGFloat? = nil,
        showAxes: Bool = true
    ) {
        self.snapshots = snapshots
        self.colorByStatus = colorByStatus
        self.seriesColorHex = seriesColorHex
        self.height = height ?? 200
        self.showAxes = showAxes
    }

    private var domain: ClosedRange<Double> {
        ChartScale.domain(
            values: snapshots.map(\.actual),
            includingTarget: snapshots.compactMap(\.target).max()
        )
    }

    private var hasGoals: Bool { snapshots.contains { $0.target != nil } }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshots.isEmpty {
                ChartEmptyState(symbolName: "chart.bar.fill").frame(height: height)
            } else {
                chart
                if colorByStatus && hasGoals {
                    statusKey
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(snapshots) { snapshot in
                BarMark(
                    x: .value("Period", snapshot.period.start, unit: barUnit),
                    y: .value("Value", snapshot.actual),
                    width: .ratio(0.62)
                )
                .foregroundStyle(color(for: snapshot))
                .cornerRadius(theme.metrics.markCornerRadius)
                .opacity(snapshot.entryCount == 0 ? 0.35 : 1)
            }

            // Stepped goal line, drawn from each period's own governing goal.
            ForEach(snapshots.filter { $0.target != nil }) { snapshot in
                LineMark(
                    x: .value("Period", snapshot.period.start, unit: barUnit),
                    y: .value("Goal", snapshot.target ?? 0),
                    series: .value("Series", "__goal")
                )
                .foregroundStyle(theme.textSecondary)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .interpolationMethod(.stepCenter)
            }

            if let selectedDate, let nearest = nearestSnapshot(to: selectedDate) {
                RuleMark(x: .value("Selected", nearest.period.start, unit: barUnit))
                    .foregroundStyle(theme.axis.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        tooltip(for: nearest)
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXSelection(value: $selectedDate)
        .trackerAxes(showX: showAxes, showY: showAxes)
        .frame(height: height)
    }

    private var barUnit: Calendar.Component {
        snapshots.first?.period.cadence.calendarComponent ?? .day
    }

    private func color(for snapshot: ProgressSnapshot) -> Color {
        guard colorByStatus, snapshot.goal != nil else {
            return seriesColorHex.map { Color(hex: $0) } ?? theme.accent
        }
        return theme.statusColor(snapshot.status)
    }

    private func nearestSnapshot(to date: Date) -> ProgressSnapshot? {
        snapshots.min {
            abs($0.period.start.timeIntervalSince(date)) < abs($1.period.start.timeIntervalSince(date))
        }
    }

    private func tooltip(for snapshot: ProgressSnapshot) -> some View {
        var rows = [
            ChartTooltip.Row(
                label: "Actual",
                value: Formatters.value(snapshot.actual, unit: snapshot.unit)
            )
        ]
        if let target = snapshot.target {
            rows.append(
                ChartTooltip.Row(label: "Goal", value: Formatters.value(target, unit: snapshot.unit))
            )
            rows.append(
                ChartTooltip.Row(
                    label: snapshot.status.displayName,
                    value: Formatters.percent(snapshot.clampedFraction),
                    color: theme.statusColor(snapshot.status)
                )
            )
        }
        return ChartTooltip(title: snapshot.period.label(), rows: rows)
    }

    /// Status legend. Icon plus word — the color never carries it alone.
    private var statusKey: some View {
        FlowLayout(spacing: 12) {
            ForEach([StoplightStatus.green, .yellow, .red], id: \.self) { status in
                HStack(spacing: 5) {
                    Image(systemName: status.symbolName)
                        .font(theme.typography.micro)
                        .foregroundStyle(theme.statusColor(status))
                    Text(status.displayName)
                        .font(theme.typography.label)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }
}

// MARK: - TrackerGroupedBarChart

/// Side-by-side bars — comparing a handful of series across a few periods.
///
/// Keep it to three or four series: grouped bars get unreadable fast, and past
/// that a small-multiple grid says the same thing better.
public struct TrackerGroupedBarChart: View {
    @Environment(\.trackerTheme) private var theme

    private let series: [ChartSeries]
    private let height: CGFloat

    public init(series: [ChartSeries], height: CGFloat? = nil) {
        self.series = series.capped(at: 4)
        self.height = height ?? 220
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if series.allSatisfy(\.isEmpty) {
                ChartEmptyState(symbolName: "chart.bar.xaxis").frame(height: height)
            } else {
                Chart {
                    ForEach(series) { item in
                        ForEach(item.points) { point in
                            BarMark(
                                x: .value("Date", point.label ?? Formatters.dayMonth(point.date)),
                                y: .value("Value", point.value),
                                width: .ratio(0.85)
                            )
                            .foregroundStyle(item.color(in: theme.palette))
                            .position(by: .value("Series", item.name))
                            .cornerRadius(theme.metrics.markCornerRadius * 0.6)
                        }
                    }
                }
                .chartLegend(.hidden)
                .trackerAxes()
                .frame(height: height)

                ChartLegend(series: series)
            }
        }
    }
}

#Preview("Stacked bars") {
    let samples = SampleData.previewSeries(count: 4)
    let engine = ProgressEngine()
    let series = samples.enumerated().map { index, sample in
        ChartSeries.daily(
            engine.dailyValues(tracker: sample.tracker, entries: sample.entries, dayCount: 14),
            name: sample.tracker.title,
            colorIndex: index
        )
    }

    return TrackerCard(title: "Where the time went", subtitle: "Last 14 days") {
        TrackerStackedBarChart(series: series, showTotals: true)
    }
    .padding()
}

#Preview("Period bars with stoplight") {
    let sample = SampleData.previewTracker(cadence: .weekly, target: 300)
    let history = ProgressEngine().history(
        tracker: sample.tracker, entries: sample.entries, periodCount: 10, cadence: .weekly
    )

    return TrackerCard(title: "Weekly focus", subtitle: "Against the goal in force each week") {
        TrackerPeriodBarChart(snapshots: history)
    }
    .padding()
}
