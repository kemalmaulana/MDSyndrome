import AppKit

/// The editing view: an NSTextView (TextKit 2) that adds Markdown typing behaviour — list
/// continuation on Return, Tab / ⇧Tab indenting, auto-pairing — by applying the pure edits from
/// `EditTransforms` through the normal undo-aware editing path.
@MainActor
final class MarkdownTextView: NSTextView {
    /// Typing behaviour switches and the indent unit.
    var behavior = EditorConfiguration()

    /// The line state at a text location; lets Return skip list continuation inside code fences,
    /// math blocks and front matter. Set by the coordinator.
    var lineStateProvider: ((Int) -> LineState?)?

    /// Called when the text view becomes the first responder (the user clicked or tabbed into the editor).
    var onBecomeFirstResponder: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onBecomeFirstResponder?() }
        return accepted
    }

    private var text: NSString { textStorage?.mutableString ?? "" }
    private var hasSingleSelection: Bool { selectedRanges.count == 1 }

    /// Applies `edit` as one undoable change and moves the selection.
    func apply(_ edit: TextEdit, actionName: String? = nil) {
        guard let storage = textStorage else { return }
        if edit.replacement.isEmpty, edit.range.length == 0 {   // typing over a closer just moves the caret
            setSelectedRange(edit.selection)
            return
        }
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        storage.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        if let actionName { undoManager?.setActionName(actionName) }
    }

    /// Code, math and front matter are written as is: no list continuation there.
    private var isInPlainContext: Bool {
        guard let state = lineStateProvider?(selectedRange().location) else { return false }
        switch state {
        case .fence, .math, .frontMatter: return true
        default: return false
        }
    }

    override func insertNewline(_ sender: Any?) {
        if behavior.continueLists, hasSingleSelection, !hasMarkedText(), !isInPlainContext,
           let edit = EditTransforms.newline(in: text, selection: selectedRange(), renumber: behavior.renumberLists) {
            apply(edit)
        } else {
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        guard hasSingleSelection, !hasMarkedText() else { return super.insertTab(sender) }
        apply(EditTransforms.indent(in: text, selection: selectedRange(), unit: behavior.indentUnit))
    }

    override func insertBacktab(_ sender: Any?) {
        guard hasSingleSelection, !hasMarkedText() else { return super.insertBacktab(sender) }
        if let edit = EditTransforms.outdent(in: text, selection: selectedRange(), unit: behavior.indentUnit) {
            apply(edit)
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if behavior.autoPair, hasSingleSelection, !hasMarkedText(), replacementRange.location == NSNotFound {
            let typed = (insertString as? NSAttributedString)?.string ?? (insertString as? String)
            if let typed, typed.utf16.count == 1,
               let edit = EditTransforms.typed(typed, in: text, selection: selectedRange()) {
                apply(edit)
                return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        if behavior.autoPair, hasSingleSelection, !hasMarkedText(),
           let edit = EditTransforms.deleteBackward(in: text, selection: selectedRange()) {
            apply(edit)
        } else {
            super.deleteBackward(sender)
        }
    }
}
