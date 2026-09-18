import SwiftUI

/// A tiny, axis-free trend line. Drawn with `Canvas` rather than Swift Charts —
/// these appear dozens at a time in lists and widgets, where the chart engine's
/// per-instance cost is real and the axes it provides are unwanted anyway.
public struct SparklineView: View {
    @Environment(\.trackerTheme) private var theme

    public enum Style: Sendable, Hashable {
        case line
        case filledLine
        case bars
        /// Bars colored by whether each period met its goal.
        case statusBars
    }

    private let values: [Double]
    private let statuses: [StoplightStatus]
    private let color: Color
    private let style: Style
    private let lineWidth: CGFloat
    private let goalLine: Double?

    public init(
        values: [Double],
        color: Color,
        style: Style = .filledLine,
        lineWidth: CGFloat = 2,
        goalLine: Double? = nil,
        statuses: [StoplightStatus] = []
    ) {
        self.values = values
        self.color = color
        self.style = style
        self.lineWidth = lineWidth
        self.goalLine = goalLine
        self.statuses = statuses
    }

    public init(
        dailyValues: [DailyValue],
        color: Color,
        style: Style = .filledLine,
        goalLine: Double? = nil
    ) {
        self.init(
            values: dailyValues.map(\.value),
            color: color,
            style: style,
            goalLine: goalLine
        )
    }

    public init(snapshots: [ProgressSnapshot], color: Color, style: Style = .statusBars) {
        self.init(
            values: snapshots.map(\.actual),
            color: color,
            style: style,
            goalLine: snapshots.last?.target,
            statuses: snapshots.map(\.status)
        )
    }

    private var upperBound: Double {
        max(values.max() ?? 1, goalLine ?? 0, 0.0001)
    }

    public var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }

            let scaleY: (Double) -> CGFloat = { value in
                let fraction = min(max(value / upperBound, 0), 1)
                return size.height - CGFloat(fraction) * (size.height - lineWidth) - lineWidth / 2
            }

            if let goalLine, goalLine > 0 {
                var path = Path()
                let y = scaleY(goalLine)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    path,
                    with: .color(theme.textMuted.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                )
            }

            switch style {
            case .line, .filledLine:
                drawLine(context: context, size: size, scaleY: scaleY)
            case .bars, .statusBars:
                drawBars(context: context, size: size, scaleY: scaleY)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawLine(context: GraphicsContext, size: CGSize, scaleY: (Double) -> CGFloat) {
        let stepX = size.width / CGFloat(values.count - 1)
        var path = Path()

        for (index, value) in values.enumerated() {
            let point = CGPoint(x: CGFloat(index) * stepX, y: scaleY(value))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }

        if style == .filledLine {
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.32), color.opacity(0.02)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
        }

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )

        // Terminal dot — marks "you are here" on a line with no axis to say so.
        if let last = values.last {
            let x = size.width
            let y = scaleY(last)
            let radius = lineWidth * 1.4
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(color)
            )
        }
    }

    private func drawBars(context: GraphicsContext, size: CGSize, scaleY: (Double) -> CGFloat) {
        let gap: CGFloat = values.count > 30 ? 1 : 2
        let barWidth = max(1.5, (size.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count))

        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * (barWidth + gap)
            let y = scaleY(value)
            let height = max(1, size.height - y)
            let rect = CGRect(x: x, y: y, width: barWidth, height: height)

            let barColor: Color
            if style == .statusBars, index < statuses.count, statuses[index] != .neutral {
                barColor = theme.statusColor(statuses[index])
            } else {
                barColor = color
            }

            context.fill(
                Path(roundedRect: rect, cornerRadius: min(2, barWidth / 2)),
                with: .color(value > 0 ? barColor : theme.gridline)
            )
        }
    }
}

// MARK: - MiniProgressBar

/// A single-line progress bar with the target marked. The row-level companion to
/// ``BulletChartView`` when there is no room even for that.
public struct MiniProgressBar: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: Double = 0

    private let fraction: Double
    private let status: StoplightStatus
    private let color: Color?
    private let height: CGFloat
    private let breachesLimit: Bool

    /// - Parameter breachesLimit: set for an `.atMost` goal that has been
    ///   exceeded. The fill switches to the critical colour, because a full bar
    ///   must never read as success when the goal was a ceiling.
    public init(
        fraction: Double,
        status: StoplightStatus = .neutral,
        color: Color? = nil,
        height: CGFloat = 6,
        breachesLimit: Bool = false
    ) {
        self.fraction = fraction
        self.status = status
        self.color = color
        self.height = height
        self.breachesLimit = breachesLimit
    }

    /// **State wins when there is one; identity fills in when there isn't.**
    ///
    /// Passing a tracker's own colour used to override the status outright, which
    /// collided badly with the categorical palette: a tracker assigned the red
    /// slot read as failing while it was merely *red*, and one assigned green read
    /// as met while it was at risk. The categorical and status palettes are
    /// deliberately close in hue — the reference palette measures series-red
    /// against status-critical at ΔE 4.8 — so they must never both try to colour
    /// the same mark.
    ///
    /// So the bar carries state, and identity lives in the row's icon and
    /// sparkline, where nothing competes with it. `color` is the fallback used
    /// only when there is no goal to be scored against.
    private var fillColor: Color {
        if breachesLimit { return theme.statusColor(.red) }
        if status != .neutral { return theme.statusColor(status) }
        return color ?? theme.accent
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.gridline)

                Capsule()
                    .fill(fillColor)
                    .frame(
                        width: geometry.size.width
                            * min(max(reduceMotion ? fraction : animated, 0), 1)
                    )

                // Overflow pip — a bar that caps at 100% hides overachievement.
                if fraction > 1.02 {
                    Capsule()
                        .fill(theme.surface.opacity(0.65))
                        .frame(width: 2, height: height)
                        .offset(x: geometry.size.width - 6)
                }
            }
        }
        .frame(height: height)
        .onAppear {
            guard theme.motion.animatesOnAppear, !reduceMotion else {
                animated = fraction
                return
            }
            withAnimation(theme.motion.fillAnimation) { animated = fraction }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(theme.motion.fillAnimation) { animated = newValue }
        }
        .accessibilityValue(Formatters.percent(fraction))
    }
}

#Preview("Sparklines") {
    let sample = SampleData.previewTracker()
    let engine = ProgressEngine()
    let daily = engine.dailyValues(tracker: sample.tracker, entries: sample.entries, dayCount: 30)
    let history = engine.history(tracker: sample.tracker, entries: sample.entries, periodCount: 12, cadence: .weekly)

    return VStack(alignment: .leading, spacing: 18) {
        TrackerCard(title: "Filled line") {
            SparklineView(dailyValues: daily, color: ChartPalette.standard.series(0), goalLine: 60)
                .frame(height: 44)
        }
        TrackerCard(title: "Status bars") {
            SparklineView(snapshots: history, color: ChartPalette.standard.series(0))
                .frame(height: 44)
        }
        TrackerCard(title: "Mini bars") {
            VStack(spacing: 10) {
                MiniProgressBar(fraction: 0.35, status: .red)
                MiniProgressBar(fraction: 0.72, status: .yellow)
                MiniProgressBar(fraction: 1.2, status: .green)
            }
        }
    }
    .padding()
}
