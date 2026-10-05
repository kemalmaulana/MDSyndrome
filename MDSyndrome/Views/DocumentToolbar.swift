import EditorKit
import SwiftUI

/// The window toolbar. It is customizable (View → Customize Toolbar…): the layout picker and the
/// common format buttons show by default, the rest wait in the palette.
struct DocumentToolbar: CustomizableToolbarContent {
    @Binding var layoutMode: LayoutMode
    let editor: EditorController
    let editorIsVisible: Bool

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "layout", placement: .principal) {
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
        formatItem(.strikethrough, showsByDefault: false)
        formatItem(.highlight, showsByDefault: false)
        formatItem(.image, showsByDefault: false)
        formatItem(.codeBlock, showsByDefault: false)
        formatItem(.taskList, showsByDefault: false)
        ToolbarItem(id: "format.heading", placement: .secondaryAction, showsByDefault: false) {
            Menu {
                ForEach(FormatCommand.headings, id: \.self) { command in
                    Button("\(command.title)  \(command.shortcutLabel)") { editor.perform(command) }
                }
            } label: {
                Label("Heading", systemImage: "textformat.size")
            }
            .disabled(!editorIsVisible)
            .help("Set the heading level")
        }
        formatItem(.indent, showsByDefault: false)
        formatItem(.outdent, showsByDefault: false)
    }

    @ToolbarContentBuilder
    private func formatItem(_ command: FormatCommand, showsByDefault: Bool = true) -> some CustomizableToolbarContent {
        ToolbarItem(id: "format.\(command.title)", placement: .secondaryAction, showsByDefault: showsByDefault) {
            Button { editor.perform(command) } label: {
                Label(command.title, systemImage: command.symbolName)
            }
            .disabled(!editorIsVisible)
            .help("\(command.title) (\(command.shortcutLabel))")
        }
    }
}
