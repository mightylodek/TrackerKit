import XCTest

/// Proves data survives the app dying.
///
/// The demo ran in-memory for most of its life, so the on-disk SwiftData path —
/// the one every real user is on — had never executed at all. Nothing in the
/// unit suite touches it: those tests build their own in-memory container.
///
/// Deliberately does **not** set `TKDEMO_INMEMORY`, so it exercises the real
/// store. Assertions are relative (value after relaunch == value before), so the
/// test stays repeatable as the on-disk data accumulates between runs.
final class PersistenceUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchPersistent() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TKDEMO_PROFILE"] = "Alex"
        app.launch()
        return app
    }

    private func scrollIntoReach(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
            usleep(400_000)
        }
        return element.exists && element.isHittable
    }

    func testALoggedEntrySurvivesRelaunch() {
        let subject = "Water"
        var app = launchPersistent()

        let row = app.buttons["row.\(subject)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "\(subject) row never appeared")
        let before = row.label

        let plus = app.buttons["quickLog.\(subject)"]
        XCTAssertTrue(scrollIntoReach(plus, in: app), "Quick-log never became tappable")
        plus.tap()

        // Wait for the log to actually register before killing the app — this is
        // the window where an unsaved context would lose the write.
        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: row)
        waitForExpectations(timeout: 10)
        let afterLogging = row.label

        app.terminate()
        XCTAssertEqual(app.state, .notRunning, "App did not terminate")

        app = launchPersistent()
        let rowAgain = app.buttons["row.\(subject)"]
        XCTAssertTrue(rowAgain.waitForExistence(timeout: 30), "Row missing after relaunch")

        XCTAssertEqual(
            rowAgain.label, afterLogging,
            """
            The logged entry did not survive relaunch. \
            Was '\(afterLogging)' before the app was killed, '\(rowAgain.label)' after. \
            If this reads like the original seeded value, the write never reached disk.
            """
        )
    }

    /// The store must not re-seed over data that is already there.
    func testSeedingDoesNotDuplicateOnSecondLaunch() {
        var app = launchPersistent()
        XCTAssertTrue(app.buttons["row.Water"].waitForExistence(timeout: 30))
        let firstCount = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'row.'")
        ).count
        XCTAssertGreaterThan(firstCount, 0, "No tracker rows found at all")

        app.terminate()
        app = launchPersistent()
        XCTAssertTrue(app.buttons["row.Water"].waitForExistence(timeout: 30))
        let secondCount = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'row.'")
        ).count

        XCTAssertEqual(
            secondCount, firstCount,
            "Tracker count changed across relaunch (\(firstCount) → \(secondCount)) — the sample data is seeding on top of itself."
        )
    }
}
