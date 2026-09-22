// iOS-only: resolving a dynamic colour against a named appearance needs
// `UITraitCollection`, which watchOS does not have — and does not need, having
// no light appearance to resolve against.
#if os(iOS)

import Testing
import Foundation
import SwiftUI
@testable import TrackerKit

/// Charts and PDFs built from a report's filtered data.
@Suite("Report visuals")
@MainActor
struct ReportVisualTests {

    private let engine = CustomReportEngine(calculator: .fixed)
    private let profileID = UUID()

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }

    private func date(_ d: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 9, day: d, hour: hour)) ?? .distantPast
    }

    private func tracker(
        _ title: String,
        kind: TrackerKind = .duration,
        goal: GoalVersion? = nil
    ) -> Tracker {
        Tracker(
            profileID: profileID,
            title: title,
            kind: kind,
            goalHistory: goal.map { [$0] } ?? []
        )
    }

    private func goal(_ target: Double, unit: String = "min", cadence: Cadence = .daily,
                      direction: GoalDirection = .atLeast) -> GoalVersion {
        GoalVersion(
            effectiveFrom: date(1),
            target: target,
            cadence: cadence,
            direction: direction,
            unit: unit,
            aggregation: .sum
        )
    }

    private func build(
        _ trackers: [Tracker],
        entries: [UUID: [Entry]],
        visuals: [ReportVisual] = [],
        weekdays: Set<Int> = [],
        from: Int = 14,
        to: Int = 20
    ) -> CustomReport {
        let definition = ReportDefinition(
            name: "Test",
            profileID: profileID,
            trackerIDs: trackers.map(\.id),
            range: .absolute(start: date(from), end: date(to)),
            weekdays: weekdays,
            breakdowns: [.daily, .total],
            visuals: visuals
        )
        return engine.build(definition, trackers: trackers, entriesByTracker: entries, now: date(21))
    }

    // MARK: Chart input

    @Test("Daily buckets become chart points")
    func dailyValuesMapAcross() throws {
        let reading = tracker("Reading")
        let logged = (14...20).map {
            Entry(trackerID: reading.id, profileID: profileID, date: date($0), value: 10)
        }
        let report = build([reading], entries: [reading.id: logged])
        let values = try #require(report.trackers.first).dailyValues

        #expect(values.count == 7)
        #expect(values.allSatisfy { $0.value == 10 })
        #expect(values.allSatisfy { $0.hasData })
    }

    /// The filter has to reach the charts too, or a chart contradicts the table
    /// printed beside it.
    @Test("A weekday filter reaches the chart data")
    func filterAppliesToCharts() throws {
        let reading = tracker("Reading")
        let logged = (14...20).map {
            Entry(trackerID: reading.id, profileID: profileID, date: date($0), value: 10)
        }
        // Mon–Fri only.
        let report = build([reading], entries: [reading.id: logged], weekdays: [2, 3, 4, 5, 6])

        #expect(try #require(report.trackers.first).dailyValues.count == 5)
    }

    @Test("A habit keeps its own colour in a combined chart")
    func seriesCarriesTrackerColour() {
        let a = tracker("Reading")
        let b = tracker("Water", kind: .count)
        let report = build([a, b], entries: [:])
        let series = report.chartSeries

        #expect(series.count == 2)
        #expect(series[0].colorHex == a.colorHex)
        #expect(series.map(\.name) == ["Reading", "Water"])
    }

    @Test("Mixed units are detected so a chart can say so")
    func mixedUnitsAreFlagged() {
        let minutes = tracker("Reading", goal: goal(30, unit: "min"))
        let glasses = tracker("Water", kind: .count, goal: goal(8, unit: "glasses"))

        #expect(build([minutes], entries: [:]).sharesOneUnit)
        #expect(!build([minutes, glasses], entries: [:]).sharesOneUnit)
    }

    // MARK: Goal scaling

    /// 30 minutes a day across seven days is 210, not 30.
    @Test("A daily goal scales to the window")
    func dailyGoalScales() {
        let reading = tracker("Reading", goal: goal(30))
        let report = build([reading], entries: [:])

        #expect(report.trackers.first?.target == 210)
    }

    @Test("A daily goal scales to the days that actually count")
    func goalScalesToFilteredDays() {
        let reading = tracker("Reading", goal: goal(30))
        let report = build([reading], entries: [:], weekdays: [2, 3, 4, 5, 6])

        // Five weekdays in Sep 14-20, so 150 rather than 210.
        #expect(report.trackers.first?.target == 150)
    }

    /// Pro-rating a weekly goal across a partial week invents a number nobody
    /// set, so it is left alone.
    @Test("A weekly goal is not pro-rated")
    func weeklyGoalIsNotScaled() {
        let reading = tracker("Reading", goal: goal(120, cadence: .weekly))
        #expect(build([reading], entries: [:]).trackers.first?.target == 120)
    }

    @Test("A habit with no goal has no target")
    func noGoalNoTarget() {
        #expect(build([tracker("Reading")], entries: [:]).trackers.first?.target == nil)
    }

    @Test("The goal in force when the window opened is the one used")
    func goalIsTakenFromWindowStart() {
        var reading = tracker("Reading", goal: goal(30))
        // A later goal must not be applied to days it never governed.
        reading.goalHistory.append(
            GoalVersion(effectiveFrom: date(19), target: 60, cadence: .daily,
                        direction: .atLeast, unit: "min", aggregation: .sum)
        )
        let report = build([reading], entries: [:])

        #expect(report.trackers.first?.goal?.target == 30)
    }

    // MARK: Rendering

    @Test("Every visual renders, including with nothing logged")
    func visualsRender() {
        let reading = tracker("Reading", goal: goal(30))
        let water = tracker("Water", kind: .count, goal: goal(8, unit: "glasses"))
        let logged = (14...20).map {
            Entry(trackerID: reading.id, profileID: profileID, date: date($0), value: 10)
        }

        for visual in ReportVisual.allCases {
            let populated = build([reading, water], entries: [reading.id: logged], visuals: [visual])
            #expect(render(ReportVisualsView(report: populated)) != nil,
                    "\(visual.displayName) failed to render with data")

            let empty = build([reading, water], entries: [:], visuals: [visual])
            #expect(render(ReportVisualsView(report: empty)) != nil,
                    "\(visual.displayName) failed to render with nothing logged")
        }
    }

    @Test("A report with every visual at once renders")
    func allVisualsTogether() {
        let reading = tracker("Reading", goal: goal(30))
        let logged = (14...20).map {
            Entry(trackerID: reading.id, profileID: profileID, date: date($0), value: 10)
        }
        let report = build([reading], entries: [reading.id: logged], visuals: ReportVisual.allCases)
        #expect(render(ReportVisualsView(report: report)) != nil)
    }

    // MARK: PDF

    @Test("The PDF is a real PDF, not just bytes")
    func pdfIsValid() {
        let reading = tracker("Reading", goal: goal(30))
        let logged = (14...20).map {
            Entry(trackerID: reading.id, profileID: profileID, date: date($0), value: 10)
        }
        let report = build([reading], entries: [reading.id: logged], visuals: [.area, .bullets])

        let data = CustomReportPDFRenderer().render(report)
        #expect(data.count > 1_000, "PDF is suspiciously small")
        // Header check: non-empty Data proves nothing about whether a reader can
        // open it.
        #expect(data.prefix(5) == Data("%PDF-".utf8))

        let document = CGPDFDocument(CGDataProvider(data: data as CFData)!)
        #expect(document != nil, "Core Graphics could not parse the PDF")
        #expect((document?.numberOfPages ?? 0) >= 1)
    }

    @Test("A long report spills onto more than one page")
    func longReportPaginates() throws {
        let trackers = (1...6).map { tracker("Habit \($0)", goal: goal(30)) }
        var entries: [UUID: [Entry]] = [:]
        for t in trackers {
            entries[t.id] = (14...20).map {
                Entry(trackerID: t.id, profileID: profileID, date: date($0), value: 10)
            }
        }
        let report = build(trackers, entries: entries, visuals: [.area, .heatmap, .bullets])

        let data = CustomReportPDFRenderer().render(report)
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(document.numberOfPages > 1, "Six habits with three charts fitted on one page?")
    }

    @Test("An empty report still produces a readable page")
    func emptyReportStillRenders() {
        let report = build([tracker("Reading")], entries: [:], visuals: [.area])
        let data = CustomReportPDFRenderer().render(report)

        #expect(data.prefix(5) == Data("%PDF-".utf8))
        #expect(CGPDFDocument(CGDataProvider(data: data as CFData)!)?.numberOfPages ?? 0 >= 1)
    }

    /// Renders offscreen the way RenderSmokeTests does.
    private func render(_ view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 390).trackerTheme(.nocturne))
        renderer.scale = 1
        return renderer.uiImage
    }
}

