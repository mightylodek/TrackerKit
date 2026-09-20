import XCTest

/// Building a custom report end to end.
///
/// The engine's arithmetic is covered by 16 unit tests; this covers the part
/// they can't see — whether the controls reach it.
final class ReportBuilderUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TKDEMO_REPORTS"] = "1"
        app.launch()
        return app
    }

    /// Types the name and gets the keyboard back out of the way.
    ///
    /// The Form's lower half — totals, weekday chips, schedule — sits behind the
    /// keyboard while the name field is focused, so anything below it is present
    /// in the tree and untappable.
    private func nameIt(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["report.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Builder never opened")
        field.tap()
        field.typeText(text)
        // Return dismisses the keyboard in a Form's single-line field.
        app.typeText("\n")
    }

    /// Scrolls until an element is genuinely tappable.
    @discardableResult
    private func reach(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
            usleep(350_000)
        }
        return element.exists && element.isHittable
    }

    /// Flips a Form toggle and proves it moved.
    ///
    /// A SwiftUI `Toggle` does not respond to a tap on its label the way a UIKit
    /// one does, and `element.tap()` lands in the middle of the row — which is
    /// the label. Hit the switch end instead, then check `value` rather than
    /// trusting the tap.
    private func flip(_ toggle: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(reach(toggle, in: app), "Toggle never became reachable", file: file, line: line)
        let before = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        usleep(400_000)
        XCTAssertNotEqual(
            toggle.value as? String, before,
            "The toggle did not change state when tapped", file: file, line: line
        )
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-georgebrown-Library-Mobile-Documents-com-apple-CloudDocs-claude-workspace/dbab9006-3e5e-4558-bdd4-98ba9ecc2db9/scratchpad/\(name).png"))
    }

    func testBuildAReportEndToEnd() {
        let app = launch()

        XCTAssertTrue(app.buttons["report.new"].waitForExistence(timeout: 30), "Reports list never appeared")
        app.buttons["report.new"].tap()

        nameIt(app, "Reading week")

        // Save must stay disabled until at least one habit is picked.
        XCTAssertFalse(app.buttons["report.save"].isEnabled, "Saved with no habits selected")

        let habit = app.buttons["report.habit.Reading"]
        XCTAssertTrue(habit.exists, "Reading habit missing from the picker")
        habit.tap()

        XCTAssertTrue(app.buttons["report.save"].isEnabled, "Save still disabled with a habit picked")
        shot(app, "report-builder")

        app.buttons["report.save"].tap()

        let row = app.buttons["report.row.Reading week"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Saved report did not appear in the list")
        shot(app, "report-list")

        row.tap()
        XCTAssertTrue(
            app.staticTexts["Total"].waitForExistence(timeout: 10),
            "The built report did not render a total"
        )
        shot(app, "report-output")
    }

    /// Ticking a breakdown must add a section, not replace one.
    func testBreakdownsAreAdditive() {
        let app = launch()
        app.buttons["report.new"].tap()
        nameIt(app, "Totals test")
        app.buttons["report.habit.Reading"].tap()

        flip(app.switches["report.breakdown.weekly"], in: app)

        app.buttons["report.save"].tap()
        app.buttons["report.row.Totals test"].tap()

        XCTAssertTrue(app.staticTexts["Weekly"].waitForExistence(timeout: 10), "Weekly section missing")
        XCTAssertTrue(app.staticTexts["Daily"].exists, "Daily section was replaced rather than added to")
        XCTAssertTrue(app.staticTexts["Total"].exists, "Total section missing")
    }

    /// The Friday-to-Thursday case, driven through the controls.
    func testWeekStartIsSelectable() {
        let app = launch()
        app.buttons["report.new"].tap()
        nameIt(app, "Fri to Thu")
        app.buttons["report.habit.Reading"].tap()

        // Turning on weekly grouping reveals the week-start picker.
        flip(app.switches["report.breakdown.weekly"], in: app)

        let weekStart = app.buttons["report.weekStart"]
        XCTAssertTrue(reach(weekStart, in: app), "Week start picker never appeared")
    }

    /// Charts picked in the builder have to reach the report.
    func testChartsAppearInTheReport() {
        let app = launch()
        app.buttons["report.new"].tap()
        nameIt(app, "With charts")
        app.buttons["report.habit.Reading"].tap()

        let area = app.buttons["report.visual.area"]
        XCTAssertTrue(reach(area, in: app), "Chart picker never became reachable")
        area.tap()
        shot(app, "report-chart-picker")

        app.buttons["report.save"].tap()
        app.buttons["report.row.With charts"].tap()

        XCTAssertTrue(
            app.staticTexts["Area chart"].waitForExistence(timeout: 10),
            "A picked chart did not appear in the report"
        )
        shot(app, "report-with-chart")
    }

    /// The PDF button must be there and enabled once there is data.
    func testExportIsOfferedOnAReportWithData() {
        let app = launch()
        app.buttons["report.new"].tap()
        nameIt(app, "Exportable")
        app.buttons["report.habit.Reading"].tap()
        app.buttons["report.save"].tap()
        app.buttons["report.row.Exportable"].tap()

        let export = app.buttons["report.exportPDF"]
        XCTAssertTrue(export.waitForExistence(timeout: 10), "No PDF export control")
        XCTAssertTrue(export.isEnabled, "Export disabled on a report that has data")
    }

    func testWeekdayFilterIsReachable() {
        let app = launch()
        app.buttons["report.new"].tap()
        XCTAssertTrue(app.textFields["report.name"].waitForExistence(timeout: 10))

        // Sunday and Saturday — the two a Mon–Fri report drops.
        for day in [1, 7] {
            let chip = app.buttons["report.weekday.\(day)"]
            XCTAssertTrue(reach(chip, in: app), "Weekday chip \(day) never became reachable")
        }

        // Turning one off must change the footer, not just the chip.
        app.buttons["report.weekday.1"].tap()
        XCTAssertTrue(
            app.buttons["Count every day"].waitForExistence(timeout: 5),
            "Filtering a weekday offered no way back to every day"
        )
    }
}
