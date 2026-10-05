import AppKit
import SwiftUI
import Testing
@testable import EditorKit

/// The real editor stack — scroll view, MarkdownTextView, coordinator, highlighter — in a window,
/// driven through the same entry points the keyboard and menus use.
@MainActor
private final class EditorHarness {
    final class Box {
        var value: String
        var writes = 0
        init(_ value: String) { self.value = value }
    }

    let box: Box
    let coordinator: EditorCoordinator
    let controller = EditorController()
    let scrollView: NSScrollView
    let textView: MarkdownTextView
    let window: NSWindow

    init(_ initial: String = "", theme: EditorTheme = .tomorrowPlus, configuration: EditorConfiguration = .macDownDefaults) {
        _ = NSApplication.shared
        box = Box(initial)
        let binding = Binding(get: { [box] in box.value }, set: { [box] in box.value = $0; box.writes += 1 })
        coordinator = EditorCoordinator(text: binding)
        (scrollView, textView) = MarkdownEditorView.makeViews()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scrollView
        coordinator.attach(to: textView, scrollView: scrollView, theme: theme, configuration: configuration, controller: controller)
        coordinator.setText(initial)
        window.makeFirstResponder(textView)
    }

    /// Text with a caret `‸` or a selection `«…»`, like the transform tests.
    func load(_ marked: String) {
        let ns = marked as NSString
        let caret = ns.range(of: "‸")
        if caret.location != NSNotFound {
            coordinator.setText(ns.replacingCharacters(in: caret, with: ""))
            textView.setSelectedRange(NSRange(location: caret.location, length: 0))
        } else {
            let open = ns.range(of: "«"), close = ns.range(of: "»")
            coordinator.setText(ns.replacingCharacters(in: close, with: "").replacingOccurrences(of: "«", with: ""))
            textView.setSelectedRange(NSRange(location: open.location, length: close.location - open.location - 1))
        }
    }

    /// The text with the selection marked, for readable assertions.
    var marked: String {
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        if selection.length == 0 { return ns.replacingCharacters(in: selection, with: "‸") }
        return ns.replacingCharacters(in: selection, with: "«" + ns.substring(with: selection) + "»")
    }

    func type(_ text: String) {
        for character in text { textView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0)) }
    }
}

@MainActor
@Suite(.requiresWindowServer) struct EditorBindingTests {
    @Test func externalTextIsShownWithoutEchoingBack() {
        let editor = EditorHarness()
        editor.coordinator.setText("# Loaded")
        #expect(editor.textView.string == "# Loaded")
        #expect(editor.box.writes == 0)
    }

    @Test func userTypingUpdatesBinding() {
        let editor = EditorHarness("ab")
        editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        editor.type("c")
        #expect(editor.box.value == "abc")
        #expect(editor.box.writes == 1)
    }

    @Test func externalTextClampsSelection() {
        let editor = EditorHarness("long text here")
        editor.textView.setSelectedRange(NSRange(location: 14, length: 0))
        editor.coordinator.setText("short")
        #expect(editor.textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test func replacingTheTextFromOutsideDropsStaleUndoSteps() {
        let editor = EditorHarness("short")
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        editor.type(" and a lot more typed text")
        #expect(editor.textView.undoManager?.canUndo == true)
        editor.coordinator.setText("new")
        #expect(editor.textView.undoManager?.canUndo == false, "undoing into replaced text could cut it at a stale range")
        editor.textView.undoManager?.undo()   // must not crash or change anything
        #expect(editor.textView.string == "new")
    }

    @Test func handingBackTheSameStringKeepsTheSelection() {
        let editor = EditorHarness("hello world")
        editor.textView.setSelectedRange(NSRange(location: 3, length: 4))
        editor.type("!")
        editor.coordinator.setText(editor.box.value)   // what SwiftUI does after every binding write
        #expect(editor.textView.string == "hel!orld")
        #expect(editor.textView.selectedRange() == NSRange(location: 4, length: 0))
    }