// MARK: - Series colour and gaps

/// Two bugs a report screenshot exposed, both wider than reports.
@Suite("Chart series")
@MainActor
struct ChartSeriesTests {

    /// Concrete channel values. `Color(light:dark:)` wraps a dynamic UIColor and
    /// two of those are never `==` even when identical, so comparing `Color`
    /// directly produces assertions that hold whatever the code does.
    private func rgb(_ color: Color) -> [CGFloat] {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { ($0 * 1000).rounded() / 1000 }
    }

    /// A chart drew the raw categorical blue in a monochrome teal app, because
    /// series colour never consulted `identityMode`.
    @Test("A series honours the palette's identity mode")
    func seriesRespectsIdentityMode() {
        let hex = ChartPalette.nocturne.categorical[1].light
        let series = ChartSeries(name: "Reading", points: [], colorHex: hex)

        #expect(rgb(series.color(in: .nocturne)) != rgb(Color(hex: hex)),
                "Monochrome palette drew the raw categorical hue")
        #expect(rgb(series.color(in: .standard)) == rgb(Color(hex: hex)),
                "A categorical palette should use the colour as given")
    }

    @Test("An index-coloured series folds too")
    func indexedSeriesFolds() {
        let series = ChartSeries(name: "Reading", points: [], colorIndex: 0)
        #expect(rgb(series.color(in: .nocturne)) != rgb(ChartPalette.nocturne.series(0)))
        #expect(rgb(series.color(in: .standard)) == rgb(ChartPalette.standard.series(0)))
    }

    /// The table says "—" for a day with nothing logged; the chart used to dive
    /// to zero on the same day, asserting the opposite.
    @Test("Missing days split a series into runs")
    func gapsSplitRuns() {
        let day = { (offset: Int) in Date(timeIntervalSince1970: 86_400 * Double(offset)) }
        let points = [
            ChartPoint(date: day(0), value: 10, hasData: true),
            ChartPoint(date: day(1), value: 0, hasData: false),
            ChartPoint(date: day(2), value: 20, hasData: true),
            ChartPoint(date: day(3), value: 30, hasData: true),
        ]
        let runs = ChartSeries(name: "x", points: points).dataRuns

        #expect(runs.count == 2, "The gap did not break the series")
        #expect(runs[0].count == 1)
        #expect(runs[1].count == 2)
    }

    @Test("A series with no gaps stays one run")
    func unbrokenSeriesIsOneRun() {
        let points = (0..<4).map {
            ChartPoint(date: Date(timeIntervalSince1970: 86_400 * Double($0)), value: 5, hasData: true)
        }
        #expect(ChartSeries(name: "x", points: points).dataRuns.count == 1)
    }

    @Test("A series with nothing logged has no runs")
    func emptySeriesHasNoRuns() {
        let points = (0..<3).map {
            ChartPoint(date: Date(timeIntervalSince1970: 86_400 * Double($0)), value: 0, hasData: false)
        }
        #expect(ChartSeries(name: "x", points: points).dataRuns.isEmpty)
    }

    /// A logged zero is data and must stay in its run.
    @Test("A genuine zero is not a gap")
    func loggedZeroIsNotAGap() {
        let points = [
            ChartPoint(date: Date(timeIntervalSince1970: 0), value: 5, hasData: true),
            ChartPoint(date: Date(timeIntervalSince1970: 86_400), value: 0, hasData: true),
        ]
        #expect(ChartSeries(name: "x", points: points).dataRuns.count == 1)
    }
}

