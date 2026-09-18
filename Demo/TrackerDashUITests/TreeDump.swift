import XCTest

/// Diagnostic: prints the accessibility tree so element queries can be written
/// against what actually exists rather than what I assumed exists.
final class TreeDump: XCTestCase {
    func testDumpTree() {
        let app = XCUIApplication()
        app.launchEnvironment["TKDEMO_PROFILE"] = "Alex"
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        sleep(6)
        print("=====TREE-START=====")
        print(app.debugDescription)
        print("=====TREE-END=====")
    }
}
