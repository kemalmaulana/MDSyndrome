import AppKit
import SwiftUI

/// Keeps a MarkdownTextView and a SwiftUI String binding in sync without loops: user edits flow out
/// through `textDidChange`; model changes flow in through `setText`, which never echoes back to the
/// binding. Also owns the syntax highlighter and applies the editor theme.
@MainActor
public final class EditorCoordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>
    public private(set) weak var textView: NSTextView?
    private weak var scrollView: NSScrollView?
    private var highlighter: EditorHighlighter?
    private var scrollSupport: EditorScrollSupport?
    private var isApplyingExternalText = false
    private var lastWrittenText: String?
    /// Counts character edits; the binding is written once per count, whichever callback sees it first.
    private var editCount = 0
    private var syncedEditCount = 0
    private var appliedConfiguration: EditorConfiguration?
    private var appliedTheme: EditorTheme?

    public init(text: Binding<String>) {
        self.text = text
    }

    /// One-time setup of a fresh text view: plain text, undo, find bar, no "smart" substitutions,
    /// syntax highlighting, and the theme.
    func attach(to textView: MarkdownTextView, scrollView: NSScrollView? = nil, theme: EditorTheme,
                configuration: EditorConfiguration, controller: EditorController? = nil) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.setAccessibilityIdentifier("markdown-editor")
        textView.delegate = self
        self.textView = textView
        self.scrollView = scrollView
        controller?.textView = textView
        textView.onActivity = { [weak controller] in controller?.onFocus?() }

        let highlighter = EditorHighlighter(theme: theme, configuration: configuration)
        self.highlighter = highlighter
        if let scrollView {
            let support = EditorScrollSupport(
                textView: textView, scrollView: scrollView,
                lineAt: { [weak highlighter] in highlighter?.line(at: $0) ?? 0 },
                locationOfLine: { [weak highlighter] in highlighter?.location(ofLine: $0) ?? 0 },
                rangeOfLine: { [weak highlighter] in highlighter?.contentRange(ofLine: $0) },
                report: { [weak controller] line in controller?.onScroll?(line) })
            controller?.scrolling = support
            scrollSupport = support
        }
        textView.lineStateProvider = { [weak highlighter] location in highlighter?.lineState(at: location) }
        // Undo and redo change the text without telling the text view's delegate, so the binding is
        // fed from the text storage, which sees every change.
        highlighter.onCharactersChanged = { [weak self] in self?.storageDidChange() }
        if let storage = textView.textStorage { highlighter.attach(to: storage) }
        apply(theme: theme, configuration: configuration, force: true)
    }

    /// Applies the theme and configuration; re-colours only when something visual changed.
    func apply(theme: EditorTheme, configuration: EditorConfiguration, force: Bool = false) {
        guard let textView = textView as? MarkdownTextView, let highlighter else { return }
        textView.behavior = configuration
        if textView.isContinuousSpellCheckingEnabled != configuration.spellCheck { textView.isContinuousSpellCheckingEnabled = configuration.spellCheck }
        applyWrapping(configuration.softWrap, to: textView)
        let inset = NSSize(width: configuration.horizontalInset, height: configuration.verticalInset)
        if textView.textContainerInset != inset { textView.textContainerInset = inset }   // SwiftUI calls this on every keystroke

        let restyle = force || theme != appliedTheme || appliedConfiguration.map { Self.visuallyDiffers($0, configuration) } ?? true
        appliedConfiguration = configuration
        appliedTheme = theme
        guard restyle else { return }

        textView.backgroundColor = editorColor(theme.background) ?? .textBackgroundColor
        textView.drawsBackground = true
        textView.insertionPointColor = editorColor(theme.caret) ?? .textColor
        var selected: [NSAttributedString.Key: Any] = [:]
        if let background = editorColor(theme.selectionBackground) { selected[.backgroundColor] = background }
        if let foreground = editorColor(theme.selectionForeground) { selected[.foregroundColor] = foreground }
        textView.selectedTextAttributes = selected.isEmpty ? [.backgroundColor: NSColor.selectedTextBackgroundColor] : selected
        if let scrollView {
            scrollView.backgroundColor = editorColor(theme.background) ?? .textBackgroundColor
            scrollView.drawsBackground = true
            // Scrollers and the find bar should match a dark theme even in a light system appearance.
            scrollView.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        }

        highlighter.theme = theme
        highlighter.configuration = configuration
        textView.defaultParagraphStyle = configuration.paragraphStyle
        textView.typingAttributes = configuration.textAttributes(foreground: editorColor(theme.foreground) ?? .textColor)
        highlighter.restyleAll()
    }

    /// Soft wrap follows the view's width; without it the text container is as wide as the longest line and the
    /// scroll view gets a horizontal scroller.
    private func applyWrapping(_ wrap: Bool, to textView: NSTextView) {
        guard let container = textView.textContainer, container.widthTracksTextView != wrap else { return }
        container.widthTracksTextView = wrap
        textView.isHorizontallyResizable = !wrap
        scrollView?.hasHorizontalScroller = !wrap
        if wrap {
            textView.autoresizingMask = [.width]
            container.containerSize = NSSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        } else {
            textView.autoresizingMask = []
            container.containerSize = NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    private static func visuallyDiffers(_ a: EditorConfiguration, _ b: EditorConfiguration) -> Bool {
        a.fontName != b.fontName || a.fontSize != b.fontSize || a.lineSpacing != b.lineSpacing
    }

    /// Replaces the text view's content when the model changed from outside (file load, revert).
    public func setText(_ newValue: String) {
        guard let textView else { return }
        // The binding usually hands back the very string we wrote; String == short-circuits on identity.
        if let lastWrittenText, lastWrittenText == newValue { return }
        guard textView.string != newValue else { return }
        isApplyingExternalText = true
        defer { isApplyingExternalText = false }
        let length = (newValue as NSString).length
        let selection = textView.selectedRange()
        textView.string = newValue
        lastWrittenText = nil
        // The text was replaced behind the undo stack's back (file reload, revert). Its entries point at
        // ranges of the old text and could cut the new text in the wrong place, so drop them.
        textView.undoManager?.removeAllActions()
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
        syncBinding()
    }

    private func storageDidChange() {
        guard !isApplyingExternalText else { return }
        editCount += 1
        syncBinding()
    }

    /// Writes the text view's content to the binding if it changed since the last write.
    private func syncBinding() {
        guard !isApplyingExternalText, let textView, editCount != syncedEditCount else { return }
        syncedEditCount = editCount
        // NSTextView already registered a coalesced "Typing" undo action. A
        // SwiftUI FileDocument binding write would register a second,
        // per-keystroke action on the same undo manager, so ⌘Z would remove a
        // single character. Suspend registration for the binding write only.
        let undoManager = textView.undoManager
        undoManager?.disableUndoRegistration()
        defer { undoManager?.enableUndoRegistration() }
        let current = textView.string
        lastWrittenText = current
        text.wrappedValue = current
    }

    /// Finishes colouring a long document right away (tests; the run loop does it otherwise).
    func finishHighlighting() {
        highlighter?.finishPending()
    }
}