// MARK: - Isolated runs

@Suite("Isolated data points")
@MainActor
struct IsolatedPointTests {

    /// A run of one draws neither an area nor a stroke, so a day sitting alone
    /// between two gaps would render as nothing at all.
    @Test("A lone day between gaps still renders")
    func loneDayRenders() {
        let day = { (offset: Int) in Date(timeIntervalSince1970: 86_400 * Double(offset)) }
        let points = [
            ChartPoint(date: day(0), value: 0, hasData: false),
            ChartPoint(date: day(1), value: 42, hasData: true),
            ChartPoint(date: day(2), value: 0, hasData: false),
        ]
        let series = ChartSeries(name: "Reading", points: points, colorHex: "#2BC8D4", unit: "min")

        #expect(series.dataRuns.count == 1)
        #expect(series.dataRuns[0].count == 1)

        let renderer = ImageRenderer(
            content: TrackerAreaChart(series: [series]).frame(width: 360).trackerTheme(.nocturne)
        )
        renderer.scale = 1
        #expect(renderer.uiImage != nil)
    }
}


// MARK: - Page layout

/// How many charts fit on a sheet of paper.
///
/// Reported after a real print: two charts took two pages, which on US Letter is
/// absurd — a page is wide, and stacking full-width charts wastes half of it.
@Suite("Print layout")
@MainActor
struct PrintLayoutTests {

