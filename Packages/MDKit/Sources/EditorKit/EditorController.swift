import AppKit

/// Lets the app's menus and toolbar drive the editor: the document window owns one, the editor view
/// attaches its text view to it, and Format commands call `perform`.
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

    /// Moves keyboard focus into the editor.
    public func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }
}
