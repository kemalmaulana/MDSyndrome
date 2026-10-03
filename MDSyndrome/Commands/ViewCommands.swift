import SwiftUI

struct ViewCommands: Commands {
    @FocusedBinding(\.layoutMode) private var layoutMode

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(LayoutMode.allCases) { mode in
                Button(mode.title) { layoutMode = mode }
                    .keyboardShortcut(mode.shortcut, modifiers: [.command, .option])
                    .disabled(layoutMode == nil)
            }
            Divider()
        }
    }
}
