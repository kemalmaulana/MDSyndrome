import XCTest

/// End-to-end: the outline lists the headings and opens with ⌃⌘S or its toolbar button, and the View menu carries
/// the switch for scrolling the panes together.
final class NavigationUITests: XCTestCase {
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

    private var editor: XCUIElement { app.textViews["markdown-editor"].firstMatch }
    private var outline: XCUIElement { app.descendants(matching: .any).matching(identifier: "outline-sidebar").firstMatch }

    @MainActor
    private func typeHeadings() {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("# First\n\ntext\n\n## Second\n\ntext")
        XCTAssertTrue(app.staticTexts["Second"].waitForExistence(timeout: 5), "the preview shows the headings")
    }

    @MainActor
    func testTheOutlineOpensWithTheShortcutAndListsTheHeadings() throws {
        typeHeadings()
        XCTAssertFalse(outline.exists, "the outline is closed until asked for")
        app.typeKey("s", modifierFlags: [.control, .command])
        XCTAssertTrue(outline.waitForExistence(timeout: 5))
        XCTAssertTrue(outline.staticTexts["First"].waitForExistence(timeout: 5))
        XCTAssertTrue(outline.staticTexts["Second"].exists)
        app.typeKey("s", modifierFlags: [.control, .command])
        XCTAssertTrue(outline.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testTheToolbarButtonTogglesTheOutline() throws {
        typeHeadings()
        let button = app.buttons["outline-toggle"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
        XCTAssertTrue(outline.waitForExistence(timeout: 5))
        button.click()
        XCTAssertTrue(outline.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testTheViewMenuHasTheSwitchForScrollingTogether() throws {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["View"].click()
        XCTAssertTrue(app.menuItems["Scroll Editor and Preview Together"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Show Outline"].exists || app.menuItems["Hide Outline"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }
}