    @Test func plainTextSettingsAndDefaultFont() {
        let editor = EditorHarness("x")
        let textView = editor.textView
        #expect(!textView.isRichText)
        #expect(textView.allowsUndo)
        #expect(textView.usesFindBar)
        #expect(!textView.isAutomaticQuoteSubstitutionEnabled)
        #expect(!textView.isAutomaticLinkDetectionEnabled)
        #expect(textView.textContainerInset == NSSize(width: 15, height: 30))
        let font = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontName == "Menlo-Regular")
        #expect(font?.pointSize == 14)
    }

    @Test func configurationChangeRestylesExistingText() {
        let editor = EditorHarness("x")
        var bigger = EditorConfiguration.macDownDefaults
        bigger.fontSize = 20
        editor.coordinator.apply(theme: .tomorrowPlus, configuration: bigger)
        #expect((editor.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 20)
    }

    @Test func hidingTheEditorResignsFocusAndShowingRestoresIt() {
        let editor = EditorHarness("text")
        #expect(editor.window.firstResponder === editor.textView)

        editor.coordinator.setHidden(true, scrollView: editor.scrollView)
        #expect(editor.scrollView.isHidden)
        #expect(editor.window.firstResponder !== editor.textView, "a hidden editor must not receive keystrokes")

        editor.coordinator.setHidden(false, scrollView: editor.scrollView)
        #expect(!editor.scrollView.isHidden)
        #expect(editor.window.firstResponder === editor.textView)
    }

    @Test func findActionsOpenTheFindBar() {
        let editor = EditorHarness("find me, find me")
        #expect(!editor.scrollView.isFindBarVisible)
        editor.controller.find(.show)
        #expect(editor.scrollView.isFindBarVisible, "⌘F must reach the editor's find bar")
        editor.controller.find(.showReplace)
        #expect(editor.scrollView.isFindBarVisible)
    }

    @Test func theControllerKnowsWhenTheEditorHasTheKeyboard() {
        let editor = EditorHarness("text")
        var focusEvents = 0
        editor.controller.onFocus = { focusEvents += 1 }
        #expect(editor.controller.hasFocus)
        editor.window.makeFirstResponder(nil)
        #expect(!editor.controller.hasFocus)
        #expect(editor.window.makeFirstResponder(editor.textView))
        #expect(editor.controller.hasFocus)
        #expect(focusEvents == 1, "taking focus is reported once, so the window can follow the user between panes")
    }

    @Test func typingInTheEditorCountsAsWorkingInIt() throws {
        // Clicking the preview leaves the keyboard in the editor, so a key press there has to say so.
        // (A click does too, through mouseDown, which is not driven here: NSTextView tracks the mouse in a loop.)
        let editor = EditorHarness("text")
        var events = 0
        editor.controller.onFocus = { events += 1 }
        let typed = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: editor.window.windowNumber,
                                                  context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        editor.textView.keyDown(with: typed)
        #expect(events == 1)
    }

    @Test func theFindBarCountsAsTheEditorHavingFocus() {
        let editor = EditorHarness("find me")
        editor.controller.find(.show)
        #expect(editor.scrollView.isFindBarVisible)
        editor.window.makeFirstResponder(editor.scrollView.findBarView?.subviews.first)
        // Wherever the first responder is inside the editor's scroll view, Find stays with the editor.
        if let responder = editor.window.firstResponder as? NSView, responder !== editor.textView {
            #expect(editor.controller.hasFocus)
        }
    }

    @Test func jumpToSelectionDoesNotMoveTheSelection() {
        let editor = EditorHarness("a\nb\nc")
        editor.textView.setSelectedRange(NSRange(location: 2, length: 1))
        editor.controller.jumpToSelection()
        #expect(editor.textView.selectedRange() == NSRange(location: 2, length: 1))
    }

    @Test func typedTextIsColouredAsYouType() {
        let editor = EditorHarness()
        editor.type("# Title")
        let heading = editorColor(EditorTheme.tomorrowPlus.style(for: .heading1)?.color)
        #expect(editor.textView.textStorage?.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor == heading)
    }
}

@MainActor
@Suite(.requiresWindowServer) struct EditorThemeApplicationTests {
    @Test func themeColoursReachTheView() {
        let editor = EditorHarness("# Hi", theme: .solarizedDark)
        let theme = EditorTheme.solarizedDark
        #expect(editor.textView.backgroundColor == editorColor(theme.background))
        #expect(editor.textView.insertionPointColor == editorColor(theme.caret))
        #expect(editor.textView.selectedTextAttributes[.backgroundColor] as? NSColor == editorColor(theme.selectionBackground))
        #expect(editor.scrollView.backgroundColor == editorColor(theme.background))
        #expect(editor.scrollView.appearance?.name == .darkAqua)
    }

    @Test func switchingThemesRecoloursTextAndChrome() {
        let editor = EditorHarness("# Hi\n")
        editor.coordinator.apply(theme: .solarizedLight, configuration: .macDownDefaults)
        let light = EditorTheme.solarizedLight
        #expect(editor.textView.backgroundColor == editorColor(light.background))
        #expect(editor.scrollView.appearance?.name == .aqua)
        #expect(editor.textView.textStorage?.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor == editorColor(light.style(for: .heading1)?.color))
        #expect(editor.textView.typingAttributes[.foregroundColor] as? NSColor == editorColor(light.foreground))
    }

