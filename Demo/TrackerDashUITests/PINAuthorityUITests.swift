import XCTest

/// That the *screen* enforces the authority model, not just the model.
///
/// The model being right is not the same as the app being safe: the original
/// hole was a settings list that let any signed-in profile open any other
/// profile's editor and switch its PIN off. The logic below it was never asked.
///
/// The seeded demo is a family — Alex owns the device, Jordan and Sam are
/// members — so signing in as Jordan is signing in as a child.
final class PINAuthorityUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Scrolls until an element is genuinely on screen.
    ///
    /// Settings grows as features land, and "Reset all data" sits at the bottom
    /// of it — present in the tree, below the fold.
    @discardableResult
    private func reach(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
            usleep(350_000)
        }
        return element.exists
    }

    private func launch(as profile: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TKDEMO_PROFILE"] = profile
        app.launchEnvironment["TKDEMO_INMEMORY"] = "1"
        app.launchEnvironment["TKDEMO_TAB"] = "settings"
        // These are the shared-iPad rules. The product default is one profile
        // and no PIN, so this suite has to ask for the other mode.
        app.launchEnvironment["TKDEMO_SHARED"] = "1"
        app.launch()
        return app
    }

    func testAMemberCannotOpenAnotherProfile() {
        let app = launch(as: "Jordan")

        let owner = app.buttons["settings.profile.Alex"]
        XCTAssertTrue(owner.waitForExistence(timeout: 30), "Settings never listed the profiles")
        XCTAssertFalse(
            owner.isEnabled,
            "A member can still open the owner's profile editor — and switch their PIN off from it."
        )

        let sibling = app.buttons["settings.profile.Sam"]
        if sibling.exists {
            XCTAssertFalse(sibling.isEnabled, "A member can open another member's editor")
        }
    }

    func testAMemberCanStillOpenTheirOwn() {
        let app = launch(as: "Jordan")
        let own = app.buttons["settings.profile.Jordan"]
        XCTAssertTrue(own.waitForExistence(timeout: 30))
        XCTAssertTrue(own.isEnabled, "A member cannot manage their own profile")
    }

    func testAMemberCannotWipeTheDevice() {
        let app = launch(as: "Jordan")
        let reset = app.buttons["Reset all data"]
        XCTAssertTrue(reach(reset, in: app), "Reset control missing")
        XCTAssertFalse(
            reset.isEnabled,
            "A member can wipe every profile — which clears every PIN along with them."
        )
    }

    func testTheOwnerCanReachEveryProfile() {
        let app = launch(as: "Alex")

        for name in ["Alex", "Jordan", "Sam"] {
            let row = app.buttons["settings.profile.\(name)"]
            XCTAssertTrue(row.waitForExistence(timeout: 30), "\(name) missing from settings")
            XCTAssertTrue(row.isEnabled, "The owner cannot open \(name)'s profile")
        }
        let reset = app.buttons["Reset all data"]
        XCTAssertTrue(reach(reset, in: app), "Reset control missing")
        XCTAssertTrue(reset.isEnabled, "The owner cannot reset the device")
    }

    /// Tapping a profile must actually open its editor.
    ///
    /// It didn't: two `.sheet` modifiers were stacked on the same view, so only
    /// one survived and this tap did nothing at all, silently.
    func testTappingAProfileOpensItsEditor() {
        let app = launch(as: "Alex")
        let kid = app.buttons["settings.profile.Sam"]
        XCTAssertTrue(kid.waitForExistence(timeout: 30))
        kid.tap()

        XCTAssertTrue(
            app.textFields["profile.name"].waitForExistence(timeout: 10),
            "Tapping a profile did not open its editor"
        )
    }

    func testAddProfileStillOpens() {
        let app = launch(as: "Alex")
        let add = app.buttons["settings.addProfile"]
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        add.tap()
        XCTAssertTrue(
            app.textFields["profile.name"].waitForExistence(timeout: 10),
            "Add profile no longer opens the editor"
        )
    }

    /// An owner opening a member sees a reset, never a way to read or set the
    /// existing code.
    func testOwnerIsNotOfferedAWayToSetAnotherPIN() {
        let app = launch(as: "Alex")
        let kid = app.buttons["settings.profile.Sam"]
        XCTAssertTrue(kid.waitForExistence(timeout: 30))
        kid.tap()

        XCTAssertTrue(app.textFields["profile.name"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.buttons["profile.setPIN"].exists,
            "An owner is being offered a way to set someone else's PIN directly"
        )
    }
}
