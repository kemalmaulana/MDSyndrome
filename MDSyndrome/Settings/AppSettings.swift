import EditorKit
import Foundation
import MarkdownCore

/// The `UserDefaults` keys behind the Settings window. Views read them with `@AppStorage`; everything else goes
/// through `AppSettings`, which turns them into the values the rest of the app uses.
enum SettingsKey {
    static let openInPreview = "openInPreview"
    static let loadRemoteImages = "loadRemoteImages"
    static let syncScroll = "syncScroll"
    /// Quit the app when its last document window closes.
    static let quitAfterLastWindow = "quitAfterLastWindow"

    static let editorTheme = EditorTheme.storageKey
    static let editorFontName = "editorFontName"
    static let editorFontSize = "editorFontSize"
    static let editorLineSpacing = "editorLineSpacing"
    static let editorHorizontalInset = "editorHorizontalInset"
    static let editorVerticalInset = "editorVerticalInset"
    /// 0 uses the whole window width.
    static let editorMaxTextWidth = "editorMaxTextWidth"
    static let editorSoftWrap = "editorSoftWrap"
    static let editorSpellCheck = "editorSpellCheck"
    static let editorUseTabs = "editorUseTabs"
    static let editorTabWidth = "editorTabWidth"
    static let editorAutoPair = "editorAutoPair"
    static let editorContinueLists = "editorContinueLists"
    static let editorRenumberLists = "editorRenumberLists"
    /// A folder name below the document's folder for pasted images; empty means the document's own folder.
    static let editorImageFolder = "editorImageFolder"

    static let tables = "mdTables"
    static let taskLists = "mdTaskLists"
    static let strikethrough = "mdStrikethrough"
    static let autolinks = "mdAutolinks"
    static let footnotes = "mdFootnotes"
    static let math = "mdMath"
    static let singleDollarMath = "mdSingleDollarMath"
    static let highlight = "mdHighlight"
    static let smartPunctuation = "mdSmartPunctuation"
    static let hardBreaks = "mdHardBreaks"
    static let frontMatter = "mdFrontMatter"

    static let previewTheme = "previewTheme"
    static let previewZoom = "previewZoom"
    /// 0 keeps the theme's own width.
    static let previewMaxWidth = "previewMaxWidth"
}

/// Everything the Settings window can change, read from `UserDefaults`. A missing key means the default, which
/// matches MacDown's preferences (Menlo 14, line spacing 3, insets 15/30).
struct AppSettings: Equatable {
    static let zoomRange: ClosedRange<Double> = 0.5...3
    static let zoomStep = 0.1

    var openInPreview = false
    var loadRemoteImages = true
    var syncScroll = true
    var quitAfterLastWindow = true
    var editorThemeName = EditorTheme.tomorrowPlus.name
    var previewThemeName = PreviewThemeName.github
    var previewZoom = 1.0
    var previewMaxWidth = 0.0
    var markdown = MarkdownOptions.default
    var editor = EditorConfiguration.macDownDefaults

    enum PreviewThemeName { static let github = "GitHub" }

    init() {}

    init(defaults: UserDefaults) {
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }
        func double(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key) }
        func string(_ key: String, _ fallback: String) -> String { defaults.string(forKey: key) ?? fallback }

        openInPreview = bool(SettingsKey.openInPreview, openInPreview)
        loadRemoteImages = bool(SettingsKey.loadRemoteImages, loadRemoteImages)
        syncScroll = bool(SettingsKey.syncScroll, syncScroll)
        quitAfterLastWindow = bool(SettingsKey.quitAfterLastWindow, quitAfterLastWindow)
        editorThemeName = string(SettingsKey.editorTheme, editorThemeName)
        previewThemeName = string(SettingsKey.previewTheme, previewThemeName)
        previewZoom = min(max(double(SettingsKey.previewZoom, previewZoom), Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        previewMaxWidth = max(0, double(SettingsKey.previewMaxWidth, previewMaxWidth))

        markdown.tables = bool(SettingsKey.tables, markdown.tables)
        markdown.taskLists = bool(SettingsKey.taskLists, markdown.taskLists)
        markdown.strikethrough = bool(SettingsKey.strikethrough, markdown.strikethrough)
        markdown.autolinks = bool(SettingsKey.autolinks, markdown.autolinks)
        markdown.footnotes = bool(SettingsKey.footnotes, markdown.footnotes)
        markdown.math = bool(SettingsKey.math, markdown.math)
        markdown.singleDollarMath = bool(SettingsKey.singleDollarMath, markdown.singleDollarMath)
        markdown.highlight = bool(SettingsKey.highlight, markdown.highlight)
        markdown.smartPunctuation = bool(SettingsKey.smartPunctuation, markdown.smartPunctuation)
        markdown.hardBreaks = bool(SettingsKey.hardBreaks, markdown.hardBreaks)
        markdown.frontMatter = bool(SettingsKey.frontMatter, markdown.frontMatter)

        editor.fontName = string(SettingsKey.editorFontName, editor.fontName)
        editor.fontSize = min(max(double(SettingsKey.editorFontSize, editor.fontSize), 8), 48)
        editor.lineSpacing = min(max(double(SettingsKey.editorLineSpacing, editor.lineSpacing), 0), 20)
        editor.horizontalInset = min(max(double(SettingsKey.editorHorizontalInset, editor.horizontalInset), 0), 200)
        editor.verticalInset = min(max(double(SettingsKey.editorVerticalInset, editor.verticalInset), 0), 200)
        editor.maxTextWidth = min(max(double(SettingsKey.editorMaxTextWidth, 0), 0), 4_000)
        editor.softWrap = bool(SettingsKey.editorSoftWrap, editor.softWrap)
        editor.spellCheck = bool(SettingsKey.editorSpellCheck, editor.spellCheck)
        editor.autoPair = bool(SettingsKey.editorAutoPair, editor.autoPair)
        editor.continueLists = bool(SettingsKey.editorContinueLists, editor.continueLists)
        editor.renumberLists = bool(SettingsKey.editorRenumberLists, editor.renumberLists)
        let width = Int(min(max(double(SettingsKey.editorTabWidth, 4), 1), 8))
        editor.indentUnit = bool(SettingsKey.editorUseTabs, false) ? "\t" : String(repeating: " ", count: width)
        editor.imageFolder = Self.imageFolder(defaults.string(forKey: SettingsKey.editorImageFolder))
    }

    /// A single folder name below the document's folder: no slashes, no `..`, nothing hidden. Anything else falls back to
    /// `assets`; an explicitly empty value means the document's own folder.
    static func imageFolder(_ raw: String?) -> String {
        guard let raw else { return "assets" }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "" }
        let bad = name.contains("/") || name.contains("\\") || name.hasPrefix(".")
        return bad ? "assets" : name
    }
}
