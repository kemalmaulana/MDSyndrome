import EditorKit
import Foundation
import MarkdownCore
import PreviewKit
import Testing
@testable import MDSyndrome

/// A throwaway defaults domain, removed afterwards.
private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "mds-settings-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
}

@Suite struct AppSettingsTests {
    @Test func nothingSetMeansMacDownsDefaults() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            #expect(settings == AppSettings())
            #expect(settings.editor.fontName == "Menlo-Regular" && settings.editor.fontSize == 14)
            #expect(settings.editor.lineSpacing == 3 && settings.editor.horizontalInset == 15 && settings.editor.verticalInset == 30)
            #expect(settings.editorThemeName == "Tomorrow+" && settings.previewThemeName == "GitHub")
            #expect(settings.syncScroll && settings.loadRemoteImages && !settings.openInPreview)
            #expect(settings.markdown == MarkdownOptions.default)
            #expect(settings.editor.indentUnit == "    ")
        }
    }

    @Test func everyKeyReachesItsValue() {
        withDefaults { defaults in
            defaults.set(true, forKey: SettingsKey.openInPreview)
            defaults.set(false, forKey: SettingsKey.loadRemoteImages)
            defaults.set(false, forKey: SettingsKey.syncScroll)
            defaults.set("Writer", forKey: SettingsKey.editorTheme)
            defaults.set("Solarized", forKey: SettingsKey.previewTheme)
            defaults.set(1.5, forKey: SettingsKey.previewZoom)
            defaults.set(700.0, forKey: SettingsKey.previewMaxWidth)
            defaults.set("Monaco", forKey: SettingsKey.editorFontName)
            defaults.set(18.0, forKey: SettingsKey.editorFontSize)
            defaults.set(false, forKey: SettingsKey.editorSoftWrap)
            defaults.set(true, forKey: SettingsKey.editorSpellCheck)
            defaults.set(false, forKey: SettingsKey.editorAutoPair)
            defaults.set(false, forKey: SettingsKey.editorContinueLists)
            defaults.set(false, forKey: SettingsKey.editorRenumberLists)
            defaults.set(false, forKey: SettingsKey.tables)
            defaults.set(false, forKey: SettingsKey.math)
            defaults.set(true, forKey: SettingsKey.hardBreaks)
            defaults.set(true, forKey: SettingsKey.smartPunctuation)
            defaults.set(false, forKey: SettingsKey.frontMatter)
            let settings = AppSettings(defaults: defaults)
            #expect(settings.openInPreview && !settings.loadRemoteImages && !settings.syncScroll)
            #expect(settings.editorThemeName == "Writer" && settings.previewThemeName == "Solarized")
            #expect(settings.previewZoom == 1.5 && settings.previewMaxWidth == 700)
            #expect(settings.editor.fontName == "Monaco" && settings.editor.fontSize == 18)
            #expect(!settings.editor.softWrap && settings.editor.spellCheck)
            #expect(!settings.editor.autoPair && !settings.editor.continueLists && !settings.editor.renumberLists)
            #expect(!settings.markdown.tables && !settings.markdown.math && settings.markdown.hardBreaks)
            #expect(settings.markdown.smartPunctuation && !settings.markdown.frontMatter)
            #expect(settings.markdown.taskLists, "untouched keys keep their defaults")
        }
    }

    @Test func indentIsTabsOrASetNumberOfSpaces() {
        withDefaults { defaults in
            defaults.set(2, forKey: SettingsKey.editorTabWidth)
            #expect(AppSettings(defaults: defaults).editor.indentUnit == "  ")
            defaults.set(true, forKey: SettingsKey.editorUseTabs)
            #expect(AppSettings(defaults: defaults).editor.indentUnit == "\t")
        }
    }

    @Test func absurdValuesAreClamped() {
        withDefaults { defaults in
            defaults.set(99.0, forKey: SettingsKey.previewZoom)
            defaults.set(-4.0, forKey: SettingsKey.previewMaxWidth)
            defaults.set(1.0, forKey: SettingsKey.editorFontSize)
            defaults.set(5_000.0, forKey: SettingsKey.editorHorizontalInset)
            defaults.set(900, forKey: SettingsKey.editorTabWidth)
            let settings = AppSettings(defaults: defaults)
            #expect(settings.previewZoom == 3 && settings.previewMaxWidth == 0)
            #expect(settings.editor.fontSize == 8 && settings.editor.horizontalInset == 200)
            #expect(settings.editor.indentUnit.count == 8)
            defaults.set(0.0, forKey: SettingsKey.previewZoom)
            #expect(AppSettings(defaults: defaults).previewZoom == 0.5)
        }
    }
}

