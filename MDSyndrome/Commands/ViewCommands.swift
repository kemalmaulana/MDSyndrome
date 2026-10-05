import EditorKit
import SwiftUI

struct ViewCommands: Commands {
    @FocusedBinding(\.layoutMode) private var layoutMode
    @FocusedBinding(\.outlineVisible) private var outlineVisible
    @AppStorage(EditorTheme.storageKey) private var editorThemeName = EditorTheme.tomorrowPlus.name
    @AppStorage("syncScroll") private var syncScroll = true

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(LayoutMode.allCases) { mode in
                Button(mode.title) { layoutMode = mode }
                    .keyboardShortcut(mode.shortcut, modifiers: [.command, .option])
                    .disabled(layoutMode == nil)
            }
            Divider()
            Button(outlineVisible == true ? "Hide Outline" : "Show Outline") { outlineVisible?.toggle() }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .disabled(outlineVisible == nil)
            Toggle("Scroll Editor and Preview Together", isOn: $syncScroll)
            Divider()
            Picker("Editor Theme", selection: $editorThemeName) {
                ForEach(EditorTheme.builtIn) { theme in
                    Text(theme.name).tag(theme.name)
                }
            }
            Divider()
        }
    }
}
