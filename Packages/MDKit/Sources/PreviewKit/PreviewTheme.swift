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
        error: ThemeColor(light: "#d1242f", dark: "#f85149"),
        syntax: .github
    )
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
    @Entry var listDepth: Int = 0
    /// Horizontal alignment of HTML-authored blocks (`<p align="center">`), read by image rows.
    @Entry var blockAlignment: BlockAlignment = .leading
}
