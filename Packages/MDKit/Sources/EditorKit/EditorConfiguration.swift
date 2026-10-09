import AppKit

/// Editor appearance and typing behaviour. Defaults match the user's MacDown preferences.
public struct EditorConfiguration: Hashable, Sendable {
    public var fontName = "Menlo-Regular"
    public var fontSize: Double = 14
    public var lineSpacing: Double = 3
    public var horizontalInset: Double = 15
    public var verticalInset: Double = 30
    /// Text is kept this wide (points) and centred when the window is wider; 0 uses the whole width (ED-4).
    public var maxTextWidth: Double = 0

    /// Typing `(` inserts `()`, `"` inserts `""`, and so on (ED-7).
    public var autoPair = true
    /// Return continues a list item or quote; Return on an empty one ends it (ED-5).
    public var continueLists = true
    /// Return in the middle of an ordered list renumbers the items after it (ED-5).
    public var renumberLists = true
    /// Long lines wrap at the window edge; off, the editor scrolls sideways (ED-4).
    public var softWrap = true
    /// Underline misspelled words while typing (ED-4). Off by default: Markdown is full of symbols.
    public var spellCheck = false
    /// What Tab inserts and ⇧Tab removes (ED-6).
    public var indentUnit = "    "
    /// Where pasted and dropped images are saved, relative to the document's folder; empty means that folder itself (ED-11).
    public var imageFolder = "assets"

    public init() {}

    public static let macDownDefaults = EditorConfiguration()

    public var font: NSFont {
        NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return style
    }

    /// The attributes of ordinary text before any Markdown colouring.
    func textAttributes(foreground: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: font, .paragraphStyle: paragraphStyle, .foregroundColor: foreground]
    }
}