    @Test func behaviourFlagsDoNotRecolour() {
        let editor = EditorHarness("# Hi\n")
        let storage = editor.textView.textStorage
        let marker = NSColor(srgbRed: 0.5, green: 0.1, blue: 0.9, alpha: 1)
        storage?.addAttribute(.backgroundColor, value: marker, range: NSRange(location: 0, length: 2))
        var configuration = EditorConfiguration.macDownDefaults
        configuration.autoPair = false
        editor.coordinator.apply(theme: .tomorrowPlus, configuration: configuration)
        #expect(storage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor == marker, "turning a typing switch off must not re-colour")
        #expect(!editor.textView.behavior.autoPair)
    }
}

@MainActor
@Suite(.requiresWindowServer) struct EditorKeyboardTests {
    @Test func returnContinuesAList() {
        let editor = EditorHarness()
        editor.load("- one‸")
        editor.textView.insertNewline(nil)
        #expect(editor.marked == "- one\n- ‸")
        #expect(editor.box.value == "- one\n- ")
    }

    @Test func returnOnAnEmptyItemEndsTheList() {
        let editor = EditorHarness()
        editor.load("- one\n- ‸")
        editor.textView.insertNewline(nil)
        #expect(editor.marked == "- one\n‸")
    }

    @Test func returnRenumbersFollowingItems() {
        let editor = EditorHarness()
        editor.load("1. a‸\n2. b")
        editor.textView.insertNewline(nil)
        #expect(editor.marked == "1. a\n2. ‸\n3. b")
        var configuration = EditorConfiguration.macDownDefaults
        configuration.renumberLists = false
        editor.coordinator.apply(theme: .tomorrowPlus, configuration: configuration)
        editor.load("1. a‸\n2. b")
        editor.textView.insertNewline(nil)
        #expect(editor.marked == "1. a\n2. ‸\n2. b")
    }

    @Test func returnIsPlainWhenListContinuationIsOff() {
        var configuration = EditorConfiguration.macDownDefaults
        configuration.continueLists = false
        let editor = EditorHarness(configuration: configuration)
        editor.load("- one‸")
        editor.textView.insertNewline(nil)
        #expect(editor.marked == "- one\n‸")
    }

    @Test func returnInsideACodeFenceIsPlain() {
        let editor = EditorHarness()
        editor.load("```\n- not a list‸\n```")
        editor.textView.insertNewline(nil)
        #expect(editor.marked == "```\n- not a list\n‸\n```")
    }

    @Test func returnWhileComposingTextIsLeftToTheInputMethod() {
        let editor = EditorHarness()
        editor.load("- one‸")
        editor.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.textView.hasMarkedText())
        editor.textView.insertNewline(nil)
        #expect(!editor.textView.string.contains("\n- "), "list continuation must not fire during composition")
    }

    @Test func continuingAListIsOneUndoStep() {
        let editor = EditorHarness()
        editor.load("- one‸")
        editor.textView.insertNewline(nil)
        editor.textView.undoManager?.undo()
        #expect(editor.textView.string == "- one")
        #expect(editor.box.value == "- one")
    }

    @Test func tabIndentsAListItemAndBacktabOutdents() {
        let editor = EditorHarness()
        editor.load("- a‸")
        editor.textView.insertTab(nil)
        #expect(editor.marked == "    - a‸")
        editor.textView.insertBacktab(nil)
        #expect(editor.marked == "- a‸")
        editor.textView.insertBacktab(nil)   // nothing left to remove
        #expect(editor.marked == "- a‸")
    }

    @Test func tabInsertsTheIndentUnitInPlainText() {
        var configuration = EditorConfiguration.macDownDefaults
        configuration.indentUnit = "\t"
        let editor = EditorHarness(configuration: configuration)
        editor.load("ab‸c")
        editor.textView.insertTab(nil)
        #expect(editor.marked == "ab\t‸c")
    }

    @Test func tabIndentsEverySelectedLine() {
        let editor = EditorHarness()
        editor.load("«one\ntwo»")
        editor.textView.insertTab(nil)
        #expect(editor.marked == "«    one\n    two»")
    }

    @Test func typingAnOpenerInsertsThePairAndTypingTheCloserSkipsOver() {
        let editor = EditorHarness()
        editor.type("(")
        #expect(editor.marked == "(‸)")
        editor.type("x)")
        #expect(editor.marked == "(x)‸")
        #expect(editor.box.value == "(x)")
    }

    @Test func typingThreeBackticksGivesAFenceNotAnExtraPair() {
        let editor = EditorHarness()
        editor.type("```")
        #expect(editor.textView.string == "```")
        #expect(editor.marked == "```‸")
    }

    @Test func backspaceDeletesAnEmptyPair() {
        let editor = EditorHarness()
        editor.type("[")
        editor.textView.deleteBackward(nil)
        #expect(editor.marked == "‸")
    }

    @Test func typingOverASelectionWrapsIt() {
        let editor = EditorHarness()
        editor.load("say «hi»")
        editor.type("\"")
        #expect(editor.marked == "say \"«hi»\"")
    }

    @Test func autoPairCanBeSwitchedOff() {
        var configuration = EditorConfiguration.macDownDefaults
        configuration.autoPair = false
        let editor = EditorHarness(configuration: configuration)
        editor.type("(")
        #expect(editor.marked == "(‸")
    }

    @Test func apostropheInsideAWordIsNotPaired() {
        let editor = EditorHarness()
        editor.type("don't")
        #expect(editor.textView.string == "don't")
    }
}

