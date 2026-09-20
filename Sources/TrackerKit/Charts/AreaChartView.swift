import SwiftUI
import Charts

/// Area chart — magnitude over time, with the volume under the curve carrying
/// the weight.
///
/// Use it for cumulative or voluminous quantities (minutes, steps, pages). For a
/// value where the *level* matters more than the mass — a weight, a rating — use
/// ``TrackerLineChart``, which doesn't imply "amount piled up".
///
/// With more than one series the areas stack, so the top edge reads as the total
/// and each band reads as a contribution. That only means something when the
/// series share a unit — see the note on ``TrackerStackedBarChart``.
public struct TrackerAreaChart: View {
    @Environment(\.trackerTheme) private var theme
    @State private var selectedDate: Date?

    private let series: [ChartSeries]
    private let goalLine: Double?
    private let goalSteps: ChartSeries?
    private let height: CGFloat
    private let showAxes: Bool
    private let smoothed: Bool

    /// - Parameters:
    ///   - goalLine: a flat reference line at a single target.
    ///   - goalSteps: a *stepped* goal line built from goal history — use this
    ///     over `goalLine` whenever the target has changed, so the chart shows the
    ///     goalpost moving instead of pretending it never did.
    ///   - smoothed: draws a monotone curve. Off by default: smoothing invents
    ///     values between real points, which is fine for a trend impression and
    ///     wrong for anything read precisely.
    public init(
        series: [ChartSeries],
        goalLine: Double? = nil,
        goalSteps: ChartSeries? = nil,
        height: CGFloat? = nil,
        showAxes: Bool = true,
        smoothed: Bool = false
    ) {
        self.series = series
        self.goalLine = goalLine
        self.goalSteps = goalSteps
        self.height = height ?? 200
        self.showAxes = showAxes
        self.smoothed = smoothed
    }

    /// Convenience for the common single-tracker case.
    public init(
        values: [DailyValue],
        name: String,
        colorHex: String? = nil,
        unit: String = "",
        goalLine: Double? = nil,
        height: CGFloat? = nil
    ) {
        self.init(
            series: [ChartSeries.daily(values, name: name, colorHex: colorHex, unit: unit)],
            goalLine: goalLine,
            height: height
        )
    }

    private var isStacked: Bool { series.count > 1 }

    private var domain: ClosedRange<Double> {
        ChartScale.domain(
            values: isStacked ? [series.stackedPeak] : series.flatMap(\.values),
            includingTarget: goalLine ?? goalSteps?.peak
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if series.allSatisfy(\.isEmpty) {
                ChartEmptyState(message: "Nothing logged yet", symbolName: "chart.xyaxis.line")
                    .frame(height: height)
            } else {
                chart
                ChartLegend(series: series)
            }
        }
    }

    private var chart: some View {
        Chart {
            // Plotted run by run rather than point by point, so a day with
            // nothing logged leaves a gap instead of a dive to zero. A zero and
            // an absence are different claims.
            ForEach(series) { item in
                ForEach(Array(item.dataRuns.enumerated()), id: \.offset) { runIndex, run in
                    ForEach(run) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value(item.unit.isEmpty ? "Value" : item.unit, point.value),
                            // Series keyed by run so the fill breaks at a gap
                            // too; the stroke alone splitting left a filled
                            // region spanning days with nothing logged.
                            series: .value("Run", "\(item.name)#\(runIndex)"),
                            stacking: .standard
                        )
                        // Explicit colour rather than `foregroundStyle(by:)`.
                        // Combining `by:` with a per-run `series:` makes Charts
                        // build a plot group per run that carries no description,
                        // which the accessibility auditor reports as text nobody
                        // can reach. The legend below is drawn by this file
                        // anyway, so the implicit one bought nothing.
                        .foregroundStyle(item.color(in: theme.palette))
                        .interpolationMethod(smoothed ? .monotone : .linear)
                        .opacity(isStacked ? 0.85 : 1)
                        // Splitting a series into runs creates a plot group per
                        // run, and an undescribed group reads to the
                        // accessibility auditor as text nobody can reach.
                        // Describing the marks is the documented pattern, and it
                        // makes the chart navigable rather than merely legal.
                        .accessibilityLabel(Formatters.dayMonth(point.date))
                        .accessibilityValue(Formatters.value(point.value, unit: item.unit))
                    }
                }
            }

