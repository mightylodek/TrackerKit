import SwiftUI

/// Contribution-grid heatmap — one cell per day, weeks running left to right.
///
/// Magnitude is encoded in a **single hue, light to dark** (never a rainbow): the
/// eye reads one hue ramp as ordered without being told, and reads a rainbow as
/// categories. Days with no entry are drawn as an empty outlined cell rather than
/// the lightest ramp step, because "nothing logged" and "logged a zero" are
/// different facts and must not look the same.
public struct HeatmapCalendarView: View {
    @Environment(\.trackerTheme) private var theme
    @State private var selected: DailyValue?

    private let values: [DailyValue]
    private let colorHex: String?
    private let unit: String
    private let cellSize: CGFloat
    private let cellSpacing: CGFloat
    private let showsMonthLabels: Bool
    private let showsWeekdayLabels: Bool
    private let calendar: Calendar

    public init(
        values: [DailyValue],
        colorHex: String? = nil,
        unit: String = "",
        cellSize: CGFloat = 13,
        cellSpacing: CGFloat = 3,
        showsMonthLabels: Bool = true,
        showsWeekdayLabels: Bool = true,
        calendar: Calendar = .current
    ) {
        self.values = values
        self.colorHex = colorHex
        self.unit = unit
        self.cellSize = cellSize
        self.cellSpacing = cellSpacing
        self.showsMonthLabels = showsMonthLabels
        self.showsWeekdayLabels = showsWeekdayLabels
        self.calendar = calendar
    }

    private var maxValue: Double {
        max(values.map(\.value).max() ?? 1, 0.0001)
    }

    /// Columns of seven, aligned so each column is one calendar week and each row
    /// is one weekday. Leading blanks pad the first partial week.
    private var weeks: [[DailyValue?]] {
        guard let first = values.first else { return [] }
        let leadingBlanks = (calendar.component(.weekday, from: first.date) - calendar.firstWeekday + 7) % 7

        var cells: [DailyValue?] = Array(repeating: nil, count: leadingBlanks)
        cells.append(contentsOf: values.map { Optional($0) })
        while cells.count % 7 != 0 { cells.append(nil) }

        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if values.isEmpty {
                ChartEmptyState(message: "No history yet", symbolName: "square.grid.3x3")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        if showsMonthLabels { monthLabels }
                        HStack(alignment: .top, spacing: cellSpacing) {
                            if showsWeekdayLabels { weekdayLabels }
                            grid
                        }
                    }
                    .padding(.vertical, 2)
                }
                .defaultScrollAnchor(.trailing)

                footer
            }
        }
    }

    // MARK: Grid

    private var grid: some View {
        HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: cellSpacing) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        cell(day)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: DailyValue?) -> some View {
        if let day {
            let isSelected = selected?.date == day.date
            RoundedRectangle(cornerRadius: 3)
                .fill(fill(for: day))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(
                            isSelected ? theme.textPrimary : (day.hasData ? .clear : theme.gridline),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
                .frame(width: cellSize, height: cellSize)
                .onTapGesture {
                    withAnimation(theme.motion.snappyAnimation) {
                        selected = isSelected ? nil : day
                    }
                }
                .accessibilityLabel(
                    "\(Formatters.dayMonth(day.date)), "
                    + (day.hasData ? Formatters.value(day.value, unit: unit) : "no entry")
                )
        } else {
            Color.clear.frame(width: cellSize, height: cellSize)
        }
    }

    private func fill(for day: DailyValue) -> Color {
        guard day.hasData, day.value > 0 else { return theme.plane }
        let intensity = min(day.value / maxValue, 1)
        if let colorHex {
            // A tracker's own color, stepped by intensity.
            return Color(hex: colorHex).opacity(0.22 + intensity * 0.78)
        }
        return theme.palette.sequentialStep(intensity)
    }

    // MARK: Chrome

    private var weekdayLabels: some View {
        VStack(spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { row in
                let index = (calendar.firstWeekday - 1 + row) % 7
                Text(row % 2 == 1 ? calendar.veryShortWeekdaySymbols[index] : " ")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textMuted)
                    .frame(width: 14, height: cellSize, alignment: .trailing)
            }
        }
    }

    private var monthLabels: some View {
        HStack(alignment: .bottom, spacing: cellSpacing) {
            if showsWeekdayLabels {
                Color.clear.frame(width: 14, height: 10)
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                let label = monthLabel(for: week, at: index)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textMuted)
                    .frame(width: cellSize, height: 10, alignment: .leading)
                    .fixedSize()
            }
        }
    }

    /// Prints the month name on the first column that contains its 1st-of-month,
    /// which is how a contribution grid labels itself without collisions.
    private func monthLabel(for week: [DailyValue?], at index: Int) -> String {
        guard let firstDay = week.compactMap({ $0 }).first else { return " " }

        let containsMonthStart = week.compactMap { $0 }.contains {
            calendar.component(.day, from: $0.date) <= 7
        }
        guard containsMonthStart else { return " " }

        // Avoid repeating the same month on consecutive columns.
        if index > 0 {
            let previous = weeks[index - 1].compactMap { $0 }
            if let previousDay = previous.last,
               calendar.isDate(previousDay.date, equalTo: firstDay.date, toGranularity: .month) {
                return " "
            }
        }
        return firstDay.date.formatted(.dateTime.month(.abbreviated))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let selected {
                HStack(spacing: 6) {
                    Text(Formatters.friendlyDay(selected.date))
                        .font(theme.typography.label.weight(.medium))
                        .foregroundStyle(theme.textPrimary)
                    Text(selected.hasData
                         ? Formatters.value(selected.value, unit: unit)
                         : "No entry")
                        .font(theme.typography.label)
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                }
                .transition(.opacity)
            } else {
                Text("\(values.filter(\.hasData).count) of \(values.count) days logged")
                    .font(theme.typography.label)
                    .foregroundStyle(theme.textMuted)
            }

            Spacer(minLength: 8)
            intensityKey
        }
    }

    private var intensityKey: some View {
        HStack(spacing: 4) {
            Text("Less")
                .font(.system(size: 9))
                .foregroundStyle(theme.textMuted)
            ForEach(0..<5, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(keyColor(step: step))
                    .frame(width: 9, height: 9)
            }
            Text("More")
                .font(.system(size: 9))
                .foregroundStyle(theme.textMuted)
        }
    }

    private func keyColor(step: Int) -> Color {
        let fraction = Double(step) / 4
        if step == 0 { return theme.plane }
        if let colorHex {
            return Color(hex: colorHex).opacity(0.22 + fraction * 0.78)
        }
        return theme.palette.sequentialStep(fraction)
    }
}

#Preview("Heatmap") {
    let sample = SampleData.previewTracker()
    let values = ProgressEngine().dailyValues(
        tracker: sample.tracker, entries: sample.entries, dayCount: 112
    )

    return TrackerCard(title: "Consistency", subtitle: "Last 16 weeks") {
        HeatmapCalendarView(values: values, colorHex: sample.tracker.colorHex, unit: "min")
    }
    .padding()
}
