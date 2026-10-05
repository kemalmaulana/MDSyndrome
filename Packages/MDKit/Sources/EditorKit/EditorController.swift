import AppKit

/// Find bar actions (the standard Edit → Find menu items).
public enum FindAction: Int, Sendable {
    case show = 1
    case next = 2
    case previous = 3
    case showReplace = 12
}

/// Lets the app's menus and toolbar drive the editor: the document window owns one, the editor view
/// attaches its text view to it, and Format and Find commands call into it.
@MainActor
public final class EditorController {
    weak var textView: MarkdownTextView?

    /// Called when the user works in the editor (focus, click or key press). The window uses it to know which pane Find should search.
    public var onFocus: (() -> Void)?

    public init() {}

    /// True while the keyboard is in the editor, including its find bar.
    public var hasFocus: Bool {
        guard let textView, let responder = textView.window?.firstResponder else { return false }
        if responder === textView { return true }
        guard let view = responder as? NSView else { return false }
        return view.isDescendant(of: textView.enclosingScrollView ?? textView)
    }

    /// True once an editor is attached to this controller.
    public var isAttached: Bool { textView != nil }

    /// Applies a Format command to the current selection and gives the editor focus back.
    public func perform(_ command: FormatCommand) {
        guard let textView, let storage = textView.textStorage,
              let edit = command.edit(in: storage.mutableString, selection: textView.selectedRange(), configuration: textView.behavior) else { return }
        textView.apply(edit, actionName: command.title)
        textView.window?.makeFirstResponder(textView)
    }

    /// Runs a find bar action in the editor. SwiftUI's default Edit menu has no Find items, so without
    /// these ⌘F would do nothing.
    public func find(_ action: FindAction) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        textView.performTextFinderAction(sender)
    }

    /// Scrolls the selection to the middle of the visible area (Edit → Find → Jump to Selection).
    public func jumpToSelection() {
        textView?.centerSelectionInVisibleArea(nil)
    }

    /// Moves keyboard focus into the editor.
    public func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }
}
