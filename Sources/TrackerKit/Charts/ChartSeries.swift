import Foundation
import SwiftUI

// MARK: - ChartPoint

/// One plotted value.
public struct ChartPoint: Identifiable, Sendable, Hashable {
    public let date: Date
    public let value: Double
    /// Axis label override. Defaults to a date-derived label.
    public let label: String?
    /// Whether this point represents real data or a filled-in zero. Empty days are
    /// drawn dimmer so "no data" and "a genuine zero" never look the same.
    public let hasData: Bool

    public var id: Date { date }

    public init(date: Date, value: Double, label: String? = nil, hasData: Bool = true) {
        self.date = date
        self.value = value
        self.label = label
        self.hasData = hasData
    }
}

// MARK: - ChartSeries

/// A named run of points sharing one identity color.
public struct ChartSeries: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var points: [ChartPoint]
    /// Slot in the categorical palette. Color follows the **entity**, so this is
    /// assigned once when the series is created and never recomputed from its
    /// position in a filtered list.
    public var colorIndex: Int
    /// Explicit color override, used when a tracker carries its own color.
    public var colorHex: String?
    public var unit: String

    public init(
        id: UUID = UUID(),
        name: String,
        points: [ChartPoint],
        colorIndex: Int = 0,
        colorHex: String? = nil,
        unit: String = ""
    ) {
        self.id = id
        self.name = name
        self.points = points
        self.colorIndex = colorIndex
        self.colorHex = colorHex
        self.unit = unit
    }

    /// The colour this series draws in.
    ///
    /// Routed through ``ChartPalette/identityColor(hex:seed:)`` so a
    /// brand-monochrome theme actually applies: taking the stored hex raw drew a
    /// blue chart in a teal app and ignored the theme entirely.
    public func color(in palette: ChartPalette) -> Color {
        if let colorHex { return palette.identityColor(hex: colorHex, seed: colorIndex) }
        return palette.seriesColor(colorIndex)
    }

    /// How many days this series spans, inclusive, or `nil` when it holds no
    /// points. Used to decide whether an axis labels weekdays or dates.
    var dayCount: Int? {
        let dates = points.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: first),
            to: calendar.startOfDay(for: last)
        ).day ?? 0
        return days + 1
    }

    /// Contiguous runs of real data.
    ///
    /// Swift Charts joins consecutive points in a series, so a day with nothing
    /// logged either dives to zero or gets drawn straight through — both of
    /// which contradict the table beside it saying "—". Giving each run its own
    /// series identifier is the documented way to leave a genuine gap;
    /// `Optional` is not `Plottable`, so nil values are not an option.
    public var dataRuns: [[ChartPoint]] {
        var runs: [[ChartPoint]] = []
        var current: [ChartPoint] = []
        for point in points {
            if point.hasData {
                current.append(point)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    public var values: [Double] { points.map(\.value) }
    public var total: Double { values.reduce(0, +) }
    public var peak: Double { values.max() ?? 0 }
    public var isEmpty: Bool { points.isEmpty }

    // MARK: Builders

    /// Builds a series from daily values.
    public static func daily(
        _ values: [DailyValue],
        name: String,
        colorIndex: Int = 0,
        colorHex: String? = nil,
        unit: String = ""
    ) -> ChartSeries {
        ChartSeries(
            name: name,
            points: values.map {
                ChartPoint(date: $0.date, value: $0.value, hasData: $0.hasData)
            },
            colorIndex: colorIndex,
            colorHex: colorHex,
            unit: unit
        )
    }

    /// Builds a series from scored periods.
    public static func periods(
        _ snapshots: [ProgressSnapshot],
        name: String,
        colorIndex: Int = 0,
        colorHex: String? = nil,
        calendar: Calendar = .current
    ) -> ChartSeries {
        ChartSeries(
            name: name,
            points: snapshots.map {
                ChartPoint(
                    date: $0.period.start,
                    value: $0.actual,
                    label: $0.period.shortLabel(calendar: calendar),
                    hasData: $0.entryCount > 0
                )
            },
            colorIndex: colorIndex,
            colorHex: colorHex,
            unit: snapshots.first?.unit ?? ""
        )
    }

    /// The **target** line that goes with a run of periods.
    ///
    /// This is drawn from each period's own governing goal, which is what makes a
    /// raised target show up as a step in the chart rather than silently
    /// rewriting the past.
    public static func targets(
        _ snapshots: [ProgressSnapshot],
        name: String = "Goal",
        colorIndex: Int = 7,
        calendar: Calendar = .current
    ) -> ChartSeries? {
        let points = snapshots.compactMap { snapshot -> ChartPoint? in
            guard let target = snapshot.target else { return nil }
            return ChartPoint(
                date: snapshot.period.start,
                value: target,
                label: snapshot.period.shortLabel(calendar: calendar)
            )
        }
        guard points.count > 1 else { return nil }
        return ChartSeries(name: name, points: points, colorIndex: colorIndex)
    }
}

// MARK: - Series capping

public extension Array where Element == ChartSeries {

    /// Folds everything past `limit` into a single "Other" series.
    ///
    /// Identity colors run out at eight, and in practice they run out sooner —
    /// this is the mechanism that keeps a chart readable instead of inventing a
    /// ninth hue nobody can distinguish.
    func capped(at limit: Int, otherName: String = "Other") -> [ChartSeries] {
        guard count > limit, limit > 0 else { return self }

        let kept = Array(prefix(limit - 1))
        let folded = Array(dropFirst(limit - 1))

        // Sum the folded series point-by-point on shared dates.
        var totals: [Date: Double] = [:]
        for series in folded {
            for point in series.points {
                totals[point.date, default: 0] += point.value
            }
        }
        let points = totals
            .sorted { $0.key < $1.key }
            .map { ChartPoint(date: $0.key, value: $0.value) }

        let other = ChartSeries(
            name: "\(otherName) (\(folded.count))",
            points: points,
            colorIndex: limit - 1
        )
        return kept + [other]
    }

    /// Every date appearing in any series, sorted — the shared x domain.
    var allDates: [Date] {
        Set(flatMap { $0.points.map(\.date) }).sorted()
    }

    /// Largest single value across all series.
    var peak: Double {
        map(\.peak).max() ?? 0
    }

    /// Largest stacked total on any one date — the y domain for a stacked chart.
    var stackedPeak: Double {
        var totals: [Date: Double] = [:]
        for series in self {
            for point in series.points {
                totals[point.date, default: 0] += point.value
            }
        }
        return totals.values.max() ?? 0
    }
}

// MARK: - ChartLegend

/// Identity key for a chart.
///
/// Present whenever two or more series are drawn — a chart that carries identity
/// in color alone is unreadable to a colorblind viewer and unprintable in
/// grayscale. A single-series chart doesn't get one; its title already names it.
public struct ChartLegend: View {
    @Environment(\.trackerTheme) private var theme

    private let series: [ChartSeries]
    private let showValues: Bool

    public init(series: [ChartSeries], showValues: Bool = false) {
        self.series = series
        self.showValues = showValues
    }

    public var body: some View {
        if series.count >= 2 {
            FlowLayout(spacing: 12) {
                ForEach(series) { item in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.color(in: theme.palette))
                            .frame(width: 10, height: 10)
                        Text(item.name)
                            .font(theme.typography.label)
                            .foregroundStyle(theme.textSecondary)
                        if showValues {
                            Text(Formatters.compact(item.total))
                                .font(theme.typography.label.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(theme.textPrimary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - FlowLayout

/// Wraps its children onto as many lines as it takes. Used by the legend so a
/// six-series key doesn't clip on a narrow phone.
public struct FlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestLine: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                totalHeight += lineHeight + lineSpacing
                widestLine = max(widestLine, lineWidth)
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += (lineWidth > 0 ? spacing : 0) + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }

        widestLine = max(widestLine, lineWidth)
        totalHeight += lineHeight
        return CGSize(
            width: maxWidth == .infinity ? widestLine : min(widestLine, maxWidth),
            height: totalHeight
        )
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

public extension Array where Element == ChartSeries {
    /// The widest span any series covers, in days.
    ///
    /// `nil` when nothing is plotted, which leaves the axis on dates rather than
    /// guessing at a weekday label for an empty chart.
    var dayCount: Int? {
        compactMap(\.dayCount).max()
    }
}