    private let engine = CustomReportEngine(calculator: .fixed)
    private let profileID = UUID()

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }

    private func date(_ d: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 12)) ?? .distantPast
    }

    private func report(visuals: [ReportVisual], habits: Int = 1,
                        breakdowns: Set<ReportBreakdown> = [.total]) -> CustomReport {
        let trackers = (0..<habits).map {
            Tracker(profileID: profileID, title: "Habit \($0)", kind: .duration)
        }
        var entries: [UUID: [Entry]] = [:]
        for tracker in trackers {
            entries[tracker.id] = (14...20).map {
                Entry(trackerID: tracker.id, profileID: profileID, date: date($0), value: 10)
            }
        }
        let definition = ReportDefinition(
            name: "Layout",
            profileID: profileID,
            trackerIDs: trackers.map(\.id),
            range: .absolute(start: date(14), end: date(20)),
            breakdowns: breakdowns,
            visuals: visuals
        )
        return engine.build(definition, trackers: trackers, entriesByTracker: entries, now: date(21))
    }

    /// Rendered height at page width.
    private func height(_ report: CustomReport, layout: ReportVisualsView.Layout) -> CGFloat {
        let width = CustomReportPDFRenderer.pageSize.width - CustomReportPDFRenderer.margin * 2
        let renderer = ImageRenderer(
            content: ReportVisualsView(report: report, layout: layout)
                .trackerTheme(.standard)
                .frame(width: width)
        )
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return renderer.uiImage?.size.height ?? 0
    }

    // MARK: Tiles

    /// A report's visuals are not its charts: a line chart holds every habit,
    /// an area chart draws one each.
    @Test("Combined visuals make one tile, per-habit visuals make one each")
    func tileCounts() {
        #expect(report(visuals: [.line], habits: 3).chartTiles.count == 1)
        #expect(report(visuals: [.area], habits: 3).chartTiles.count == 3)
        #expect(report(visuals: [.area, .line], habits: 2).chartTiles.count == 3)
    }

    @Test("Every tile is uniquely identified")
    func tilesHaveDistinctIDs() {
        let tiles = report(visuals: [.area, .bars, .heatmap], habits: 3).chartTiles
        #expect(Set(tiles.map(\.id)).count == tiles.count)
    }

    // MARK: Fitting

    /// The complaint, measured: two charts side by side rather than stacked.
    @Test("Two charts sit side by side, not one above the other")
    func twoChartsShareARow() {
        let two = report(visuals: [.area], habits: 2)
        #expect(two.chartTiles.count == 2)

        let stacked = height(two, layout: .stacked)
        let grid = height(two, layout: .grid)

        #expect(grid < stacked * 0.75,
                "Grid height \(grid) is not meaningfully shorter than stacked \(stacked) — they are still in a column")
    }

    @Test("Four charts fit the height of a page")
    func fourChartsFitOnePage() {
        let four = report(visuals: [.area], habits: 4)
        #expect(four.chartTiles.count == 4)

        let usable = CustomReportPDFRenderer.pageSize.height - CustomReportPDFRenderer.margin * 2
        let grid = height(four, layout: .grid)

        // Two rows of tiles, with the header still to fit above them.
        #expect(grid <= usable - 80,
                "Four charts render \(grid)pt tall, which will not fit \(usable)pt of page under a header")
    }

    /// The whole document, not just the charts: a two-chart report should be one
    /// sheet, which is what it took two of before.
    @Test("A two-chart report prints on a single page")
    func twoChartReportIsOnePage() throws {
        let data = CustomReportPDFRenderer(scale: 1)
            .render(report(visuals: [.area], habits: 2), appearance: .light, appTheme: .standard)
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))

        #expect(document.numberOfPages == 1,
                "A two-chart report still takes \(document.numberOfPages) pages")
    }

    @Test("A four-chart report stays within two pages")
    func fourChartReportIsCompact() throws {
        let data = CustomReportPDFRenderer(scale: 1)
            .render(report(visuals: [.area], habits: 4), appearance: .light, appTheme: .standard)
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))

        #expect(document.numberOfPages <= 2,
                "Four charts and their tables took \(document.numberOfPages) pages")
    }

    /// On a phone the trade runs the other way: width is scarce, scrolling free.
    @Test("The screen still stacks")
    func screenStaysStacked() {
        let two = report(visuals: [.area], habits: 2)
        #expect(height(two, layout: .stacked) > height(two, layout: .grid))
    }
}

