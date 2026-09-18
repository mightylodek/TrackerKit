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

    private let subject = "Screen Time"

    /// Brings an element clear of the floating tab bar.
    ///
    /// The tab bar floats over the bottom ~83pt and content scrolls beneath it,
    /// so an element can exist, be on screen, and still not be tappable. Real
    /// users scroll; so does this.
    @discardableResult
    private func scrollIntoReach(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
            usleep(400_000)
        }
        return element.exists && element.isHittable
    }

    func testDashboardQuickLogChangesTheNumber() {
        let app = launchApp()

        let row = app.buttons["row.\(subject)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "\(subject) row never appeared")
        let before = row.label

        let plus = app.buttons["quickLog.\(subject)"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "Quick-log button not found")
        XCTAssertTrue(scrollIntoReach(plus, in: app), "Quick-log button never became tappable")
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

// MARK: - Undo

extension LoggingUITests {

    /// The whole point of undo is the accidental double-tap, so the test is the
    /// accidental double-tap.
    func testUndoReversesAnAccidentalDoubleTap() {
        let app = launchApp()

        let row = app.buttons["row.\(subject)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        let original = row.label

        let plus = app.buttons["quickLog.\(subject)"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollIntoReach(plus, in: app))
        plus.tap()

        // Wait for the row to reflect the first tap before slipping.
        let firstChange = NSPredicate(format: "label != %@", original)
        expectation(for: firstChange, evaluatedWith: row)
        waitForExpectations(timeout: 10)
        let afterOne = row.label

        plus.tap()  // the slip
        let secondChange = NSPredicate(format: "label != %@", afterOne)
        expectation(for: secondChange, evaluatedWith: row)
        waitForExpectations(timeout: 10)

        let undo = app.buttons["undo.button"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "Undo was never offered")
        XCTAssertTrue(undo.isHittable, "Undo is offered but not hittable")
        undo.tap()

        let backToOne = NSPredicate(format: "label == %@", afterOne)
        expectation(for: backToOne, evaluatedWith: row)
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(
                error,
                "Undo did not reverse the slip. Expected '\(afterOne)', got '\(row.label)'."
            )
        }
    }

    /// The offer must not become permanent furniture on the screen.
    func testUndoOfferExpires() {
        let app = launchApp()

        let plus = app.buttons["quickLog.\(subject)"]
        XCTAssertTrue(plus.waitForExistence(timeout: 30))
        XCTAssertTrue(scrollIntoReach(plus, in: app))
        plus.tap()

        let undo = app.buttons["undo.button"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "Undo was never offered")

        // Offer duration is 6s; allow generous slack for a loaded machine.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: undo)
        waitForExpectations(timeout: 25) { error in
            XCTAssertNil(error, "Undo offer never expired")
        }
    }
}

// MARK: - Repeated logging

extension LoggingUITests {

    /// Three taps for a thirty-minute session.
    ///
    /// This failed before the undo bar moved: the first tap put an undo offer
    /// directly on top of the Add button, so taps two and three landed on the
    /// undo bar instead. The action bar must not move or become unreachable
    /// while an undo is being offered.
    func testDetailAddCanBeTappedRepeatedly() {
        let app = launchApp()

        let row = app.buttons["row.\(subject)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        XCTAssertTrue(app.navigationBars[subject].waitForExistence(timeout: 10))

        let actual = app.staticTexts["detail.actual"]
        XCTAssertTrue(actual.waitForExistence(timeout: 10))
        let start = actual.label

        let add = app.buttons["detail.quickAdd"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))

        let firstFrame = add.frame
        var seen: [String] = [start]

        for tap in 1...3 {
            XCTAssertTrue(
                add.isHittable,
                "Add button became unreachable on tap \(tap) — something is covering it"
            )
            add.tap()

            let previous = seen.last!
            let changed = NSPredicate(format: "label != %@", previous)
            expectation(for: changed, evaluatedWith: actual)
            waitForExpectations(timeout: 10) { error in
                XCTAssertNil(error, "Tap \(tap) did not register (still '\(actual.label)')")
            }
            seen.append(actual.label)
        }

        // The button must not have shifted under the finger between taps.
        XCTAssertEqual(
            add.frame, firstFrame,
            "Add button moved while undo was offered — it must stay put"
        )

        XCTAssertEqual(Set(seen).count, seen.count, "Each tap should produce a distinct value")
    }
}
