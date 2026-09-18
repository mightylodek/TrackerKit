import SwiftUI
import Charts

/// Line chart — the *level* of a value over time, and how several levels compare.
///
/// Lines do not stack and do not imply volume, which makes this the right form
/// for ratings, weights, paces and anything else where the number itself is the
/// point. It can overlay a moving average and a stepped goal line built from goal
/// history.
public struct TrackerLineChart: View {
    @Environment(\.trackerTheme) private var theme
    @State private var selectedDate: Date?

    private let series: [ChartSeries]
    private let goalLine: Double?
    private let goalSteps: ChartSeries?
    private let movingAverageWindow: Int?
    private let showPoints: Bool
    private let showTrendLine: Bool
    private let height: CGFloat
    private let showAxes: Bool
    private let anchorAtZero: Bool

    /// - Parameters:
    ///   - movingAverageWindow: draws a smoothed companion line over `n` points.
    ///     Good for noisy daily data where the day-to-day is not the story.
    ///   - showTrendLine: overlays a least-squares fit. Only meaningful on a
    ///     single series — two fitted lines on one chart is noise.
    ///   - anchorAtZero: lines are the one form where a non-zero baseline is
    ///     legitimate (a weight chart from 0 is unreadable). Defaults to `false`.
    public init(
        series: [ChartSeries],
        goalLine: Double? = nil,
        goalSteps: ChartSeries? = nil,
        movingAverageWindow: Int? = nil,
        showPoints: Bool = false,
        showTrendLine: Bool = false,
        height: CGFloat? = nil,
        showAxes: Bool = true,
        anchorAtZero: Bool = false
    ) {
        self.series = series
        self.goalLine = goalLine
        self.goalSteps = goalSteps
        self.movingAverageWindow = movingAverageWindow
        self.showPoints = showPoints
        self.showTrendLine = showTrendLine
        self.height = height ?? 200
        self.showAxes = showAxes
        self.anchorAtZero = anchorAtZero
    }

    public init(
        values: [DailyValue],
        name: String,
        colorHex: String? = nil,
        unit: String = "",
        goalLine: Double? = nil,
        movingAverageWindow: Int? = nil,
        height: CGFloat? = nil
    ) {
        self.init(
            series: [ChartSeries.daily(values, name: name, colorHex: colorHex, unit: unit)],
            goalLine: goalLine,
            movingAverageWindow: movingAverageWindow,
            height: height
        )
    }

    private var domain: ClosedRange<Double> {
        ChartScale.domain(
            values: series.flatMap(\.values),
            includingTarget: goalLine ?? goalSteps?.peak,
            anchorAtZero: anchorAtZero
        )
    }

    private var averages: [(series: ChartSeries, values: [Double])] {
        guard let window = movingAverageWindow, window > 1 else { return [] }
        let engine = TrendEngine()
        return series.map { ($0, engine.movingAverage($0.values, window: window)) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if series.allSatisfy(\.isEmpty) {
                ChartEmptyState(message: "Nothing logged yet")
                    .frame(height: height)
            } else {
                chart
                HStack(spacing: 12) {
                    ChartLegend(series: series)
                    if movingAverageWindow != nil {
                        HStack(spacing: 6) {
                            Capsule()
                                .fill(theme.textMuted)
                                .frame(width: 14, height: 2)
                            Text("\(movingAverageWindow ?? 0)-point average")
                                .font(theme.typography.label)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series) { item in
                ForEach(item.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        series: .value("Series", item.name)
                    )
                    .foregroundStyle(item.color(in: theme.palette))
                    .lineStyle(StrokeStyle(lineWidth: theme.metrics.lineWidth, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    if showPoints {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(item.color(in: theme.palette))
                        .symbolSize(theme.metrics.markerSize * theme.metrics.markerSize)
                        // A surface-colored ring keeps overlapping points legible.
                        .symbol {
                            Circle()
                                .fill(item.color(in: theme.palette))
                                .frame(width: theme.metrics.markerSize, height: theme.metrics.markerSize)
                                .overlay(Circle().strokeBorder(theme.surface, lineWidth: 2))
                        }
                    }
                }
            }

            ForEach(Array(averages.enumerated()), id: \.offset) { _, entry in
                ForEach(Array(zip(entry.series.points, entry.values)), id: \.0.id) { point, average in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Average", average),
                        series: .value("Series", "\(entry.series.name) avg")
                    )
                    .foregroundStyle(entry.series.color(in: theme.palette).opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
            }

            if showTrendLine, series.count == 1, let first = series.first {
                let fitted = TrendEngine().trendLine(first.values)
                ForEach(Array(zip(first.points, fitted)), id: \.0.id) { point, value in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Trend", value),
                        series: .value("Series", "__trend")
                    )
                    .foregroundStyle(theme.textMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
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
        .chartLegend(.hidden)
        .chartYScale(domain: domain)
        .chartXSelection(value: $selectedDate)
        .trackerAxes(showX: showAxes, showY: showAxes)
        .frame(height: height)
    }

    private func nearestDate(to date: Date) -> Date? {
        let dates = series.allDates
        guard !dates.isEmpty else { return nil }
        return dates.min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }
    }

    private func tooltip(for date: Date) -> some View {
        var rows = series.compactMap { item -> ChartTooltip.Row? in
            guard let point = item.points.first(where: { $0.date == date }) else { return nil }
            return ChartTooltip.Row(
                label: item.name,
                value: point.hasData
                    ? Formatters.value(point.value, unit: item.unit)
                    : "No entry",
                color: series.count > 1 ? item.color(in: theme.palette) : nil
            )
        }
        if let goalLine {
            rows.append(ChartTooltip.Row(label: "Goal", value: Formatters.compact(goalLine)))
        }
        return ChartTooltip(title: Formatters.friendlyDay(date), rows: rows)
    }
}

#Preview("Line with average") {
    let sample = SampleData.previewTracker()
    let values = ProgressEngine().dailyValues(
        tracker: sample.tracker, entries: sample.entries, dayCount: 45
    )

    return TrackerCard(title: "Focus Time", subtitle: "Daily, 7-day average overlaid") {
        TrackerLineChart(
            values: values,
            name: "Focus",
            colorHex: sample.tracker.colorHex,
            unit: "min",
            goalLine: 60,
            movingAverageWindow: 7
        )
    }
    .padding()
}

#Preview("Line — multi series") {
    let samples = SampleData.previewSeries(count: 3)
    let engine = ProgressEngine()
    let series = samples.enumerated().map { index, sample in
        ChartSeries.daily(
            engine.dailyValues(tracker: sample.tracker, entries: sample.entries, dayCount: 30),
            name: sample.tracker.title,
            colorIndex: index
        )
    }

    return TrackerCard(title: "Comparison") {
        TrackerLineChart(series: series, showPoints: false)
    }
    .padding()
}
