/// Stable identity for a block. Derived from the block's source text plus a
/// duplicate counter, so unchanged blocks keep their id while the user edits
/// other parts of the document.
public struct BlockID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64
    public init(_ rawValue: UInt64) { self.rawValue = rawValue }
    public var description: String { String(rawValue, radix: 16) }
}

/// 1-based, inclusive line range in the original markdown source.
public struct SourceLines: Hashable, Sendable {
    public let start: Int
    public let end: Int
    public init(start: Int, end: Int) {
        self.start = start
        self.end = max(start, end)
    }
    public func contains(line: Int) -> Bool { line >= start && line <= end }
}

public struct MarkdownDocument: Hashable, Sendable {
    public let blocks: [Block]
    public init(blocks: [Block]) { self.blocks = blocks }
}

public struct Block: Hashable, Sendable, Identifiable {
    public let id: BlockID
    public let lines: SourceLines
    public let kind: Kind

    public init(id: BlockID, lines: SourceLines, kind: Kind) {
        self.id = id
        self.lines = lines
        self.kind = kind
    }

    public enum Kind: Hashable, Sendable {
        case heading(level: Int, content: [Inline])
        case paragraph([Inline])
        case blockQuote([Block])
        case list(ListBlock)
        case codeBlock(language: String?, code: String)
        case thematicBreak
        case htmlBlock(String)
        case table(TableBlock)
        case mathBlock(latex: String)
        case footnoteDefinition(index: Int, label: String, blocks: [Block])
        /// YAML front matter at the top of the document.
        case frontMatter([FrontMatterEntry])
        /// `<details><summary>…` — a collapsible section.
        case details(summary: [Inline], isOpen: Bool, blocks: [Block])
        /// A paragraph (level 0) or heading (1…6) written as HTML, e.g. `<p align="center">`.
        case htmlParagraph(level: Int, alignment: BlockAlignment, content: [Inline])
    }
}

public enum BlockAlignment: Hashable, Sendable { case leading, center, trailing }

public struct ListBlock: Hashable, Sendable {
    public let ordered: Bool
    public let start: Int
    public let tight: Bool
    public let items: [ListItem]
}

public struct ListItem: Hashable, Sendable, Identifiable {
    public let id: BlockID
    public let lines: SourceLines
    /// nil when the item is not a GFM task item.
    public let task: TaskState?
    public let blocks: [Block]
}

public enum TaskState: Hashable, Sendable { case checked, unchecked }

public struct TableBlock: Hashable, Sendable {
    public enum Alignment: Hashable, Sendable { case none, left, center, right }
    public let alignments: [Alignment]
    /// One entry per column.
    public let header: [[Inline]]
    /// rows → cells → inlines. Every row has exactly `alignments.count` cells.
    public let rows: [[[Inline]]]
}

public enum Inline: Hashable, Sendable {
    case text(String)
    case emphasis([Inline])
    case strong([Inline])
    case strikethrough([Inline])
    case code(String)
    case link(destination: String, title: String?, content: [Inline])
    /// `width` comes from HTML `<img width>`; Markdown images have none.
    case image(source: String, title: String?, alt: String, width: Double? = nil)
    case softBreak
    case lineBreak
    case html(String)
    case math(latex: String, display: Bool)
    case footnoteReference(index: Int)
    /// `==marked==` or `<mark>`.
    case highlight([Inline])
    case superscript([Inline])
    case `subscript`([Inline])
    case underline([Inline])
    /// `<kbd>`.
    case keyboard([Inline])
}

extension Inline {
    /// Rendered text without formatting: used for alt text, slugs, outline titles, word counts.
    public static func plainText(_ inlines: [Inline]) -> String {
        inlines.map(\.plainText).joined()
    }

    public var plainText: String {
        switch self {
        case .text(let s), .code(let s): s
        case .emphasis(let c), .strong(let c), .strikethrough(let c), .highlight(let c),
             .superscript(let c), .subscript(let c), .underline(let c), .keyboard(let c): Inline.plainText(c)
        case .link(_, _, let c): Inline.plainText(c)
        case .image(_, _, let alt, _): alt
        case .softBreak, .lineBreak: " "
        case .html: ""
        case .math(let latex, _): latex
        case .footnoteReference(let i): "[\(i)]"
        }
    }
}
