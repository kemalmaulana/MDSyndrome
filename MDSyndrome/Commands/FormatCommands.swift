import EditorKit
import SwiftUI

extension FocusedValues {
    /// The active document's editor; nil while the editor is hidden (Preview-only layout).
    @Entry var editorController: EditorController?
}

struct FormatCommands: Commands {
    @FocusedValue(\.editorController) private var editor

    var body: some Commands {
        CommandMenu("Format") {
            buttons(FormatCommand.inline)
            Divider()
            Menu("Heading") { buttons(FormatCommand.headings) }
            Divider()
            buttons(FormatCommand.blocks)
            Divider()
            buttons(FormatCommand.indentation)
        }
    }

    @ViewBuilder
    private func buttons(_ commands: [FormatCommand]) -> some View {
        ForEach(commands, id: \.self) { command in
            Button(command.title) { editor?.perform(command) }
                .keyboardShortcut(command.shortcut)
                .disabled(editor == nil)
        }
    }
}
