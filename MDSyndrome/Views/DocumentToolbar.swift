import EditorKit
import SwiftUI

/// The window toolbar: the layout picker on the leading side, format buttons on the trailing side.
/// It is customizable (View → Customize Toolbar…): buttons can be reordered, removed and restored.
/// Rarely used formats live in one "More" menu so the default set fits a narrow window.
struct DocumentToolbar: CustomizableToolbarContent {
    @Binding var layoutMode: LayoutMode
    let editor: EditorController
    let editorIsVisible: Bool

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "layout", placement: .navigation) {
            Picker("Layout", selection: $layoutMode) {
                ForEach(LayoutMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Switch between editor, split view and preview")
        }
        formatItem(.bold)
        formatItem(.italic)
        formatItem(.inlineCode)
        formatItem(.link)
        formatItem(.bulletList)
        formatItem(.numberedList)
        formatItem(.blockquote)
        ToolbarItem(id: "format.heading", placement: .primaryAction) {
            Menu {
                commandButtons(FormatCommand.headings)
            } label: {
                Label("Heading", systemImage: "textformat.size")
            }
            .disabled(!editorIsVisible)
            .help("Set the heading level")
        }
        ToolbarItem(id: "format.more", placement: .primaryAction) {
            Menu {
                commandButtons([.strikethrough, .highlight, .image, .codeBlock, .taskList])
                Divider()
                commandButtons(FormatCommand.indentation)
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .disabled(!editorIsVisible)
            .help("More formatting")
        }
    }

    @ToolbarContentBuilder
    private func formatItem(_ command: FormatCommand) -> some CustomizableToolbarContent {
        ToolbarItem(id: "format.\(command.title)", placement: .primaryAction) {
            Button { editor.perform(command) } label: {
                Label(command.title, systemImage: command.symbolName)
            }
            .disabled(!editorIsVisible)
            .help("\(command.title) (\(command.shortcutLabel))")
        }
    }

    @ViewBuilder
    private func commandButtons(_ commands: [FormatCommand]) -> some View {
        ForEach(commands, id: \.self) { command in
            Button("\(command.title)  \(command.shortcutLabel)") { editor.perform(command) }
        }
    }
}
