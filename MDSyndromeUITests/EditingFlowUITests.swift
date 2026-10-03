import XCTest

/// End-to-end: new document → type markdown → preview updates → layout modes → undo → unsaved state.
final class EditingFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Start with an untitled document instead of the Open panel.
        app.launchArguments += ["-NSShowAppCentricOpenPanelInsteadOfUntitledFile", "NO"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private var editor: XCUIElement { app.textViews["markdown-editor"].firstMatch }

    @MainActor
    func testTypingUpdatesPreview() throws {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("# Hello MDSyndrome\n\nSome *styled* text.")
        XCTAssertTrue(app.staticTexts["Hello MDSyndrome"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Some styled text."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLayoutShortcutsHideAndShowPanes() throws {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("# Modes")
        XCTAssertTrue(app.staticTexts["Modes"].waitForExistence(timeout: 5))

        app.typeKey("1", modifierFlags: [.command, .option])   // editor only
        XCTAssertTrue(app.staticTexts["Modes"].waitForNonExistence(timeout: 3))

        app.typeKey("3", modifierFlags: [.command, .option])   // preview only
        XCTAssertTrue(app.staticTexts["Modes"].waitForExistence(timeout: 3))

        app.typeKey("2", modifierFlags: [.command, .option])   // split
        XCTAssertTrue(editor.isHittable)
    }

    @MainActor
    func testUndoRevertsTyping() throws {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("undo me")
        XCTAssertEqual(editor.value as? String, "undo me")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, "", "one ⌘Z removes the typed run, and only once")
    }

    @MainActor
    func testTypingMarksDocumentEdited() throws {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("dirty")
        app.typeKey("w", modifierFlags: .command)
        // An edited document must ask before closing; a clean one closes silently.
        // (On macOS 26+ the window title does not show "Edited", so check the sheet.)
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5), "closing an edited document shows a save/keep sheet")
    }
}
