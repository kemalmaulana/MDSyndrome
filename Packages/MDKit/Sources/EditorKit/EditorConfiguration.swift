import AppKit

/// Editor appearance and typing behaviour. Defaults match the user's MacDown preferences.
public struct EditorConfiguration: Hashable, Sendable {
    public var fontName = "Menlo-Regular"
    public var fontSize: Double = 14
    public var lineSpacing: Double = 3
    public var horizontalInset: Double = 15
    public var verticalInset: Double = 30

    /// Typing `(` inserts `()`, `"` inserts `""`, and so on (ED-7).
    public var autoPair = true
    /// Return continues a list item or quote; Return on an empty one ends it (ED-5).
    public var continueLists = true
    /// Return in the middle of an ordered list renumbers the items after it (ED-5).
    public var renumberLists = true
    /// What Tab inserts and ⇧Tab removes (ED-6).
    public var indentUnit = "    "

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
