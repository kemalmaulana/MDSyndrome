import AppKit

/// File ▸ Reload from Disk (⌘R): reads the open file again, for when another program changed it.
///
/// It goes through `NSDocument.revert(toContentsOf:ofType:)`, the same path as Revert to Saved, so the
/// editor, the preview, the undo history and the "edited" mark all follow the file.
@MainActor
enum DocumentReloader {
    /// Asks whether to throw away unsaved edits; calls `answer(true)` to reload, `answer(false)` to keep them.
    typealias Confirmation = @MainActor (_ document: NSDocument, _ answer: @escaping @MainActor (Bool) -> Void) -> Void

    /// - Parameter completion: called with true once the file was read again, false if the user kept
    ///   their edits or the file could not be read.
    static func reload(_ document: NSDocument, confirm: Confirmation? = nil,
                       completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard let url = document.fileURL, let type = document.fileType else {
            NSSound.beep()   // untitled: there is no file yet
            completion(false)
            return
        }
        func revert() {
            do {
                try document.revert(toContentsOf: url, ofType: type)
                completion(true)
            } catch {
                document.presentError(error)
                completion(false)
            }
        }
        guard document.isDocumentEdited else { return revert() }
        (confirm ?? askBeforeDiscardingEdits)(document) { reload in
            if reload { revert() } else { completion(false) }
        }
    }

    /// Whether the file on disk is newer than what the document last read or saved.
    static func isStale(_ document: NSDocument) -> Bool {
        guard let url = document.fileURL, let known = document.fileModificationDate,
              let onDisk = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return false }
        return onDisk > known
    }

    /// For when the app comes to the front: another program may have saved the file meanwhile. A clean
    /// document quietly picks the new text up; one with unsaved edits is left alone (saving it asks
    /// what to do, as for any document, and ⌘R asks too).
    static func reloadIfChangedOnDisk(_ document: NSDocument, completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard !document.isDocumentEdited, isStale(document) else { return completion(false) }
        reload(document, completion: completion)
    }

    /// A sheet on the document's window. Cancel is the default button: ⌘R pressed out of habit must not
    /// silently discard work.
    static let askBeforeDiscardingEdits: Confirmation = { document, answer in
        let alert = NSAlert()
        alert.messageText = "Reload “\(document.displayName ?? "this document")” from disk?"
        alert.informativeText = "Your unsaved changes in this window will be lost."
        alert.addButton(withTitle: "Cancel")
        let reload = alert.addButton(withTitle: "Reload")
        reload.hasDestructiveAction = true
        if let window = document.windowControllers.first?.window {
            alert.beginSheetModal(for: window) { response in answer(response == .alertSecondButtonReturn) }
        } else {
            answer(alert.runModal() == .alertSecondButtonReturn)
        }
    }
}
