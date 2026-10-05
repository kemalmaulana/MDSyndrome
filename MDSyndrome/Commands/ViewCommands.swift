import EditorKit
import SwiftUI

struct ViewCommands: Commands {
    @FocusedBinding(\.layoutMode) private var layoutMode
    @FocusedBinding(\.outlineVisible) private var outlineVisible
    @State private var model = SettingsModel.shared
    @AppStorage(SettingsKey.editorTheme) private var editorThemeName = EditorTheme.tomorrowPlus.name
    @AppStorage(SettingsKey.previewTheme) private var previewThemeName = "GitHub"
    @AppStorage(SettingsKey.previewZoom) private var previewZoom = 1.0
    @AppStorage(SettingsKey.syncScroll) private var syncScroll = true

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
                ForEach(model.editorThemes) { theme in
                    Text(theme.name).tag(theme.name)
                }
            }
            Picker("Preview Theme", selection: $previewThemeName) {
                ForEach(model.previewThemes, id: \.name) { theme in
                    Text(theme.name).tag(theme.name)
                }
            }
            Divider()
            Button("Zoom In") { zoom(by: AppSettings.zoomStep) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(previewZoom >= AppSettings.zoomRange.upperBound)
            Button("Zoom Out") { zoom(by: -AppSettings.zoomStep) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(previewZoom <= AppSettings.zoomRange.lowerBound)
            Button("Actual Size") { previewZoom = 1 }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(previewZoom == 1)
            Divider()
        }
    }

    /// ⌘+ / ⌘−: the preview text, in steps of 10 %.
    private func zoom(by step: Double) {
        let next = (previewZoom + step) * 10
        previewZoom = min(max(next.rounded() / 10, AppSettings.zoomRange.lowerBound), AppSettings.zoomRange.upperBound)
    }
}
