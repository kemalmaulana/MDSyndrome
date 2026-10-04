public struct DocumentStats: Hashable, Sendable {
    /// Words in the rendered text (markdown syntax excluded).
    public let words: Int
    /// Characters in the source, newlines included.
    public let characters: Int
    /// Source lines; a trailing newline starts a new (empty) line, like the editor shows.
    public let lines: Int

    public init(words: Int, characters: Int, lines: Int) {
        self.words = words
        self.characters = characters
        self.lines = lines
    }

    /// 200 words per minute, rounded up; 0 for an empty document.
    public var readingMinutes: Int { (words + 199) / 200 }

    public static let empty = DocumentStats(words: 0, characters: 0, lines: 0)

    public static func make(source: String, document: MarkdownDocument) -> DocumentStats {
        DocumentStats(
            words: document.blocks.reduce(0) { $0 + wordCount($1) },
            characters: source.count,
            lines: source.isEmpty ? 0 : source.normalizedLineEndings.utf8.reduce(1) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
        )
    }

    private static func wordCount(_ block: Block) -> Int {
        switch block.kind {
        case .heading(_, let c), .paragraph(let c): count(Inline.plainText(c))
        case .blockQuote(let b), .footnoteDefinition(_, _, let b): b.reduce(0) { $0 + wordCount($1) }
        case .list(let list): list.items.reduce(0) { sum, item in item.blocks.reduce(sum) { $0 + wordCount($1) } }
        case .codeBlock(_, let code): count(code)
        case .table(let t): (t.header + t.rows.flatMap { $0 }).reduce(0) { $0 + count(Inline.plainText($1)) }
        case .thematicBreak, .htmlBlock, .mathBlock: 0
        }
    }

    private static func count(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
