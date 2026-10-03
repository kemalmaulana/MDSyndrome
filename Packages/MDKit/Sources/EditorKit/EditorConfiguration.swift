import AppKit

/// Editor appearance. Defaults match the user's MacDown preferences.
public struct EditorConfiguration: Hashable, Sendable {
    public var fontName = "Menlo-Regular"
    public var fontSize: Double = 14
    public var lineSpacing: Double = 3
    public var horizontalInset: Double = 15
    public var verticalInset: Double = 30

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

    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .paragraphStyle: paragraphStyle, .foregroundColor: NSColor.textColor]
    }
}
