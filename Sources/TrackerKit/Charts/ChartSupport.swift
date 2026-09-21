import SwiftUI
import Charts

// MARK: - Axis styling

/// Applies the recessive axis treatment every chart in the library shares:
/// hairline gridlines, muted tick labels, no chart junk.
public struct TrackerAxisStyle: ViewModifier {
    @Environment(\.trackerTheme) private var theme

    let showXAxis: Bool
    let showYAxis: Bool
    let xLabelCount: Int
    let yLabelCount: Int
    let unit: String

    public func body(content: Content) -> some View {
        content
            .chartXAxis {
                if showXAxis {
                    AxisMarks(values: .automatic(desiredCount: xLabelCount)) { value in
                        AxisGridLine()
                            .foregroundStyle(theme.gridline.opacity(0.6))
                        AxisTick()
                            .foregroundStyle(theme.axis)
                        // Date ticks get a compact label of their own. The
                        // default runs to "Sep 14", which truncates to "Sep…"
                        // on a narrow tile and tells the reader nothing.
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(Formatters.axisDate(date))
                                    .font(theme.typography.micro)
                                    .monospacedDigit()
                                    .foregroundStyle(theme.textMuted)
                            }
                        } else {
                            AxisValueLabel()
                                .font(theme.typography.micro)
                                .foregroundStyle(theme.textMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                if showYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: yLabelCount)) { value in
                        AxisGridLine()
                            .foregroundStyle(theme.gridline)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(Formatters.compact(number))
                                    .font(theme.typography.micro)
                                    .monospacedDigit()
                                    .foregroundStyle(theme.textMuted)
                            }
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.background(Color.clear)
            }
    }
}

public extension View {
    /// Standard themed axes. Turn either axis off for sparkline-style charts.
    func trackerAxes(
        showX: Bool = true,
        showY: Bool = true,
        xLabelCount: Int = 5,
        yLabelCount: Int = 4,
        unit: String = ""
    ) -> some View {
        modifier(TrackerAxisStyle(
            showXAxis: showX,
            showYAxis: showY,
            xLabelCount: xLabelCount,
            yLabelCount: yLabelCount,
            unit: unit
        ))
    }
}

// MARK: - ChartTooltip

/// The card shown when a chart is scrubbed.
///
/// Every time-series chart here ships one. A chart you can touch and get no
/// number back from is a picture, not an instrument.
public struct ChartTooltip: View {
    @Environment(\.trackerTheme) private var theme

    public struct Row: Identifiable, Hashable {
        public let id = UUID()
        public let label: String
        public let value: String
        public let color: Color?

        public init(label: String, value: String, color: Color? = nil) {
            self.label = label
            self.value = value
            self.color = color
        }
    }

    private let title: String
    private let rows: [Row]

    public init(title: String, rows: [Row]) {
        self.title = title
        self.rows = rows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(theme.typography.micro.weight(.semibold))
                .foregroundStyle(theme.textSecondary)

            ForEach(rows) { row in
                HStack(spacing: 6) {
                    if let color = row.color {
                        Circle()
                            .fill(color)
                            .frame(width: 7, height: 7)
                    }
                    Text(row.label)
                        .font(theme.typography.label)
                        .foregroundStyle(theme.textSecondary)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(theme.typography.label.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.surface, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .fixedSize()
    }
}

// MARK: - TrendBadge

/// A compact delta chip: arrow, percentage, favorable coloring.
public struct TrendBadge: View {
    @Environment(\.trackerTheme) private var theme

    private let trend: Trend
    private let direction: GoalDirection
    private let unit: String
    private let compact: Bool

    public init(
        trend: Trend,
        direction: GoalDirection = .atLeast,
        unit: String = "",
        compact: Bool = false
    ) {
        self.trend = trend
        self.direction = direction
        self.unit = unit
        self.compact = compact
    }

    private var isFavorable: Bool { trend.isFavorable(for: direction) }

    private var symbol: String {
        switch trend.direction {
        case .rising: "arrow.up.right"
        case .falling: "arrow.down.right"
        case .flat: "arrow.right"
        }
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(theme.typography.micro.weight(.bold))
            Text(trend.displayText(unit: unit))
                .font(theme.typography.label.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(
            trend.direction == .flat ? theme.textMuted : theme.deltaColor(isFavorable: isFavorable)
        )
        .padding(.horizontal, compact ? 0 : 8)
        .padding(.vertical, compact ? 0 : 3)
        .background {
            if !compact {
                Capsule().fill(theme.plane)
            }
        }
        .accessibilityLabel(
            "\(trend.direction == .rising ? "Up" : trend.direction == .falling ? "Down" : "Flat") "
            + "\(trend.displayText(unit: unit)), \(isFavorable ? "favorable" : "unfavorable")"
        )
    }
}

// MARK: - Empty state

/// Shown in place of a chart when there is nothing to draw.
///
/// Wraps `ContentUnavailableView` rather than hand-rolling an empty state. The
/// system component already handles Dynamic Type, VoiceOver grouping and the
/// platform's own empty-state proportions, and it keeps these looking like the
/// rest of iOS instead of like this library's idea of iOS.
///
/// The call-site API is deliberately unchanged from the custom version it
/// replaced, so adopting it touched no chart code.
public struct ChartEmptyState: View {
    @Environment(\.trackerTheme) private var theme

    private let message: String
    private let symbolName: String
    private let detail: String?

    public init(
        message: String = "No data yet",
        symbolName: String = "chart.xyaxis.line",
        detail: String? = nil
    ) {
        self.message = message
        self.symbolName = symbolName
        self.detail = detail
    }

    public var body: some View {
        ContentUnavailableView {
            Label(message, systemImage: symbolName)
        } description: {
            if let detail {
                Text(detail)
            }
        }
        .foregroundStyle(theme.textMuted)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Value scale helpers

public enum ChartScale {

    /// A y-domain with headroom, always anchored at zero for magnitude charts.
    ///
    /// Truncating a bar chart's baseline exaggerates differences — the most common
    /// way a chart lies — so bars and areas always start at zero here.
    public static func domain(
        values: [Double],
        includingTarget target: Double? = nil,
        headroom: Double = 0.15,
        anchorAtZero: Bool = true
    ) -> ClosedRange<Double> {
        var all = values.filter(\.isFinite)
        if let target { all.append(target) }
        guard let maxValue = all.max(), maxValue > 0 else { return 0...1 }

        let minValue = anchorAtZero ? 0 : (all.min() ?? 0)
        let padded = maxValue * (1 + headroom)
        return minValue...max(padded, minValue + 1)
    }

    /// "Nice" step for reference lines: 1, 2, 5, 10, 20, 50...
    public static func niceStep(for span: Double, targetCount: Int = 4) -> Double {
        guard span > 0, targetCount > 0 else { return 1 }
        let rough = span / Double(targetCount)
        let magnitude = pow(10, floor(log10(rough)))
        let normalized = rough / magnitude
        let snapped: Double
        switch normalized {
        case ..<1.5: snapped = 1
        case ..<3: snapped = 2
        case ..<7: snapped = 5
        default: snapped = 10
        }
        return snapped * magnitude
    }
}
