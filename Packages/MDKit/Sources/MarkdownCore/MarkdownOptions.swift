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
    /// `==marked==` text.
    public var highlight = true
    /// YAML front matter at the top of the file shown as a table.
    public var frontMatter = true

    public init() {}

    public static let `default` = MarkdownOptions()
}
