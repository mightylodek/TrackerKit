// watchOS-only. The phone's charts assume a canvas this device does not have.
#if os(watchOS)

import SwiftUI
import Charts

// MARK: - WatchHabitChart

/// Last seven days as bars, with the goal drawn across them.
///
/// Purpose-built rather than reused from `Charts/`: at 45mm there is room for
/// bars, a rule and seven letters, and nothing else. No legend, no y axis, no
/// tooltip — the number that matters is printed above the chart instead.
public struct WatchHabitChart: View {
    @Environment(\.trackerTheme) private var theme

    private let values: [DailyValue]
    private let target: Double?
    private let unit: String
    private let colorHex: String

    public init(values: [DailyValue], target: Double?, unit: String, colorHex: String) {
        self.values = values
        self.target = target
        self.unit = unit
        self.colorHex = colorHex
    }

    private var tint: Color { theme.identityColor(hex: colorHex) }

    public var body: some View {
        Chart {
            ForEach(values) { day in
                BarMark(
                    x: .value("Day", Formatters.weekdayInitial(day.date)),
                    y: .value(unit.isEmpty ? "Value" : unit, day.value),
                    width: .ratio(0.6)
                )
                .foregroundStyle(day.hasData ? tint : tint.opacity(0.18))
                .cornerRadius(2)
            }

            // The goal, as a line to clear rather than a number to remember.
            if let target, target > 0 {
                RuleMark(y: .value("Goal", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textMuted)
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }
}

#endif