@Suite struct ThemeStoreTests {
    private func withFolder(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mds-themes-\(UUID().uuidString)", isDirectory: true)
        ThemeStore.ensureFolders(in: root)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func write(_ text: String, _ name: String, kind: String, in root: URL) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(kind).appendingPathComponent(name))
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    @Test func aValidThemeOfEachKindLoads() throws {
        try withFolder { root in
            var editor = EditorTheme.writer
            editor.name = "Mine"
            var preview = PreviewTheme.clearness
            preview.name = "Mine"
            try write(try json(editor), "mine.json", kind: "Editor", in: root)
            try write(try json(preview), "mine.json", kind: "Preview", in: root)
            #expect(ThemeStore.loadEditorThemes(in: root).themes.map(\.name) == ["Mine"])
            #expect(ThemeStore.loadPreviewThemes(in: root).themes.map(\.name) == ["Mine"])
        }
    }

    @Test func aBrokenFileIsSkippedAndReportedWithoutStoppingTheRest() throws {
        try withFolder { root in
            var good = EditorTheme.writer
            good.name = "Good"
            try write(try json(good), "a-good.json", kind: "Editor", in: root)
            try write("{ not json", "b-broken.json", kind: "Editor", in: root)
            try write("{\"name\": \"Half\"}", "c-incomplete.json", kind: "Editor", in: root)
            try write(try json(good), "d-duplicate.json", kind: "Editor", in: root)
            try write("ignored", "notes.txt", kind: "Editor", in: root)
            let loaded = ThemeStore.loadEditorThemes(in: root)
            #expect(loaded.themes.map(\.name) == ["Good"])
            #expect(loaded.problems.count == 3)
            #expect(loaded.problems.contains { $0.hasPrefix("b-broken.json") } && loaded.problems.contains { $0.hasPrefix("d-duplicate.json") })
        }
    }

    @Test func aMissingFolderIsJustNoThemes() {
        let nowhere = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(ThemeStore.loadEditorThemes(in: nowhere).themes.isEmpty)
        #expect(ThemeStore.loadPreviewThemes(in: nowhere).problems.isEmpty)
    }

    @Test func aUserThemeReplacesABuiltInOfTheSameNameAndOthersAreAdded() {
        var mine = PreviewTheme.github
        mine.name = "GitHub"
        mine.bodyFontSize = 20
        var other = PreviewTheme.github
        other.name = "Other"
        let merged = ThemeStore.merged(builtIn: PreviewTheme.builtIn, user: [mine, other], name: \.name)
        #expect(merged.map(\.name) == ["Clearness", "Solarized", "System", "GitHub", "Other"])
        #expect(merged.first { $0.name == "GitHub" }?.bodyFontSize == 20)
    }
}

@MainActor
@Suite struct SettingsModelTests {
    @Test func aChangeInTheDefaultsReachesTheModel() async throws {
        let name = "mds-model-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = SettingsModel(defaults: defaults, themeRoot: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        #expect(model.settings.previewZoom == 1)
        defaults.set(1.4, forKey: SettingsKey.previewZoom)
        defaults.set("Clearness", forKey: SettingsKey.previewTheme)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.settings.previewZoom == 1.4)
        #expect(model.previewTheme.name == "Clearness")
        #expect(model.previewTheme.bodyFontSize == PreviewTheme.clearness.bodyFontSize * 1.4)
    }

    @Test func unknownThemeNamesFallBackToTheDefaults() {
        let model = SettingsModel(defaults: UserDefaults(suiteName: "mds-x-\(UUID().uuidString)")!, themeRoot: URL(fileURLWithPath: "/nonexistent"))
        #expect(model.editorTheme(named: "No such theme") == .tomorrowPlus)
        #expect(model.editorThemes.count == EditorTheme.builtIn.count)
    }
}

@Suite struct PreviewThemeSettingsTests {
    @Test func theFourBuiltInThemesAreNamedAndDistinct() {
        #expect(PreviewTheme.builtIn.map(\.name) == ["GitHub", "Clearness", "Solarized", "System"])
        #expect(Set(PreviewTheme.builtIn.map(\.background)).count == 4)
        #expect(PreviewTheme.named("Solarized") == .solarized)
        #expect(PreviewTheme.named("nope") == .github)
    }

    @Test func zoomScalesTextAndSpacingButNotTheContentWidth() {
        let zoomed = PreviewTheme.github.scaled(by: 1.5)
        #expect(zoomed.bodyFontSize == 24 && zoomed.codeFontSize == PreviewTheme.github.codeFontSize * 1.5)
        #expect(zoomed.lineSpacing == 6 && zoomed.blockSpacing == 24)
        #expect(zoomed.maxContentWidth == PreviewTheme.github.maxContentWidth)
        #expect(PreviewTheme.github.withMaxContentWidth(500).maxContentWidth == 500)
    }

    @Test func aThemeSurvivesAJSONRoundTrip() throws {
        for theme in PreviewTheme.builtIn {
            let decoded = try JSONDecoder().decode(PreviewTheme.self, from: JSONEncoder().encode(theme))
            #expect(decoded == theme)
        }
    }

    @Test func remoteImagesCanBeRefused() async {
        let remote = ImageSource.remote(URL(string: "https://example.invalid/a.png")!)
        await #expect(throws: ImageLoadError.remoteDisabled) { _ = try await ImageLoader.data(for: remote, allowRemote: false) }
    }
}
