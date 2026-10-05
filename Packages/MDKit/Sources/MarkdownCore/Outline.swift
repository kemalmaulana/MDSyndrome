public struct OutlineItem: Hashable, Sendable, Identifiable {
    /// The heading block's id, usable as a scroll target.
    public let id: BlockID
    public let level: Int
    public let title: String
    public let slug: String
    public let line: Int
}

public enum Outline {
    /// Top-level headings (including headings written as HTML such as `<h1 align="center">`); headings nested in
    /// quotes or lists are anchors but not outline entries. Slugs come from the same walk as the anchors, so
    /// they number duplicates the way GitHub does.
    public static func make(from document: MarkdownDocument) -> [OutlineItem] {
        HeadingWalk.headings(in: document.blocks).filter(\.isTopLevel).map {
            OutlineItem(id: $0.id, level: $0.level, title: $0.text, slug: $0.slug, line: $0.line)
        }
    }

    /// The heading a document is at when its first visible line is `line` (1-based): the last item that starts on or
    /// before it. nil above the first heading. `items` are in document order, as `make(from:)` returns them.
    public static func current(in items: [OutlineItem], atLine line: Int) -> OutlineItem? {
        var low = 0
        var high = items.count
        while low < high {
            let middle = (low + high) / 2
            if items[middle].line <= line { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : items[low - 1]
    }
}
