import EditorKit
import SwiftUI

/// Edit → Find. SwiftUI's default Edit menu has no Find items, so ⌘F needs these to reach the
/// editor's find bar. "Use Selection for Find" is left out: ⌘E belongs to Format → Inline Code.
struct FindCommands: Commands {
    @FocusedValue(\.editorController) private var editor

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Menu("Find") {
                Button("Find…") { editor?.find(.show) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find and Replace…") { editor?.find(.showReplace) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Find Next") { editor?.find(.next) }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { editor?.find(.previous) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Jump to Selection") { editor?.jumpToSelection() }
                    .keyboardShortcut("j", modifiers: .command)
            }
            .disabled(editor == nil)
        }
    }
}
