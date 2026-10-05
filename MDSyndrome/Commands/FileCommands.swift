import SwiftUI

/// Something a menu command can run in the active window (a struct, since a bare closure cannot be compared).
struct DocumentAction {
    let run: @MainActor () -> Void
}

extension FocusedValues {
    /// Reloads the active document from disk; nil for an untitled document, which has no file yet.
    @Entry var reloadDocument: DocumentAction?
}

struct FileCommands: Commands {
    @FocusedValue(\.reloadDocument) private var reload

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Reload from Disk") { reload?.run() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(reload == nil)
        }
    }
}
