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

// MARK: - ReportChartTile

/// One chart on the page.
///
/// A report's visuals do not map one-to-one onto charts: a line chart holds
/// every habit at once, while an area chart draws one per habit. Flattening to
/// tiles first is what lets the page lay them out in a grid — otherwise "two
/// charts" might be one card containing four.
public struct ReportChartTile: Identifiable, Sendable, Hashable {
    public let visual: ReportVisual
    /// `nil` for a chart that holds every habit at once.
    public let trackerID: UUID?
    public let title: String
    public let subtitle: String?

    public var id: String { "\(visual.rawValue)-\(trackerID?.uuidString ?? "all")" }

    public init(visual: ReportVisual, trackerID: UUID?, title: String, subtitle: String?) {
        self.visual = visual
        self.trackerID = trackerID
        self.title = title
        self.subtitle = subtitle
    }
}

public extension CustomReport {

    /// Every chart this report draws, one entry per tile on the page.
    var chartTiles: [ReportChartTile] {
        definition.visuals.flatMap { visual -> [ReportChartTile] in
            if visual.combinesTrackers {
                return [ReportChartTile(
                    visual: visual,
                    trackerID: nil,
                    title: visual.displayName,
                    subtitle: mixedUnitsCaption(for: visual)
                )]
            }
            return trackers.map { tracker in
                ReportChartTile(
                    visual: visual,
                    trackerID: tracker.id,
                    title: tracker.title,
                    subtitle: visual.displayName
                )
            }
        }
    }

    /// Says out loud when a combined chart is showing mixed units, rather than
    /// letting one axis quietly imply they are comparable.
    func mixedUnitsCaption(for visual: ReportVisual) -> String? {
        guard visual.combinesTrackers, !sharesOneUnit else { return nil }
        return "Different units (\(unitSummary)) — compare shapes, not heights."
    }

    /// How many tiles a printed page has to hold: every chart, plus one block of
    /// numbers per habit.
    var pageTileCount: Int { chartTiles.count + trackers.count }

    func tracker(_ id: UUID?) -> CustomReportTracker? {
        guard let id else { return nil }
        return trackers.first { $0.trackerID == id }
    }
}

// MARK: - ReportPageTile

/// One cell on a printed page. Charts and numbers are laid out alike.
public enum ReportPageTile: Identifiable, Sendable, Hashable {
    case chart(ReportChartTile)
    case numbers(trackerID: UUID)

    public var id: String {
        switch self {
        case .chart(let tile): "chart-\(tile.id)"
        case .numbers(let id): "numbers-\(id.uuidString)"
        }
    }
}

public extension CustomReport {

    /// Every cell the printed report needs: each chart, then each habit's
    /// numbers.
    var pageTiles: [ReportPageTile] {
        chartTiles.map(ReportPageTile.chart) + trackers.map { .numbers(trackerID: $0.trackerID) }
    }

    /// Tiles grouped into pages.
    ///
    /// Pages are built explicitly rather than by slicing one tall image at page
    /// height: a blind slice cuts whichever tile straddles the boundary, and
    /// half a table at the foot of a sheet is worse than a blank half-page.
    func pageTiles(perPage: Int) -> [[ReportPageTile]] {
        let all = pageTiles
        guard perPage > 0, !all.isEmpty else { return all.isEmpty ? [] : [all] }
        return stride(from: 0, to: all.count, by: perPage).map {
            Array(all[$0..<min($0 + perPage, all.count)])
        }
    }
}
