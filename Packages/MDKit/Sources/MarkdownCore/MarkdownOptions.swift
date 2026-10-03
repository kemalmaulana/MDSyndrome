/// Parser feature switches. Mirrors the Settings → Markdown tab.
public struct MarkdownOptions: Hashable, Sendable {
    public var tables = true
    public var taskLists = true
    public var strikethrough = true
    public var autolinks = true
    public var footnotes = true
    public var math = true
    public var singleDollarMath = true
    public var smartPunctuation = false
    public var hardBreaks = false

    public init() {}

    public static let `default` = MarkdownOptions()
}
