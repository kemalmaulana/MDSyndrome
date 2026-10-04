import AppKit
import SwiftUI

/// Keeps an NSTextView and a SwiftUI String binding in sync without loops:
/// user edits flow out through `textDidChange`; model changes flow in through
/// `setText`, which never echoes back to the binding.
@MainActor
public final class EditorCoordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>
    public private(set) weak var textView: NSTextView?
    private var isApplyingExternalText = false
    private var appliedConfiguration: EditorConfiguration?

    public init(text: Binding<String>) {
        self.text = text
    }

    /// One-time setup of a fresh text view: plain text, undo, find bar, no "smart" substitutions.
    public func attach(to textView: NSTextView, configuration: EditorConfiguration) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.setAccessibilityIdentifier("markdown-editor")
        textView.delegate = self
        self.textView = textView
        apply(configuration)
    }

    public func apply(_ configuration: EditorConfiguration) {
        guard let textView, configuration != appliedConfiguration else { return }
        appliedConfiguration = configuration
        textView.font = configuration.font
        textView.defaultParagraphStyle = configuration.paragraphStyle
        textView.typingAttributes = configuration.textAttributes
        textView.textContainerInset = NSSize(width: configuration.horizontalInset, height: configuration.verticalInset)
        restyleAll()
    }

    /// Replaces the text view's content when the model changed from outside (file load, revert).
    public func setText(_ newValue: String) {
        guard let textView, textView.string != newValue else { return }
        isApplyingExternalText = true
        defer { isApplyingExternalText = false }
        let length = (newValue as NSString).length
        let selection = textView.selectedRange()
        textView.string = newValue
        restyleAll()
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
    }

    /// Hides the editor without destroying it. A zero-width or transparent NSTextView still receives
    /// keystrokes, so typing in Preview-only mode would silently edit (and autosave) the document.
    /// Hiding resigns focus; showing again hands focus back so the user can type straight away.
    public func setHidden(_ hidden: Bool, scrollView: NSScrollView) {
        guard scrollView.isHidden != hidden else { return }
        scrollView.isHidden = hidden
        guard let textView, let window = textView.window else { return }
        if hidden {
            if window.firstResponder === textView { window.makeFirstResponder(nil) }
        } else {
            window.makeFirstResponder(textView)
        }
    }

    public func textDidChange(_ notification: Notification) {
        guard !isApplyingExternalText, let textView = notification.object as? NSTextView else { return }
        // NSTextView already registered a coalesced "Typing" undo action. A
        // SwiftUI FileDocument binding write would register a second,
        // per-keystroke action on the same undo manager, so ⌘Z would remove a
        // single character. Suspend registration for the binding write only.
        let undoManager = textView.undoManager
        undoManager?.disableUndoRegistration()
        defer { undoManager?.enableUndoRegistration() }
        text.wrappedValue = textView.string
    }

    private func restyleAll() {
        guard let textView, let storage = textView.textStorage, let configuration = appliedConfiguration else { return }
        storage.setAttributes(configuration.textAttributes, range: NSRange(location: 0, length: storage.length))
    }
}
