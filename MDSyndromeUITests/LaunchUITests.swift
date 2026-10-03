import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor
    func testLaunchOpensUntitledDocumentWithEditor() throws {
        let app = XCUIApplication()
        // Start with an untitled document instead of the Open panel.
        app.launchArguments += ["-NSShowAppCentricOpenPanelInsteadOfUntitledFile", "NO"]
        app.launch()
        XCTAssertTrue(app.textViews["markdown-editor"].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
    }
}
