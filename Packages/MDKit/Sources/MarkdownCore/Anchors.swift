import Foundation

/// A heading found anywhere in a document, in document order.
struct HeadingEntry {
    let text: String
    let level: Int
    let slug: String
    /// The heading's own block.
    let id: BlockID
    /// The top-level block that contains it (itself, for a top-level heading).
    let topLevelID: BlockID
    let isTopLevel: Bool
    let line: Int
}

enum HeadingWalk {
    /// Every heading, whether at the top level, in a quote, a list item, a `<details>` or a footnote, plus
    /// headings written as HTML (`<h2>`). Slugs come from one `Slugger` over the whole walk, because GitHub
    /// numbers duplicates across the document, not per nesting level.
    static func headings(in blocks: [Block]) -> [HeadingEntry] {
        var slugger = Slugger()
        var found: [HeadingEntry] = []
        walk(blocks, top: nil, slugger: &slugger, into: &found)
        return found
    }

    private static func walk(_ blocks: [Block], top: BlockID?, slugger: inout Slugger, into found: inout [HeadingEntry]) {
        for block in blocks {
            let topID = top ?? block.id
            var heading: (level: Int, content: [Inline])?
            switch block.kind {
            case .heading(let level, let content):
                heading = (level, content)
            case .htmlParagraph(let level, _, let content):
                if level > 0 { heading = (level, content) }
            case .blockQuote(let children), .details(_, _, let children), .footnoteDefinition(_, _, let children):
                walk(children, top: topID, slugger: &slugger, into: &found)
            case .list(let list):
                for item in list.items { walk(item.blocks, top: topID, slugger: &slugger, into: &found) }
            default:
                break
            }
            if let heading {
                let text = Inline.plainText(heading.content)
                found.append(HeadingEntry(text: text, level: heading.level, slug: slugger.slug(text), id: block.id, topLevelID: topID,
                                          isTopLevel: top == nil, line: block.lines.start))
            }
        }
    }
}

/// Where a `#fragment` link points inside the document.
public struct DocumentAnchors: Hashable, Sendable {
    public static let empty = DocumentAnchors(blocks: [])

    private let targets: [String: BlockID]

    public init(blocks: [Block]) {
        var targets: [String: BlockID] = [:]
        for heading in HeadingWalk.headings(in: blocks) where targets[heading.slug] == nil {
            targets[heading.slug] = heading.topLevelID
        }
        for block in blocks {
            if case .footnoteDefinition(let index, _, _) = block.kind { targets["fn-\(index)"] = block.id }
        }
        var referenced = Set<Int>()
        for block in blocks {
            Self.forEachFootnoteReference(in: block) { index in
                if referenced.insert(index).inserted { targets["fnref-\(index)"] = block.id }
            }
        }
        self.targets = targets
    }

    /// The block `fragment` refers to: a heading slug (GitHub's rules; the match ignores case and
    /// percent-encoding), `fn-N` (footnote N's definition) or `fnref-N` (the block with its first reference).
    /// A leading `#` is accepted. nil when nothing matches.
    public func target(for fragment: String) -> BlockID? {
        var name = fragment
        if name.hasPrefix("#") { name.removeFirst() }
        name = name.removingPercentEncoding ?? name
        guard !name.isEmpty else { return nil }
        return targets[name.lowercased()]
    }

    // MARK: Footnote references

    private static func forEachFootnoteReference(in block: Block, _ body: (Int) -> Void) {
        switch block.kind {
        case .heading(_, let content), .paragraph(let content), .htmlParagraph(_, _, let content):
            forEachFootnoteReference(in: content, body)
        case .blockQuote(let children), .footnoteDefinition(_, _, let children):
            for child in children { forEachFootnoteReference(in: child, body) }
        case .details(let summary, _, let children):
            forEachFootnoteReference(in: summary, body)
            for child in children { forEachFootnoteReference(in: child, body) }
        case .list(let list):
            for item in list.items { for child in item.blocks { forEachFootnoteReference(in: child, body) } }
        case .table(let table):
            for cell in table.header { forEachFootnoteReference(in: cell, body) }
            for row in table.rows { for cell in row { forEachFootnoteReference(in: cell, body) } }
        case .codeBlock, .thematicBreak, .htmlBlock, .mathBlock, .frontMatter:
            break
        }
    }

    private static func forEachFootnoteReference(in inlines: [Inline], _ body: (Int) -> Void) {
        for inline in inlines {
            switch inline {
            case .footnoteReference(let index):
                body(index)
            case .emphasis(let content), .strong(let content), .strikethrough(let content), .highlight(let content),
                 .superscript(let content), .subscript(let content), .underline(let content), .keyboard(let content),
                 .link(_, _, let content):
                forEachFootnoteReference(in: content, body)
            case .text, .code, .image, .softBreak, .lineBreak, .html, .math:
                break
            }
        }
    }
}
