import EditorKit
import Foundation
import os
import PreviewKit

/// User themes: JSON files in `~/Library/Application Support/MDSyndrome/Themes/Editor` and `…/Preview`, one theme
/// per file in the same shape as the built-in ones. A file that does not decode is skipped and logged; it never
/// stops the app or the other themes (PRD §7).
enum ThemeStore {
    private static let log = Logger(subsystem: "com.kemalmaulana.mdsyndrome", category: "themes")

    struct Loaded<Theme> {
        var themes: [Theme] = []
        /// One line per file that was skipped, with the reason.
        var problems: [String] = []
    }

    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MDSyndrome/Themes", isDirectory: true)
    }

    static func loadEditorThemes(in root: URL = defaultFolder) -> Loaded<EditorTheme> {
        load(EditorTheme.self, from: root.appendingPathComponent("Editor", isDirectory: true), name: \.name)
    }

    static func loadPreviewThemes(in root: URL = defaultFolder) -> Loaded<PreviewTheme> {
        load(PreviewTheme.self, from: root.appendingPathComponent("Preview", isDirectory: true), name: \.name)
    }

    /// The built-in themes with the user's added; a user theme with a built-in's name replaces it.
    static func merged<Theme>(builtIn: [Theme], user: [Theme], name: KeyPath<Theme, String>) -> [Theme] {
        let replaced = Set(user.map { $0[keyPath: name] })
        return builtIn.filter { !replaced.contains($0[keyPath: name]) } + user
    }

    /// Creates the folders (so "Reveal" has something to show) and returns the root.
    @discardableResult
    static func ensureFolders(in root: URL = defaultFolder) -> URL {
        for kind in ["Editor", "Preview"] {
            try? FileManager.default.createDirectory(at: root.appendingPathComponent(kind, isDirectory: true), withIntermediateDirectories: true)
        }
        return root
    }

    private static func load<Theme: Decodable>(_ type: Theme.Type, from folder: URL, name: KeyPath<Theme, String>) -> Loaded<Theme> {
        var result = Loaded<Theme>()
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return result }
        var seen = Set<String>()
        for file in files.filter({ $0.pathExtension.lowercased() == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let theme = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: file))
                let themeName = theme[keyPath: name]
                guard !themeName.isEmpty else { throw CocoaError(.coderValueNotFound, userInfo: [NSLocalizedDescriptionKey: "the theme has no name"]) }
                guard seen.insert(themeName).inserted else { throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "another file already defines “\(themeName)”"]) }
                result.themes.append(theme)
            } catch {
                result.problems.append("\(file.lastPathComponent): \(error.localizedDescription)")
                log.error("Skipped theme \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return result
    }
}
