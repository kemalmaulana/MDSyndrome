import AppKit
import SwiftUI

/// The Settings window (⌘,): General, Editor, Markdown and Preview. Every control writes a `SettingsKey` default,
/// which `SettingsModel` turns into live changes in every open document.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            EditorSettings().tabItem { Label("Editor", systemImage: "pencil.and.outline") }
            MarkdownSettings().tabItem { Label("Markdown", systemImage: "text.badge.checkmark") }
            PreviewSettings().tabItem { Label("Preview", systemImage: "eye") }
        }
        .frame(width: 520, height: 480)
        .scenePadding()
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.openInPreview) private var openInPreview = false
    @AppStorage(SettingsKey.loadRemoteImages) private var loadRemoteImages = true

    var body: some View {
        Form {
            Section("Opening") {
                Toggle("Open documents in the preview only", isOn: $openInPreview)
                Text("New windows start without the editor. Switch with ⌥⌘1, ⌥⌘2 and ⌥⌘3.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Images") {
                Toggle("Load remote images", isOn: $loadRemoteImages)
                Text("Off: pictures from http and https addresses are not fetched. Local images still show.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct EditorSettings: View {
    @State private var model = SettingsModel.shared
    @AppStorage(SettingsKey.editorTheme) private var theme = "Tomorrow+"
    @AppStorage(SettingsKey.editorFontName) private var fontName = "Menlo-Regular"
    @AppStorage(SettingsKey.editorFontSize) private var fontSize = 14.0
    @AppStorage(SettingsKey.editorLineSpacing) private var lineSpacing = 3.0
    @AppStorage(SettingsKey.editorHorizontalInset) private var horizontalInset = 15.0
    @AppStorage(SettingsKey.editorVerticalInset) private var verticalInset = 30.0
    @AppStorage(SettingsKey.editorMaxTextWidth) private var maxTextWidth = 0.0
    @AppStorage(SettingsKey.editorSoftWrap) private var softWrap = true
    @AppStorage(SettingsKey.editorSpellCheck) private var spellCheck = false
    @AppStorage(SettingsKey.editorUseTabs) private var useTabs = false
    @AppStorage(SettingsKey.editorTabWidth) private var tabWidth = 4
    @AppStorage(SettingsKey.editorAutoPair) private var autoPair = true
    @AppStorage(SettingsKey.editorContinueLists) private var continueLists = true
    @AppStorage(SettingsKey.editorRenumberLists) private var renumberLists = true
    @AppStorage(SettingsKey.editorImageFolder) private var imageFolder = "assets"

    private static let fonts: [String] = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? ["Menlo-Regular"]

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(model.editorThemes) { Text($0.name).tag($0.name) }
                }
                Picker("Font", selection: $fontName) {
                    ForEach(Self.fonts.contains(fontName) ? Self.fonts : [fontName] + Self.fonts, id: \.self) { name in
                        Text(NSFont(name: name, size: 12)?.displayName ?? name).tag(name)
                    }
                }
                Stepper("Size: \(Int(fontSize)) pt", value: $fontSize, in: 8...48)
                Stepper("Line spacing: \(Int(lineSpacing)) pt", value: $lineSpacing, in: 0...20)
                Stepper("Side margin: \(Int(horizontalInset)) pt", value: $horizontalInset, in: 0...200, step: 5)
                Stepper("Top margin: \(Int(verticalInset)) pt", value: $verticalInset, in: 0...200, step: 5)
                Toggle("Wrap long lines", isOn: $softWrap)
                Stepper(maxTextWidth == 0 ? "Text width: whole window" : "Text width: \(Int(maxTextWidth)) pt", value: $maxTextWidth, in: 0...2_000, step: 20)
                    .disabled(!softWrap)
                Toggle("Check spelling while typing", isOn: $spellCheck)
            }
            Section("Typing") {
                Toggle("Tab inserts a tab character", isOn: $useTabs)
                Stepper("Indent width: \(tabWidth) spaces", value: $tabWidth, in: 1...8).disabled(useTabs)
                Toggle("Close brackets and quotes automatically", isOn: $autoPair)
                Toggle("Continue lists and quotes on Return", isOn: $continueLists)
                Toggle("Renumber ordered lists", isOn: $renumberLists)
            }
            Section("Images") {
                TextField("Folder for pasted images", text: $imageFolder, prompt: Text("assets"))
                Text("Images you paste or drop are saved in this folder next to the document. Leave it empty to save them beside the document.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ThemesFolderSection()
        }
        .formStyle(.grouped)
    }
}

/// Where your own themes go, and what went wrong with the ones that did not load.
private struct ThemesFolderSection: View {
    @State private var model = SettingsModel.shared

    var body: some View {
        Section("Your themes") {
            Text("Put JSON theme files in the Editor and Preview folders; they appear in the theme menus.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reveal Themes Folder") { NSWorkspace.shared.activateFileViewerSelecting([ThemeStore.ensureFolders()]) }
                Button("Reload Themes") { model.reloadThemes() }
            }
            ForEach(model.themeProblems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

private struct MarkdownSettings: View {
    @AppStorage(SettingsKey.tables) private var tables = true
    @AppStorage(SettingsKey.taskLists) private var taskLists = true
    @AppStorage(SettingsKey.strikethrough) private var strikethrough = true
    @AppStorage(SettingsKey.autolinks) private var autolinks = true
    @AppStorage(SettingsKey.footnotes) private var footnotes = true
    @AppStorage(SettingsKey.math) private var math = true
    @AppStorage(SettingsKey.singleDollarMath) private var singleDollarMath = true
    @AppStorage(SettingsKey.highlight) private var highlight = true
    @AppStorage(SettingsKey.smartPunctuation) private var smartPunctuation = false
    @AppStorage(SettingsKey.hardBreaks) private var hardBreaks = false
    @AppStorage(SettingsKey.frontMatter) private var frontMatter = true

    var body: some View {
        Form {
            Section("GitHub Flavored Markdown") {
                Toggle("Tables", isOn: $tables)
                Toggle("Task lists", isOn: $taskLists)
                Toggle("Strikethrough", isOn: $strikethrough)
                Toggle("Autolinks", isOn: $autolinks)
                Toggle("Footnotes", isOn: $footnotes)
            }
            Section("Extensions") {
                Toggle("Math ($…$ and $$…$$)", isOn: $math)
                Toggle("Single dollar signs start inline math", isOn: $singleDollarMath).disabled(!math)
                Toggle("==Highlight==", isOn: $highlight)
                Toggle("Smart punctuation (curly quotes, dashes)", isOn: $smartPunctuation)
                Toggle("A new line is a line break", isOn: $hardBreaks)
                Toggle("Show YAML front matter", isOn: $frontMatter)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PreviewSettings: View {
    @State private var model = SettingsModel.shared
    @AppStorage(SettingsKey.previewTheme) private var theme = "GitHub"
    @AppStorage(SettingsKey.previewZoom) private var zoom = 1.0
    @AppStorage(SettingsKey.previewMaxWidth) private var maxWidth = 0.0
    @AppStorage(SettingsKey.syncScroll) private var syncScroll = true

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(model.previewThemes, id: \.name) { Text($0.name).tag($0.name) }
                }
                HStack {
                    Slider(value: $zoom, in: AppSettings.zoomRange, step: AppSettings.zoomStep) { Text("Text size") }
                    Text("\(Int((zoom * 100).rounded()))%").monospacedDigit().frame(width: 52, alignment: .trailing)
                    Button("Reset") { zoom = 1 }.disabled(zoom == 1)
                }
                Stepper(maxWidth == 0 ? "Content width: theme default" : "Content width: \(Int(maxWidth)) pt", value: $maxWidth, in: 0...2_000, step: 20)
            }
            Section("Scrolling") {
                Toggle("Scroll the editor and the preview together", isOn: $syncScroll)
            }
            ThemesFolderSection()
        }
        .formStyle(.grouped)
    }
}
