import AppKit
import MarkdownCore
import SwiftUI
import SyntaxHighlighting

/// A color with light and dark variants, stored as hex so themes can be JSON files.
public struct ThemeColor: Codable, Hashable, Sendable {
    public var light: String
    public var dark: String

    public init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }

    public var color: Color { Color(nsColor: nsColor) }

    public var nsColor: NSColor {
        let light = Self.nsColor(hex: light)
        let dark = Self.nsColor(hex: dark)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA` into 0…1 components. Returns nil for anything else.
    public static func rgba(hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let rgba = digits.count == 6 ? (value << 8) | 0xff : value
        return (
            Double((rgba >> 24) & 0xff) / 255,
            Double((rgba >> 16) & 0xff) / 255,
            Double((rgba >> 8) & 0xff) / 255,
            Double(rgba & 0xff) / 255
        )
    }

    private static func nsColor(hex: String) -> NSColor {
        guard let c = rgba(hex: hex) else { return .labelColor }
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}

public struct PreviewTheme: Codable, Hashable, Sendable {
    public var name: String
    public var bodyFontSize: Double
    public var codeFontScale: Double
    public var lineSpacing: Double
    public var blockSpacing: Double
    public var maxContentWidth: Double
    /// Multipliers of `bodyFontSize` for h1…h6.
    public var headingScales: [Double]
    public var background: ThemeColor
    public var text: ThemeColor
    public var secondaryText: ThemeColor
    public var link: ThemeColor
    public var codeBackground: ThemeColor
    public var border: ThemeColor
    public var blockQuoteBar: ThemeColor
    public var tableStripe: ThemeColor
    /// `==marked==` / `<mark>` background.
    public var highlightBackground: ThemeColor
    /// Find in preview: every match, and the one the user is on.
    public var searchMatchBackground: ThemeColor
    public var searchCurrentBackground: ThemeColor
    /// LaTeX that could not be typeset, and similar inline errors.
    public var error: ThemeColor
    public var syntax: SyntaxPalette

    public func headingSize(level: Int) -> Double {
        bodyFontSize * headingScales[min(max(level, 1), headingScales.count) - 1]
    }

    public var codeFontSize: Double { bodyFontSize * codeFontScale }

    public static let github = PreviewTheme(
        name: "GitHub",
        bodyFontSize: 16,
        codeFontScale: 0.85,
        lineSpacing: 4,
        blockSpacing: 16,
        maxContentWidth: 880,
        headingScales: [2, 1.5, 1.25, 1, 0.875, 0.85],
        background: ThemeColor(light: "#ffffff", dark: "#0d1117"),
        text: ThemeColor(light: "#1f2328", dark: "#e6edf3"),
        secondaryText: ThemeColor(light: "#59636e", dark: "#9198a1"),
        link: ThemeColor(light: "#0969da", dark: "#4493f8"),
        codeBackground: ThemeColor(light: "#818b981f", dark: "#656c7633"),
        border: ThemeColor(light: "#d1d9e0", dark: "#3d444d"),
        blockQuoteBar: ThemeColor(light: "#d1d9e0", dark: "#3d444d"),
        tableStripe: ThemeColor(light: "#f6f8fa", dark: "#151b23"),
        highlightBackground: ThemeColor(light: "#fff8c5", dark: "#bb800926"),
        searchMatchBackground: ThemeColor(light: "#ffe58f", dark: "#9a6700b3"),
        searchCurrentBackground: ThemeColor(light: "#ff9632", dark: "#d4a72c"),
        error: ThemeColor(light: "#d1242f", dark: "#f85149"),
        syntax: .github
    )
}

extension PreviewTheme {
    /// The `UserDefaults` key under which the app remembers the chosen preview theme's name.
    public static let storageKey = "previewTheme"

    /// Smaller or larger text for ⌘+ / ⌘− (PV-9): sizes and spacing scale together, the content width does not.
    public func scaled(by zoom: Double) -> PreviewTheme {
        var theme = self
        theme.bodyFontSize *= zoom
        theme.lineSpacing *= zoom
        theme.blockSpacing *= zoom
        return theme
    }

    public func withMaxContentWidth(_ width: Double) -> PreviewTheme {
        var theme = self
        theme.maxContentWidth = width
        return theme
    }

    /// Soft paper colours and a roomier layout, after MacDown's Clearness.
    public static let clearness: PreviewTheme = {
        var theme = PreviewTheme.github
        theme.name = "Clearness"
        theme.bodyFontSize = 15
        theme.lineSpacing = 6
        theme.blockSpacing = 18
        theme.maxContentWidth = 760
        theme.headingScales = [1.9, 1.5, 1.25, 1.1, 1, 0.9]
        theme.background = ThemeColor(light: "#fdfdfc", dark: "#1c1c1e")
        theme.text = ThemeColor(light: "#333333", dark: "#d8d8d8")
        theme.secondaryText = ThemeColor(light: "#777777", dark: "#8e8e93")
        theme.link = ThemeColor(light: "#4183c4", dark: "#6cb0f0")
        theme.codeBackground = ThemeColor(light: "#f3f3f1", dark: "#2a2a2c")
        theme.border = ThemeColor(light: "#dddddd", dark: "#3a3a3c")
        theme.blockQuoteBar = ThemeColor(light: "#dddddd", dark: "#48484a")
        theme.tableStripe = ThemeColor(light: "#f8f8f6", dark: "#232325")
        return theme
    }()

    /// Solarized: cream paper by day, deep teal by night.
    public static let solarized: PreviewTheme = {
        var theme = PreviewTheme.github
        theme.name = "Solarized"
        theme.background = ThemeColor(light: "#fdf6e3", dark: "#002b36")
        theme.text = ThemeColor(light: "#586e75", dark: "#93a1a1")
        theme.secondaryText = ThemeColor(light: "#93a1a1", dark: "#657b83")
        theme.link = ThemeColor(light: "#268bd2", dark: "#268bd2")
        theme.codeBackground = ThemeColor(light: "#eee8d5", dark: "#073642")
        theme.border = ThemeColor(light: "#eee8d5", dark: "#073642")
        theme.blockQuoteBar = ThemeColor(light: "#93a1a1", dark: "#586e75")
        theme.tableStripe = ThemeColor(light: "#f5eedb", dark: "#04323e")
        theme.highlightBackground = ThemeColor(light: "#b5890059", dark: "#b5890040")
        theme.error = ThemeColor(light: "#dc322f", dark: "#dc322f")
        return theme
    }()

    /// Neutral macOS look: system-like greys, blue links.
    public static let system: PreviewTheme = {
        var theme = PreviewTheme.github
        theme.name = "System"
        theme.bodyFontSize = 14
        theme.maxContentWidth = 820
        theme.background = ThemeColor(light: "#ffffff", dark: "#1e1e1e")
        theme.text = ThemeColor(light: "#1d1d1f", dark: "#f5f5f7")
        theme.secondaryText = ThemeColor(light: "#6e6e73", dark: "#98989d")
        theme.link = ThemeColor(light: "#0066cc", dark: "#2997ff")
        theme.codeBackground = ThemeColor(light: "#f2f2f4", dark: "#2c2c2e")
        theme.border = ThemeColor(light: "#d2d2d7", dark: "#424245")
        theme.blockQuoteBar = ThemeColor(light: "#c7c7cc", dark: "#48484a")
        theme.tableStripe = ThemeColor(light: "#f5f5f7", dark: "#252527")
        return theme
    }()

    public static let builtIn: [PreviewTheme] = [.github, .clearness, .solarized, .system]

    /// A built-in theme by name; an unknown name gives GitHub, the default.
    public static func named(_ name: String) -> PreviewTheme {
        builtIn.first { $0.name == name } ?? .github
    }
}

/// Code-block colours per token kind (light + dark), GitHub Primer palette by default.
public struct SyntaxPalette: Codable, Hashable, Sendable {
    public var keyword: ThemeColor
    public var type: ThemeColor
    public var literal: ThemeColor
    public var string: ThemeColor
    public var number: ThemeColor
    public var comment: ThemeColor
    public var attribute: ThemeColor
    public var tag: ThemeColor
    public var inserted: ThemeColor
    public var deleted: ThemeColor
    public var meta: ThemeColor

    public func color(for kind: TokenKind) -> ThemeColor {
        switch kind {
        case .keyword: keyword
        case .type: type
        case .literal: literal
        case .string: string
        case .number: number
        case .comment: comment
        case .attribute: attribute
        case .tag: tag
        case .inserted: inserted
        case .deleted: deleted
        case .meta: meta
        }
    }

    public static let github = SyntaxPalette(
        keyword: ThemeColor(light: "#cf222e", dark: "#ff7b72"),
        type: ThemeColor(light: "#953800", dark: "#ffa657"),
        literal: ThemeColor(light: "#0550ae", dark: "#79c0ff"),
        string: ThemeColor(light: "#0a3069", dark: "#a5d6ff"),
        number: ThemeColor(light: "#0550ae", dark: "#79c0ff"),
        comment: ThemeColor(light: "#59636e", dark: "#9198a1"),
        attribute: ThemeColor(light: "#8250df", dark: "#d2a8ff"),
        tag: ThemeColor(light: "#116329", dark: "#7ee787"),
        inserted: ThemeColor(light: "#116329", dark: "#3fb950"),
        deleted: ThemeColor(light: "#82071e", dark: "#f85149"),
        meta: ThemeColor(light: "#8250df", dark: "#d2a8ff")
    )
}

extension EnvironmentValues {
    @Entry public var previewTheme: PreviewTheme = .github
    /// Folder of the open document; relative image paths resolve against it. nil for unsaved documents.
    @Entry public var documentBaseURL: URL? = nil
    /// Bumped when the user reloads the document from disk (⌘R). Images load again when it changes,
    /// since the Markdown can stay the same while a picture on disk changed.
    @Entry public var previewReloadToken: Int = 0
    @Entry var listDepth: Int = 0
    /// False keeps remote images (`http`/`https`) from being fetched; they show as broken images.
    @Entry public var loadRemoteImages: Bool = true
    /// Handles a click on a task item's checkbox; nil leaves checkboxes as pictures.
    @Entry var toggleTask: TaskToggleHandler? = nil
    /// Horizontal alignment of HTML-authored blocks (`<p align="center">`), read by image rows.
    @Entry var blockAlignment: BlockAlignment = .leading
}

/// The checkbox handler, wrapped so the environment can compare it. The closure is rebuilt on every update of the
/// window but does the same thing each time, so two handlers count as equal and an update does not invalidate
/// every list in the preview.
struct TaskToggleHandler: Equatable {
    /// Gets the source line of the item.
    let run: (Int) -> Void

    static func == (lhs: TaskToggleHandler, rhs: TaskToggleHandler) -> Bool { true }
}