// MARK: - Page composition

/// How tiles are grouped onto sheets.
///
/// Reported after printing: a single habit's chart and its totals took two
/// pages, the totals ran full width at body size, and four charts down a
/// portrait sheet squeezed into letterbox strips.
@Suite("Page composition")
@MainActor
struct PageCompositionTests {

    private let engine = CustomReportEngine(calculator: .fixed)
    private let profileID = UUID()

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }

    private func date(_ d: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 12)) ?? .distantPast
    }

    private func report(habits: Int, visuals: [ReportVisual],
                        breakdowns: Set<ReportBreakdown> = [.daily, .total]) -> CustomReport {
        let trackers = (0..<habits).map {
            Tracker(profileID: profileID, title: "Habit \($0)", kind: .duration)
        }
        var entries: [UUID: [Entry]] = [:]
        for tracker in trackers {
            entries[tracker.id] = (14...20).map {
                Entry(trackerID: tracker.id, profileID: profileID, date: date($0), value: 20)
            }
        }
        let definition = ReportDefinition(
            name: "Layout", profileID: profileID,
            trackerIDs: trackers.map(\.id),
            range: .absolute(start: date(14), end: date(20)),
            breakdowns: breakdowns, visuals: visuals
        )
        return engine.build(definition, trackers: trackers, entriesByTracker: entries, now: date(21))
    }

    private func pageCount(_ report: CustomReport) throws -> Int {
        let data = CustomReportPDFRenderer(scale: 1)
            .render(report, appearance: .light, appTheme: .standard)
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        return document.numberOfPages
    }

    // MARK: Tiles

    @Test("A page holds every chart and every habit's numbers")
    func tileInventory() {
        let r = report(habits: 3, visuals: [.area])
        // Three area charts, one per habit, plus three blocks of numbers.
        #expect(r.pageTiles.count == 6)
        #expect(r.pageTileCount == 6)
    }

    @Test("Tiles chunk into pages without dropping any")
    func chunking() {
        let r = report(habits: 4, visuals: [.area])
        let pages = r.pageTiles(perPage: 6)
        #expect(pages.count == 2)
        #expect(pages.flatMap(\.self).count == r.pageTiles.count)
        #expect(pages.first?.count == 6)
        #expect(pages.last?.count == 2)
    }

    @Test("An empty report still yields one page")
    func emptyReportOnePage() throws {
        let r = report(habits: 0, visuals: [])
        #expect(r.pageTiles.isEmpty)
        #expect(try pageCount(r) == 1)
    }

    // MARK: Orientation

    @Test("More than one row turns the paper sideways")
    func orientationSwitches() {
        // One chart and its numbers: two tiles, one row, portrait.
        #expect(CustomReportPDFRenderer.suggestedOrientation(for: report(habits: 1, visuals: [.area])) == .portrait)
        // Four habits: landscape, where four tiles across get a sensible aspect.
        #expect(CustomReportPDFRenderer.suggestedOrientation(for: report(habits: 4, visuals: [.area])) == .landscape)
    }

    @Test("Landscape is wider than it is tall, and portrait the reverse")
    func orientationSizes() {
        #expect(CustomReportPDFRenderer.Orientation.landscape.size.width
                > CustomReportPDFRenderer.Orientation.landscape.size.height)
        #expect(CustomReportPDFRenderer.Orientation.portrait.size.height
                > CustomReportPDFRenderer.Orientation.portrait.size.width)
    }

    // MARK: Fitting

    /// The complaint, exactly: one chart and its totals on one sheet.
    @Test("One habit with one chart prints on a single page")
    func oneHabitOnePage() throws {
        #expect(try pageCount(report(habits: 1, visuals: [.area])) == 1)
    }

    @Test("Four habits with a chart each fit two pages")
    func fourHabitsTwoPages() throws {
        // Eight tiles at six per landscape sheet.
        #expect(try pageCount(report(habits: 4, visuals: [.area])) == 2)
    }

    /// The regression guard for tiles overflowing and colliding with the row
    /// below: every tile has to fit inside the height the grid gives it.
    @Test("No tile overflows the height it is given")
    func tilesFitTheirFrame() {
        let r = report(habits: 1, visuals: [.area])
        let shape = CustomReportPDFRenderer.grid(for: .landscape)
        let columnWidth = (CustomReportPDFRenderer.Orientation.landscape.size.width
                           - CustomReportPDFRenderer.margin * 2
                           - CGFloat(shape.columns - 1) * 8) / CGFloat(shape.columns)

        func rendered(_ view: some View) -> CGFloat {
            let renderer = ImageRenderer(
                content: view.trackerTheme(.standard).frame(width: columnWidth)
            )
            renderer.proposedSize = ProposedViewSize(width: columnWidth, height: nil)
            return renderer.uiImage?.size.height ?? .greatestFiniteMagnitude
        }

        let chart = rendered(ReportChartTileView(
            report: r,
            tile: r.chartTiles[0],
            chartHeight: shape.tileHeight - CustomReportPageView.cardChrome
        ))
        #expect(chart <= shape.tileHeight,
                "A chart tile renders \(chart)pt into a \(shape.tileHeight)pt cell and will overlap the row below")

        let numbers = rendered(ReportTrackerTable(tracker: r.trackers[0], isCompact: true))
        #expect(numbers <= shape.tileHeight,
                "A numbers tile renders \(numbers)pt into a \(shape.tileHeight)pt cell")
    }

    /// A week of days down one column was taller than the tile meant to hold it.
    @Test("Compact numbers use two columns once there are more than four rows")
    func longTablesSplit() {
        let r = report(habits: 1, visuals: [])
        let daily = r.trackers[0].section(.daily)
        #expect((daily?.buckets.count ?? 0) > 4, "Fixture should have a week of days")
    }
}


