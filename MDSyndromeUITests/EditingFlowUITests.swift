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

    @MainActor
    func testTypingInPreviewModeDoesNotEditTheHiddenEditor() throws {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("keep")
        app.typeKey("3", modifierFlags: [.command, .option])   // preview only: editor hidden
        app.typeText("xyz ")
        app.typeKey("2", modifierFlags: [.command, .option])   // back to split
        XCTAssertEqual(editor.value as? String, "keep", "keystrokes in Preview mode must not reach the hidden editor")
    }

    @MainActor
    func testReturnContinuesAList() throws {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("- one\n")
        XCTAssertEqual(editor.value as? String, "- one\n- ")
    }

    @MainActor
    func testFormatShortcutWrapsTheSelection() throws {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("word")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("b", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, "**word**")
    }

    @MainActor
    func testTabIndentsAListItem() throws {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("- a")
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        XCTAssertEqual(editor.value as? String, "    - a")
    }

    @MainActor
    func testBracketsPairUp() throws {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("(")
        XCTAssertEqual(editor.value as? String, "()")
    }

    @MainActor
    func testUndoUpdatesThePreview() throws {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("# Gone soon")
        XCTAssertTrue(app.staticTexts["Gone soon"].waitForExistence(timeout: 5))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Gone soon"].waitForNonExistence(timeout: 5), "undo must reach the document, not only the text view")
    }

    @MainActor
    func testFormatAndThemeMenusExist() throws {
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["Format"].click()
        XCTAssertTrue(app.menuItems["Bold"].waitForExistence(timeout: 3))
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        app.menuBars.menuBarItems["View"].click()
        XCTAssertTrue(app.menuItems["Editor Theme"].waitForExistence(timeout: 3))
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    }
}
