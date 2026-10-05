import AppKit

/// How one kind of Markdown source is drawn. Unset fields fall back to the editor's base style.
public struct EditorTokenStyle: Codable, Hashable, Sendable {
    public var color: String?
    public var background: String?
    public var bold: Bool?
    public var italic: Bool?
    /// Multiplier of the editor font size (MacDown's "+" themes enlarge headings).
    public var sizeScale: Double?

    public init(color: String? = nil, background: String? = nil, bold: Bool? = nil, italic: Bool? = nil, sizeScale: Double? = nil) {
        self.color = color
        self.background = background
        self.bold = bold
        self.italic = italic
        self.sizeScale = sizeScale
    }
}

/// An editor colour theme. Codable so user themes can be JSON files (Plan 6); the built-ins follow
/// MacDown's themes of the same names.
public struct EditorTheme: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var background: String
    public var foreground: String
    public var caret: String
    public var selectionBackground: String?
    public var selectionForeground: String?
    /// Keyed by `EditorTokenKind.rawValue`.
    public var styles: [String: EditorTokenStyle]

    public var id: String { name }

    /// The `@AppStorage` key under which the app remembers the chosen theme's name.
    public static let storageKey = "editorTheme"

    /// Whether the editor background is dark, so scrollers, the find bar and menus can match it.
    public var isDark: Bool {
        guard let color = editorColor(background)?.usingColorSpace(.sRGB) else { return false }
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance < 0.5
    }

    public func style(for kind: EditorTokenKind) -> EditorTokenStyle? {
        styles[kind.rawValue]
    }

    /// Built-in theme by name; unknown names give Tomorrow+ (the user's MacDown default).
    public static func named(_ name: String) -> EditorTheme {
        builtIn.first { $0.name == name } ?? .tomorrowPlus
    }

    public static let builtIn: [EditorTheme] = [.tomorrowPlus, .tomorrow, .solarizedLight, .solarizedDark, .mouPaper, .writer]

    /// MacDown's "+" heading sizes (24/20/17/15/13/11 px against a 14 px body).
    private static let plusScales: [Double] = [24, 20, 17, 15, 13, 11].map { $0 / 14 }

    private static func styles(
        heading: String?, headingBold: [Bool], headingScales: [Double]? = nil,
        emphasis: String?, strong: String?, rule: String?, list: String?, link: String?, reference: String?,
        image: String?, code: String?, codeBackground: String? = nil, entity: String?, comment: String?, quote: String?,
        highlight: String
    ) -> [String: EditorTokenStyle] {
        var s: [String: EditorTokenStyle] = [:]
        let headings: [EditorTokenKind] = [.heading1, .heading2, .heading3, .heading4, .heading5, .heading6]
        for (i, kind) in headings.enumerated() {
            s[kind.rawValue] = EditorTokenStyle(color: heading, bold: headingBold[i], sizeScale: headingScales?[i])
        }
        s[EditorTokenKind.emphasis.rawValue] = EditorTokenStyle(color: emphasis, italic: true)
        s[EditorTokenKind.strong.rawValue] = EditorTokenStyle(color: strong, bold: true)
        s[EditorTokenKind.strikethrough.rawValue] = EditorTokenStyle(color: comment)
        s[EditorTokenKind.highlight.rawValue] = EditorTokenStyle(background: highlight)
        s[EditorTokenKind.horizontalRule.rawValue] = EditorTokenStyle(color: rule)
        s[EditorTokenKind.listMarker.rawValue] = EditorTokenStyle(color: list)
        s[EditorTokenKind.taskMarker.rawValue] = EditorTokenStyle(color: list)
        s[EditorTokenKind.link.rawValue] = EditorTokenStyle(color: link)
        s[EditorTokenKind.url.rawValue] = EditorTokenStyle(color: link)
        s[EditorTokenKind.reference.rawValue] = EditorTokenStyle(color: reference)
        s[EditorTokenKind.image.rawValue] = EditorTokenStyle(color: image)
        s[EditorTokenKind.code.rawValue] = EditorTokenStyle(color: code, background: codeBackground)
        s[EditorTokenKind.codeBlock.rawValue] = EditorTokenStyle(color: code, background: codeBackground)
        s[EditorTokenKind.math.rawValue] = EditorTokenStyle(color: code)
        s[EditorTokenKind.frontMatter.rawValue] = EditorTokenStyle(color: comment)
        s[EditorTokenKind.htmlEntity.rawValue] = EditorTokenStyle(color: entity)
        s[EditorTokenKind.html.rawValue] = EditorTokenStyle(color: entity)
        s[EditorTokenKind.comment.rawValue] = EditorTokenStyle(color: comment)
        s[EditorTokenKind.blockquote.rawValue] = EditorTokenStyle(color: quote)
        return s
    }

    public static let tomorrowPlus = EditorTheme(
        name: "Tomorrow+", background: "#2d2d2d", foreground: "#cccccc", caret: "#cc99cc",
        selectionBackground: "#515151", selectionForeground: "#ffffff",
        styles: styles(heading: "#66cccc", headingBold: [true, true, false, false, false, false], headingScales: plusScales,
                       emphasis: "#ffcc66", strong: "#f99157", rule: "#999999", list: "#6699cc", link: "#99cc99", reference: "#66cccc",
                       image: "#cc99cc", code: "#999999", entity: "#cc99cc", comment: "#888888", quote: "#f2777a", highlight: "#ffcc6640"))

    public static let tomorrow = EditorTheme(
        name: "Tomorrow", background: "#2d2d2d", foreground: "#cccccc", caret: "#cc99cc",
        selectionBackground: "#515151", selectionForeground: "#ffffff",
        styles: styles(heading: "#66cccc", headingBold: Array(repeating: true, count: 6),
                       emphasis: "#ffcc66", strong: "#f99157", rule: "#999999", list: "#6699cc", link: "#99cc99", reference: "#66cccc",
                       image: "#cc99cc", code: "#999999", entity: "#cc99cc", comment: "#888888", quote: "#f2777a", highlight: "#ffcc6640"))

    public static let solarizedLight = EditorTheme(
        name: "Solarized (Light)", background: "#fdf6e3", foreground: "#657b83", caret: "#002b36",
        selectionBackground: "#d33682", selectionForeground: "#fdf6e3",
        styles: styles(heading: "#b58900", headingBold: Array(repeating: false, count: 6),
                       emphasis: "#586e75", strong: "#586e75", rule: "#b58900", list: "#93a1a1", link: "#268bd2", reference: "#6c71c4",
                       image: "#cb4b16", code: "#586e75", codeBackground: "#eee8d5", entity: "#93a1a1", comment: "#93a1a1", quote: "#657b83",
                       highlight: "#b5890033"))

    public static let solarizedDark = EditorTheme(
        name: "Solarized (Dark)", background: "#002b36", foreground: "#839496", caret: "#fdf6e3",
        selectionBackground: "#d33682", selectionForeground: "#002b36",
        styles: styles(heading: "#b58900", headingBold: Array(repeating: false, count: 6),
                       emphasis: "#93a1a1", strong: "#93a1a1", rule: "#b58900", list: "#586e75", link: "#268bd2", reference: "#6c71c4",
                       image: "#cb4b16", code: "#93a1a1", codeBackground: "#073642", entity: "#586e75", comment: "#586e75", quote: "#839496",
                       highlight: "#b5890040"))

    public static let mouPaper = EditorTheme(
        name: "Mou Paper", background: "#ffffff", foreground: "#000000", caret: "#000000",
        styles: styles(heading: nil, headingBold: Array(repeating: true, count: 6),
                       emphasis: nil, strong: nil, rule: "#555555", list: "#bbbbbb", link: "#555555", reference: "#555555",
                       image: "#555555", code: "#555555", entity: "#555555", comment: "#bbbbbb", quote: "#bbbbbb", highlight: "#fff3a0"))

    public static let writer = EditorTheme(
        name: "Writer", background: "#fafafa", foreground: "#424242", caret: "#00b9ff",
        styles: styles(heading: nil, headingBold: Array(repeating: true, count: 6),
                       emphasis: nil, strong: nil, rule: "#555555", list: "#bbbbbb", link: "#555555", reference: "#555555",
                       image: "#555555", code: "#555555", entity: "#555555", comment: "#bbbbbb", quote: "#bbbbbb", highlight: "#fff3a0"))
}

/// `#RRGGBB` / `#RRGGBBAA` → NSColor (sRGB). Invalid strings give nil.
func editorColor(_ hex: String?) -> NSColor? {
    guard var digits = hex else { return nil }
    if digits.hasPrefix("#") { digits.removeFirst() }
    guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
    let rgba = digits.count == 6 ? (value << 8) | 0xff : value
    return NSColor(srgbRed: Double((rgba >> 24) & 0xff) / 255, green: Double((rgba >> 16) & 0xff) / 255,
                   blue: Double((rgba >> 8) & 0xff) / 255, alpha: Double(rgba & 0xff) / 255)
}
