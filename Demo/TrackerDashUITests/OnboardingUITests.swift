import XCTest

/// Tests the first-run wizard end to end.
///
/// A new profile is the one screen every user sees and no unit test can reach:
/// the wizard only presents when a real profile exists with nothing in it, and
/// an earlier `onAppear` trigger silently never fired because the profile was
/// selected a beat later. Only a launched app catches that.
final class OnboardingUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchEmptyProfile() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TKDEMO_ONBOARD"] = "1"
        app.launch()
        return app
    }

    func testWizardPresentsOnAnEmptyProfile() {
        let app = launchEmptyProfile()
        XCTAssertTrue(
            app.buttons["template.daily-habits"].waitForExistence(timeout: 30),
            "The wizard never presented on a profile with nothing in it."
        )
    }

    /// The whole point of the wizard: one pass leaves a usable app behind.
    func testTemplateCreatesTrackersAndADashboard() {
        let app = launchEmptyProfile()

        let template = app.buttons["template.daily-habits"]
        XCTAssertTrue(template.waitForExistence(timeout: 30), "Template row never appeared")
        template.tap()

        // Step two arrives with the recommended blueprints already ticked
        // (a template may hold optional ones that start off); confirm as-is.
        let confirm = app.buttons["onboarding.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "Confirm button never appeared")
        XCTAssertTrue(confirm.isEnabled, "Confirm was disabled on the default selection")
        confirm.tap()

        // The trackers the template promised are now on the dashboard...
        let reading = app.buttons["row.Reading"]
        XCTAssertTrue(reading.waitForExistence(timeout: 15), "Template did not create its trackers")

        // ...and so is the dashboard furniture, which proves the layout was
        // seeded too rather than the trackers landing on an empty screen.
        XCTAssertTrue(
            app.staticTexts["Where everything stands"].exists,
            "Template created trackers but no dashboard layout"
        )
    }

    /// Deselecting must actually subtract — a tick box that only looks ticked
    /// would quietly create trackers the user declined.
    func testDeselectingABlueprintSkipsThatTracker() {
        let app = launchEmptyProfile()

        let template = app.buttons["template.daily-habits"]
        XCTAssertTrue(template.waitForExistence(timeout: 30), "Template row never appeared")
        template.tap()

        let water = app.buttons["blueprint.Water"]
        XCTAssertTrue(water.waitForExistence(timeout: 10), "Blueprint row never appeared")
        water.tap()

        app.buttons["onboarding.confirm"].tap()

        XCTAssertTrue(
            app.buttons["row.Reading"].waitForExistence(timeout: 15),
            "Ticked trackers were not created"
        )
        XCTAssertFalse(
            app.buttons["row.Water"].exists,
            "A deselected blueprint was created anyway"
        )
    }

    /// Skipping must not loop: the app has to be usable without the wizard.
    func testSkipLeavesAUsableEmptyState() {
        let app = launchEmptyProfile()

        let skip = app.buttons["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 30), "Wizard never presented")
        skip.tap()

        XCTAssertFalse(
            app.buttons["template.daily-habits"].waitForExistence(timeout: 3),
            "The wizard re-presented itself after being dismissed"
        )
        XCTAssertTrue(
            app.buttons["empty.chooseTemplate"].exists,
            "No way back to the templates after skipping"
        )
    }
}

/// The cold start — no profiles, no trackers, nothing seeded.
///
/// Everything above starts from a profile that already exists. This is the path
/// a real first launch takes, and it was the one with a hole in it: the wizard
/// can only fire once a profile is selected, so profile creation has to hand off
/// to it rather than returning to a picker holding a single tile.
final class FirstLaunchUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TKDEMO_FRESH"] = "1"
        app.launch()
        return app
    }

    func testColdStartReachesADashboardWithoutABlindAlley() {
        let app = launchFresh()

        let create = app.buttons["welcome.createProfile"]
        XCTAssertTrue(create.waitForExistence(timeout: 30), "No welcome screen on a cold start")
        create.tap()

        let name = app.textFields["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "Profile name field never appeared")
        name.tap()
        name.typeText("Sam")

        app.buttons["profile.save"].tap()

        // The hand-off: creating the first profile must land in the wizard, not
        // back on a picker holding one tile.
        let template = app.buttons["template.daily-habits"]
        XCTAssertTrue(
            template.waitForExistence(timeout: 15),
            "Creating the first profile did not hand off to the wizard"
        )
        template.tap()

        let confirm = app.buttons["onboarding.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "Confirm never appeared")
        confirm.tap()

        XCTAssertTrue(
            app.buttons["row.Reading"].waitForExistence(timeout: 15),
            "Cold start never reached a populated dashboard"
        )
    }
}
