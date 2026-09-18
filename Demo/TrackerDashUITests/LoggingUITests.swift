import XCTest

/// Tests that actually tap.
///
/// The unit suite proves every view *draws*; none of it proves a tap *lands*.
/// That blind spot shipped a quick-log button that silently did nothing, so this
/// target exists to close it.
///
/// Assertions read the **row button's label** rather than an identifier on the
/// progress text. SwiftUI drops identifiers on `Text` nested inside a Button's
/// label and folds the text into the parent's accessibility label instead — so
/// the row is the reliable handle, and it already contains the number.
final class LoggingUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TKDEMO_PROFILE"] = "Alex"
        app.launch()
        return app
    }

    /// Screen Time is the first row, so it's on screen without scrolling.
    private let subject = "Screen Time"

    func testDashboardQuickLogChangesTheNumber() {
        let app = launchApp()

        let row = app.buttons["row.\(subject)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "\(subject) row never appeared")
        let before = row.label

        let plus = app.buttons["quickLog.\(subject)"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "Quick-log button not found")
        XCTAssertTrue(plus.isHittable, "Quick-log button exists but isn't hittable")
        plus.tap()

        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: row)
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(
                error,
                "Quick-log did not change the row. Was '\(before)', still '\(row.label)'."
            )
        }
    }

    func testTappingRowOpensDetail() {
        let app = launchApp()

        let row = app.buttons["row.\(subject)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()

        XCTAssertTrue(
            app.navigationBars[subject].waitForExistence(timeout: 10),
            "Tapping the row did not open the tracker's detail screen"
        )
    }

    /// The detail action bar is a separate code path from the dashboard button
    /// and can break independently.
    func testDetailQuickAddChangesTheValue() {
        let app = launchApp()

        let row = app.buttons["row.\(subject)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        XCTAssertTrue(app.navigationBars[subject].waitForExistence(timeout: 10))

        let actual = app.staticTexts["detail.actual"]
        XCTAssertTrue(actual.waitForExistence(timeout: 10), "Detail value never appeared")
        let before = actual.label

        let add = app.buttons["detail.quickAdd"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Detail quick-add not found")
        XCTAssertTrue(add.isHittable, "Detail quick-add exists but isn't hittable")
        add.tap()

        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: actual)
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(
                error,
                "Detail quick-add did not change the value. Was '\(before)', still '\(actual.label)'."
            )
        }
    }
}
