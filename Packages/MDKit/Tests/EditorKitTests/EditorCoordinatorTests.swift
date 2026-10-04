import AppKit
import SwiftUI
import Testing
@testable import EditorKit

@MainActor
@Suite struct EditorCoordinatorTests {
    /// Captures binding writes so tests can count them.
    final class Box {
        var value: String
        var writes = 0
        init(_ value: String) { self.value = value }
    }

    private func makeEditor(_ initial: String = "") -> (EditorCoordinator, NSTextView, Box) {
        let box = Box(initial)
        let binding = Binding(get: { box.value }, set: { box.value = $0; box.writes += 1 })
        let coordinator = EditorCoordinator(text: binding)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        coordinator.attach(to: textView, configuration: .macDownDefaults)
        coordinator.setText(initial)
        return (coordinator, textView, box)
    }

    @Test func externalTextIsShownWithoutEchoingBack() {
        let (coordinator, textView, box) = makeEditor()
        coordinator.setText("# Loaded")
        #expect(textView.string == "# Loaded")
        #expect(box.writes == 0)
    }

    @Test func userTypingUpdatesBinding() {
        let (_, textView, box) = makeEditor("ab")
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.insertText("c", replacementRange: textView.selectedRange())
        #expect(box.value == "abc")
        #expect(box.writes == 1)
    }

    @Test func externalTextClampsSelection() {
        let (coordinator, textView, _) = makeEditor("long text here")
        textView.setSelectedRange(NSRange(location: 14, length: 0))
        coordinator.setText("short")
        #expect(textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test func plainTextSettingsAndDefaultFont() {
        let (_, textView, _) = makeEditor("x")
        #expect(!textView.isRichText)
        #expect(textView.allowsUndo)
        #expect(textView.usesFindBar)
        #expect(!textView.isAutomaticQuoteSubstitutionEnabled)
        #expect(textView.font?.fontName == "Menlo-Regular")
        #expect(textView.font?.pointSize == 14)
        #expect(textView.textContainerInset == NSSize(width: 15, height: 30))
        #expect(textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == textView.font)
    }

    @Test func configurationChangeRestylesExistingText() {
        let (coordinator, textView, _) = makeEditor("x")
        var bigger = EditorConfiguration.macDownDefaults
        bigger.fontSize = 20
        coordinator.apply(bigger)
        #expect((textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 20)
    }

    @Test func hidingTheEditorResignsFocusAndShowingRestoresIt() throws {
        _ = NSApplication.shared
        let box = Box("text")
        let coordinator = EditorCoordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let scrollView = NSTextView.scrollableTextView()
        let textView = try #require(scrollView.documentView as? NSTextView)
        coordinator.attach(to: textView, configuration: .macDownDefaults)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scrollView
        #expect(window.makeFirstResponder(textView))

        coordinator.setHidden(true, scrollView: scrollView)
        #expect(scrollView.isHidden)
        #expect(window.firstResponder !== textView, "a hidden editor must not receive keystrokes")

        coordinator.setHidden(false, scrollView: scrollView)
        #expect(!scrollView.isHidden)
        #expect(window.firstResponder === textView)
    }
}
