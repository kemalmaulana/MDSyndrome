import XCTest

/// Xcode's accessibility audit on the document window: contrast, hit regions, element descriptions and clipped text.
final class AccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-NSShowAppCentricOpenPanelInsteadOfUntitledFile", "NO"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    @MainActor
    func testDocumentWindowPassesTheAccessibilityAudit() throws {
        let editor = app.textViews["markdown-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("# Title\n\nSome *text* and a [link](https://example.com).\n\n- one\n- two")
        XCTAssertTrue(app.staticTexts["Title"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }
}
