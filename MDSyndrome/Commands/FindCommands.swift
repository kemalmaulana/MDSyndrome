import EditorKit
import SwiftUI

/// Edit → Find. SwiftUI's default Edit menu has no Find items, so ⌘F needs these. They go to the pane the
/// user is in: the editor's find bar, or the find bar over the preview. "Use Selection for Find" is left
/// out: ⌘E belongs to Format → Inline Code.
struct FindCommands: Commands {
    @FocusedValue(\.findRouter) private var router

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Menu("Find") {
                item("Find…", .show, key: "f", modifiers: .command)
                item("Find and Replace…", .showReplace, key: "f", modifiers: [.command, .option])
                item("Find Next", .next, key: "g", modifiers: .command)
                item("Find Previous", .previous, key: "g", modifiers: [.command, .shift])
                Button("Jump to Selection") { router?.editor?.jumpToSelection() }
                    .keyboardShortcut("j", modifiers: .command)
                    .disabled(router?.editor == nil)
            }
            .disabled(router == nil)
        }
    }

    private func item(_ title: String, _ action: FindAction, key: KeyEquivalent, modifiers: EventModifiers) -> some View {
        Button(title) { router?.run(action) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(router?.target(for: action) == nil)
    }
}
