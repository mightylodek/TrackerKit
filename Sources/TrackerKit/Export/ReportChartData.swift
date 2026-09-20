import Foundation

// MARK: - Chart adapters

/// Turns a built report into the shapes the chart views already take.
///
/// Kept beside the report rather than inside the charts so the filtering stays
/// in one place: a chart drawn from these values is showing exactly what the
/// report says it is — same range, same weekday filter, same habits.
public extension CustomReportTracker {

    /// The daily section as chart input.
    ///
    /// Falls back to the finest section available, so a report configured with
    /// only weekly totals still draws something rather than an empty chart.
    var dailyValues: [DailyValue] {
        let source = section(.daily) ?? sections.first
        return (source?.buckets ?? []).map { bucket in
            DailyValue(
                date: bucket.interval.start,
                value: bucket.value,
                entryCount: bucket.entryCount
            )
        }
    }

    /// One series for a multi-habit chart.
    ///
    /// `colorHex` carries the tracker's own colour so identity follows the
    /// entity rather than its position in the list — a habit keeps its colour
    /// when another is filtered out.
    func chartSeries(colorIndex: Int) -> ChartSeries {
        ChartSeries(
            name: title,
            points: dailyValues.map { value in
                ChartPoint(date: value.date, value: value.value, hasData: value.hasData)
            },
            colorIndex: colorIndex,
            colorHex: colorHex,
            unit: unit
        )
    }
}

public extension CustomReport {

    /// Every habit as its own series, for the charts that combine them.
    var chartSeries: [ChartSeries] {
        trackers.enumerated().map { index, tracker in
            tracker.chartSeries(colorIndex: index)
        }
    }

    /// Whether the habits in this report share a unit.
    ///
    /// Stacking minutes on top of glasses produces a number that means nothing,
    /// so a combined chart has to check before drawing one.
    var sharesOneUnit: Bool {
        let units = Set(trackers.map(\.unit))
        return units.count <= 1
    }

    /// The units on show, for a caption that admits when they differ.
    var unitSummary: String {
        Set(trackers.map(\.unit)).sorted().filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
