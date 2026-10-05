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

    public init() {}

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