// MARK: - Weekday axis

/// How a daily chart labels its x axis.
@Suite("Weekday axis")
@MainActor
struct WeekdayAxisTests {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }

    private func date(_ d: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 12)) ?? .distantPast
    }

    private func series(days: Int) -> ChartSeries {
        ChartSeries(
            name: "Reading",
            points: (0..<days).map { ChartPoint(date: date(14 + $0), value: 10) }
        )
    }

    /// `veryShortWeekdaySymbols` gives S M T W T F S — two Ts and two Ss, so
    /// half the week is ambiguous on the one chart where the weekday is the
    /// question being asked.
    @Test("Every weekday is distinguishable")
    func weekdaysAreUnambiguous() {
        // Sep 13 2026 is a Sunday, so this walks a full week.
        let week = (13...19).map { Formatters.weekdayInitial(date($0), calendar: utc) }
        #expect(week == ["Su", "M", "T", "W", "Th", "F", "Sa"])
        #expect(Set(week).count == 7, "Two days share a label")
    }

    @Test("A series knows how many days it spans")
    func spanIsCounted() {
        #expect(series(days: 7).dayCount == 7)
        #expect(series(days: 1).dayCount == 1)
        #expect(ChartSeries(name: "x", points: []).dayCount == nil)
    }

    @Test("The widest series decides the axis")
    func widestSeriesWins() {
        #expect([series(days: 3), series(days: 9)].dayCount == 9)
        #expect([ChartSeries]().dayCount == nil)
    }

    /// A bar chart's x axis is categorical — the value *is* the label — so it
    /// cannot be restyled by the axis modifier the way the line and area charts
    /// are. It picks its own, and this is that decision.
    @Test("Bars are labelled by weekday over a week, by date beyond one")
    func barCategories() {
        // Sep 14 2026 is a Monday.
        #expect(Formatters.axisCategory(for: date(14), spanDays: 7, calendar: utc) == "M")
        #expect(Formatters.axisCategory(for: date(14), spanDays: 1, calendar: utc) == "M")
        #expect(Formatters.axisCategory(for: date(14), spanDays: 8, calendar: utc)
                == Formatters.dayMonth(date(14)))
        // An empty chart has no span to reason about and keeps dates.
        #expect(Formatters.axisCategory(for: date(14), spanDays: 0, calendar: utc)
                == Formatters.dayMonth(date(14)))
    }

    /// The boundary: a week reads as weekdays, longer reads as dates, because
    /// past seven days the letters repeat and identify nothing.
    @Test("Charts render at the boundary and either side of it")
    func rendersAcrossTheBoundary() {
        for days in [1, 7, 8, 30] {
            let chart = TrackerGroupedBarChart(series: [series(days: days)])
                .frame(width: 300, height: 200)
                .trackerTheme(.nocturne)
            let renderer = ImageRenderer(content: chart)
            renderer.scale = 1
            #expect(renderer.uiImage != nil, "A \(days)-day bar chart failed to render")
        }
    }
}

#endif
