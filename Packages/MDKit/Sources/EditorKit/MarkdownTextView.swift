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

    /// Called when the user starts working in the editor: it takes keyboard focus, is clicked, or gets a
    /// key press. Clicking the preview does not move keyboard focus, so a click or key press back in the
    /// editor is the only way the window learns the user is back.
    var onActivity: (() -> Void)?

    /// Where the document lives (nil while unsaved) and what to do when an image arrives without one. Set by the coordinator.
    var documentFolderProvider: (() -> URL?)?
    var onImageNeedsSavedDocument: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onActivity?() }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        onActivity?()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        onActivity?()
        super.keyDown(with: event)
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

    // MARK: Images (ED-11)

    /// Image items on a pasteboard, or nil when it carries text (text wins) or nothing we take.
    func imageItems(on pasteboard: NSPasteboard) -> [ImageInsertion.Item]? {
        if pasteboard.availableType(from: [.string]) != nil { return nil }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let images = urls.filter(ImageInsertion.isImageFile)
            return images.count == urls.count ? images.map { .file($0) } : nil
        }
        if let png = pasteboard.data(forType: .png) { return [.bitmap(png)] }
        if let tiff = pasteboard.data(forType: .tiff), let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return [.bitmap(png)]
        }
        return nil
    }

    /// Saves the images and inserts their Markdown at `location` as one undoable edit. Without a document folder nothing is
    /// written and the window is told to ask for a save. A failed write shows the error and inserts nothing.
    @discardableResult
    func insertImages(_ items: [ImageInsertion.Item], at location: Int) -> Bool {
        guard let folder = documentFolderProvider?() else {
            onImageNeedsSavedDocument?()
            return true
        }
        let plan = ImageInsertion.plan(items: items, documentFolder: folder, imageFolder: behavior.imageFolder, now: Date(),
                                       exists: { FileManager.default.fileExists(atPath: $0.path) })
        do {
            for action in plan.actions {
                switch action {
                case .write(let data, let destination):
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: destination, options: .atomic)
                case .copy(let source, let destination):
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: source, to: destination)
                }
            }
        } catch {
            if let window { NSAlert(error: error).beginSheetModal(for: window) } else { NSAlert(error: error).runModal() }
            return true
        }
        let at = NSRange(location: min(max(location, 0), text.length), length: 0)
        let end = at.location + (plan.markdown as NSString).length
        apply(TextEdit(range: at, replacement: plan.markdown, selection: NSRange(location: end, length: 0)), actionName: "Insert Image")
        return true
    }

    override func paste(_ sender: Any?) {
        if hasSingleSelection, let items = imageItems(on: .general) {
            insertImages(items, at: selectedRange().location)
        } else {
            super.paste(sender)
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        imageItems(on: sender.draggingPasteboard) != nil ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        imageItems(on: sender.draggingPasteboard) != nil ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let items = imageItems(on: sender.draggingPasteboard) else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        return insertImages(items, at: characterIndexForInsertion(at: point))
    }
}
