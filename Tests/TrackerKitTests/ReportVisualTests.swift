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