            // Top edge. On a single series this is the readable line over the
            // wash; on a stack it is the 2px separator that keeps bands distinct.
            ForEach(series) { item in
                ForEach(Array(item.dataRuns.enumerated()), id: \.offset) { runIndex, run in
                    ForEach(run) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value),
                            // The run index is part of the series identity, which
                            // is what actually breaks the stroke at a gap.
                            series: .value("Edge", "\(item.name)#\(runIndex)")
                        )
                        .foregroundStyle(item.color(in: theme.palette))
                        .lineStyle(StrokeStyle(lineWidth: theme.metrics.lineWidth, lineCap: .round))
                        .interpolationMethod(smoothed ? .monotone : .linear)
                        .opacity(isStacked ? 0 : 1)
                    }

                    // A run of one draws neither an area nor a stroke — two
                    // points are needed for both — so an isolated day would
                    // vanish entirely. Mark it.
                    if run.count == 1, let only = run.first, !isStacked {
                        PointMark(
                            x: .value("Date", only.date),
                            y: .value("Value", only.value)
                        )
                        .foregroundStyle(item.color(in: theme.palette))
                        .symbolSize(theme.metrics.markerSize * theme.metrics.markerSize)
                        // A bare mark is text on screen with nothing behind it
                        // for VoiceOver, which the accessibility auditor flags
                        // as unreachable. It is a data point; it can say so.
                        .accessibilityLabel(Formatters.dayMonth(only.date))
                        .accessibilityValue(
                            Formatters.value(only.value, unit: item.unit)
                        )
                    }
                }
            }

            if let goalSteps {
                ForEach(goalSteps.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Goal", point.value),
                        series: .value("Series", "__goal")
                    )
                    .foregroundStyle(theme.textMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.stepEnd)
                }
            } else if let goalLine {
                RuleMark(y: .value("Goal", goalLine))
                    .foregroundStyle(theme.textMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("Goal \(Formatters.compact(goalLine))")
                            .font(theme.typography.micro)
                            .foregroundStyle(theme.textMuted)
                    }
            }

            if let selectedDate, let nearest = nearestDate(to: selectedDate) {
                RuleMark(x: .value("Selected", nearest))
                    .foregroundStyle(theme.axis)
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
        .chartForegroundStyleScale(range: gradients)
        .chartLegend(.hidden)
        .chartYScale(domain: domain)
        .chartXSelection(value: $selectedDate)
        .trackerAxes(showX: showAxes, showY: showAxes)
        .frame(height: height)
    }

    /// One gradient per series, in palette order. Built as a range array so Swift
    /// Charts keeps color bound to the series *name*, not its draw order.
    private var gradients: [AnyShapeStyle] {
        series.map { item in
            let color = item.color(in: theme.palette)
            return AnyShapeStyle(
                LinearGradient(
                    colors: [color.opacity(isStacked ? 0.9 : 0.45), color.opacity(isStacked ? 0.65 : 0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private func nearestDate(to date: Date) -> Date? {
        let dates = series.allDates
        guard !dates.isEmpty else { return nil }
        return dates.min {
            abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date))
        }
    }

    private func tooltip(for date: Date) -> some View {
        let rows = series.compactMap { item -> ChartTooltip.Row? in
            guard let point = item.points.first(where: { $0.date == date }) else { return nil }
            return ChartTooltip.Row(
                label: item.name,
                value: Formatters.value(point.value, unit: item.unit),
                color: series.count > 1 ? item.color(in: theme.palette) : nil
            )
        }
        return ChartTooltip(title: Formatters.friendlyDay(date), rows: rows)
    }
}

#Preview("Area — single series") {
    let sample = SampleData.previewTracker()
    let engine = ProgressEngine()
    let values = engine.dailyValues(tracker: sample.tracker, entries: sample.entries, dayCount: 30)

    return TrackerCard(title: "Focus Time", subtitle: "Last 30 days") {
        TrackerAreaChart(
            values: values,
            name: "Focus",
            colorHex: sample.tracker.colorHex,
            unit: "min",
            goalLine: 60
        )
    }
    .padding()
}

#Preview("Area — stacked") {
    let samples = SampleData.previewSeries(count: 3)
    let engine = ProgressEngine()
    let series = samples.enumerated().map { index, sample in
        ChartSeries.daily(
            engine.dailyValues(tracker: sample.tracker, entries: sample.entries, dayCount: 21),
            name: sample.tracker.title,
            colorIndex: index
        )
    }

    return TrackerCard(title: "All activity", subtitle: "Stacked, last 21 days") {
        TrackerAreaChart(series: series)
    }
    .padding()
}
