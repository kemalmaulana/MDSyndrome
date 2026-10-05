import EditorKit
import Foundation
import Observation
import PreviewKit

/// The current settings and themes, shared by every window. It reloads when `UserDefaults` changes, so a change in
/// the Settings window reaches open documents at once.
@MainActor
@Observable
final class SettingsModel {
    static let shared = SettingsModel()

    private(set) var settings: AppSettings
    private(set) var editorThemes: [EditorTheme] = EditorTheme.builtIn
    private(set) var previewThemes: [PreviewTheme] = PreviewTheme.builtIn
    /// Theme files that were skipped, for the Settings window.
    private(set) var themeProblems: [String] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let themeRoot: URL
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, themeRoot: URL = ThemeStore.defaultFolder) {
        self.defaults = defaults
        self.themeRoot = themeRoot
        settings = AppSettings(defaults: defaults)
        reloadThemes()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadSettings() }
        }
    }

    func reloadSettings() {
        let fresh = AppSettings(defaults: defaults)
        if fresh != settings { settings = fresh }
    }

    func reloadThemes() {
        let editor = ThemeStore.loadEditorThemes(in: themeRoot)
        let preview = ThemeStore.loadPreviewThemes(in: themeRoot)
        editorThemes = ThemeStore.merged(builtIn: EditorTheme.builtIn, user: editor.themes, name: \.name)
        previewThemes = ThemeStore.merged(builtIn: PreviewTheme.builtIn, user: preview.themes, name: \.name)
        themeProblems = editor.problems + preview.problems
    }

    func editorTheme(named name: String) -> EditorTheme {
        editorThemes.first { $0.name == name } ?? .tomorrowPlus
    }

    /// The preview theme with the zoom and width settings applied.
    var previewTheme: PreviewTheme {
        var theme = previewThemes.first { $0.name == settings.previewThemeName } ?? .github
        if settings.previewMaxWidth > 0 { theme = theme.withMaxContentWidth(settings.previewMaxWidth) }
        return theme.scaled(by: settings.previewZoom)
    }
}
