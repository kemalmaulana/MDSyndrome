public struct OutlineItem: Hashable, Sendable, Identifiable {
    /// The heading block's id, usable as a scroll target.
    public let id: BlockID
    public let level: Int
    public let title: String
    public let slug: String
    public let line: Int
}

public enum Outline {
    /// Top-level headings only (headings nested in quotes/lists are not navigation targets).
    public static func make(from document: MarkdownDocument) -> [OutlineItem] {
        var slugger = Slugger()
        return document.blocks.compactMap { block in
            guard case .heading(let level, let content) = block.kind else { return nil }
            let title = Inline.plainText(content)
            return OutlineItem(id: block.id, level: level, title: title, slug: slugger.slug(title), line: block.lines.start)
        }
    }
}