@MainActor
@Suite(.requiresWindowServer) struct EditorFormatCommandTests {
    @Test func boldWrapsTheSelectionAndKeepsFocus() {
        let editor = EditorHarness()
        editor.load("make «this» loud")
        editor.window.makeFirstResponder(nil)
        editor.controller.perform(.bold)
        #expect(editor.marked == "make **«this»** loud")
        #expect(editor.box.value == "make **this** loud")
        #expect(editor.window.firstResponder === editor.textView)
    }

    @Test func formatChangesAreUndoableWithTheirName() {
        let editor = EditorHarness()
        editor.load("«word»")
        editor.controller.perform(.italic)
        #expect(editor.textView.undoManager?.undoActionName == "Italic")
        editor.textView.undoManager?.undo()
        #expect(editor.textView.string == "word")
    }

    @Test func italicOnBoldTextAddsToIt() {
        let editor = EditorHarness()
        editor.load("**«word»**")
        editor.controller.perform(.italic)
        #expect(editor.marked == "***«word»***")
        editor.controller.perform(.bold)
        #expect(editor.marked == "*«word»*")
        editor.controller.perform(.italic)
        #expect(editor.marked == "«word»")
    }

    @Test func headingsListsAndQuotes() {
        let editor = EditorHarness()
        editor.load("Title‸")
        editor.controller.perform(.heading(2))
        #expect(editor.marked == "## Title‸")
        editor.controller.perform(.heading(2))
        #expect(editor.marked == "Title‸")
        editor.load("«a\nb»")
        editor.controller.perform(.numberedList)
        #expect(editor.marked == "«1. a\n2. b»")
    }

    @Test func indentCommandIndentsTheWholeLineEvenWithAnEmptySelection() {
        let editor = EditorHarness()
        editor.load("para‸graph")
        editor.controller.perform(.indent)
        #expect(editor.marked == "    para‸graph")
        editor.controller.perform(.outdent)
        #expect(editor.marked == "para‸graph")
    }

    @Test func aDetachedControllerDoesNothing() {
        let controller = EditorController()
        #expect(!controller.isAttached)
        controller.perform(.bold)   // must not crash
    }

    @Test func everyCommandHasATitleSymbolAndUniqueShortcut() {
        var seen = Set<String>()
        for command in FormatCommand.allCases {
            #expect(!command.title.isEmpty)
            #expect(!command.symbolName.isEmpty)
            let shortcut = command.shortcut
            let key = "\(shortcut.key.character)-\(shortcut.modifiers.rawValue)"
            #expect(seen.insert(key).inserted, "\(command.title) reuses a shortcut")
        }
        #expect(FormatCommand.allCases.count == 20)
    }

    @Test func shortcutsAreLabelledTheWayMenusPrintThem() {
        #expect(FormatCommand.bold.shortcutLabel == "⌘B")
        #expect(FormatCommand.strikethrough.shortcutLabel == "⇧⌘X")
        #expect(FormatCommand.heading(3).shortcutLabel == "⌘3")
        #expect(FormatCommand.blockquote.shortcutLabel == "⇧⌘.")
        #expect(FormatCommand.indent.shortcutLabel == "⌘]")
        #expect(Set(FormatCommand.allCases.map(\.shortcutLabel)).count == FormatCommand.allCases.count)
    }

    @Test func everyCommandProducesAnEditOnASampleLine() {
        for command in FormatCommand.allCases {
            let edit = command.edit(in: "sample" as NSString, selection: NSRange(location: 0, length: 6), configuration: .macDownDefaults)
            if command == .outdent { #expect(edit == nil) } else { #expect(edit != nil, "\(command.title) did nothing") }
        }
    }
}
