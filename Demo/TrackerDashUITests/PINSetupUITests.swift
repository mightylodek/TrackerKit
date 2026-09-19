import XCTest

/// The enter-then-confirm flow for setting a PIN.
///
/// Reported from the device on first contact: entering a correct first PIN
/// showed "Wrong PIN — 99 attempts left" in red *and* "Enter it once more" at
/// the same time. The setup flow had no way to say "accepted, keep going", so it
/// returned `.incorrect(remainingAttempts: 99)` to mean it. No unit test could
/// see this — the bug was entirely in view logic.
final class PINSetupUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TKDEMO_PINSETUP"] = "1"
        app.launch()
        return app
    }

    private func enter(_ pin: String, in app: XCUIApplication) {
        for digit in pin {
            app.buttons[String(digit)].tap()
        }
    }

    func testFirstEntryIsAcceptedWithoutAnError() {
        let app = launch()
        XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 30), "Pad never appeared")

        enter("1379", in: app)

        XCTAssertTrue(
            app.staticTexts["Confirm your PIN"].waitForExistence(timeout: 5),
            "A correct first entry did not advance to the confirm step"
        )
        // The specific regression: a red failure shown on a good entry.
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Wrong PIN'")).element.exists,
            "A correct first entry still reports 'Wrong PIN'"
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'attempts left'")).element.exists,
            "The setup flow is still showing an attempt countdown"
        )
    }

    func testMatchingEntriesSetThePIN() {
        let app = launch()
        XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 30))
        enter("1379", in: app)
        XCTAssertTrue(app.staticTexts["Confirm your PIN"].waitForExistence(timeout: 5))
        enter("1379", in: app)

        XCTAssertTrue(
            app.staticTexts["pinsetup.result"].waitForExistence(timeout: 5),
            "Two matching entries did not complete setup"
        )
    }

    func testMismatchStartsOverWithAnExplanation() {
        let app = launch()
        XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 30))
        enter("1379", in: app)
        XCTAssertTrue(app.staticTexts["Confirm your PIN"].waitForExistence(timeout: 5))
        enter("2468", in: app)

        XCTAssertTrue(
            app.staticTexts["Those didn't match. Start again."].waitForExistence(timeout: 5),
            "A mismatch did not explain itself"
        )
        XCTAssertTrue(
            app.staticTexts["Choose a PIN"].waitForExistence(timeout: 5),
            "A mismatch did not return to the first step"
        )
    }

    /// The owner's call, not ours: warn once and carry on.
    func testAGuessablePINIsAllowed() {
        let app = launch()
        XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 30))
        enter("1234", in: app)

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'easy guess'")).element
                .waitForExistence(timeout: 5),
            "No caution shown for a guessable PIN"
        )
        XCTAssertTrue(
            app.staticTexts["Confirm your PIN"].exists,
            "A guessable PIN was blocked rather than allowed"
        )

        enter("1234", in: app)
        XCTAssertTrue(
            app.staticTexts["pinsetup.result"].waitForExistence(timeout: 5),
            "A guessable PIN could not be set even after the warning"
        )
    }

    /// Reported from the device as "there is also no delete button" — it existed,
    /// drawn as a bare glyph with no key background, so it read as empty space.
    func testDeleteRemovesADigit() {
        let app = launch()
        XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 30))

        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.exists, "No delete key on the pad")

        enter("137", in: app)
        XCTAssertTrue(delete.isHittable, "Delete key is not tappable with digits entered")
        delete.tap()

        // Three entered, one removed, so a fourth digit must not complete the PIN.
        enter("9", in: app)
        XCTAssertFalse(
            app.staticTexts["Confirm your PIN"].waitForExistence(timeout: 3),
            "Delete did not remove a digit — the entry completed a digit early"
        )
    }
}
