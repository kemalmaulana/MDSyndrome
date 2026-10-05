import Foundation
import MarkdownCore

/// Finds text in the preview. `runs(in:)` must list exactly the text the views draw, in the same
/// order and with the same keys, because the views look their highlights up by key; the views and
/// this file share `InlineRenderer.searchText` so the characters agree.
enum SearchIndex {
    /// Every piece of searchable text in `blocks`, in reading order. Math, images, raw HTML and front
    /// matter are left out: they are not text in the preview.
    static func runs(in blocks: [Block]) -> [SearchRun] {
        var runs: [SearchRun] = []
        for block in blocks { collect(block, topLevel: block.id, into: &runs) }
        return runs
    }

    private static func collect(_ block: Block, topLevel: BlockID, into runs: inout [SearchRun]) {
        let line = block.lines.start
        func add(_ slot: Int, _ text: String) {
            if !text.isEmpty { runs.append(SearchRun(key: SearchRunKey(line: line, slot: slot), topLevel: topLevel, text: text)) }
        }
        switch block.kind {
        case .heading(_, let content):
            add(0, InlineRenderer.searchText(content))
        case .htmlParagraph(_, _, let content):
            add(0, InlineRenderer.searchText(content))
        case .paragraph(let content):
            // A paragraph with images is laid out word by word (or as a row of pictures), not as one text.
            if !content.containsImage { add(0, InlineRenderer.searchText(content)) }
        case .codeBlock(_, let code):
            add(0, code)
        case .blockQuote(let children):
            for child in children { collect(child, topLevel: topLevel, into: &runs) }
        case .list(let list):
            for item in list.items { for child in item.blocks { collect(child, topLevel: topLevel, into: &runs) } }
        case .table(let table):
            for (column, cell) in table.header.enumerated() {
                add(SearchRunKey.cell(line: line, row: 0, column: column).slot, InlineRenderer.searchText(cell))
            }
            for (row, cells) in table.rows.enumerated() {
                for (column, cell) in cells.enumerated() {
                    add(SearchRunKey.cell(line: line, row: row + 1, column: column).slot, InlineRenderer.searchText(cell))
                }
            }
        case .footnoteDefinition(_, _, let children):
            for child in children { collect(child, topLevel: topLevel, into: &runs) }
        case .details(let summary, let isOpen, let children):
            add(SearchRunKey.summarySlot, InlineRenderer.searchText(summary))
            // A collapsed section hides its body, so its text is not searched until it is opened.
            if isOpen { for child in children { collect(child, topLevel: topLevel, into: &runs) } }
        case .thematicBreak, .htmlBlock, .mathBlock, .frontMatter:
            break
        }
    }

    /// Non-overlapping occurrences of `query` in `text`, as `Character` offsets. Without `caseSensitive`
    /// case and accents are ignored ("cafe" finds "Café").
    static func ranges(of query: String, in text: String, caseSensitive: Bool) -> [Range<Int>] {
        guard !query.isEmpty, !text.isEmpty else { return [] }
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive, .diacriticInsensitive]
        var result: [Range<Int>] = []
        var searchStart = text.startIndex
        var countedUpTo = text.startIndex
        var counted = 0
        while searchStart < text.endIndex, let found = text.range(of: query, options: options, range: searchStart..<text.endIndex), !found.isEmpty {
            // Offsets are counted from the previous match, so a long text is walked once.
            counted += text.distance(from: countedUpTo, to: found.lowerBound)
            let length = text.distance(from: found.lowerBound, to: found.upperBound)
            result.append(counted..<(counted + length))
            counted += length
            countedUpTo = found.upperBound
            searchStart = found.upperBound
        }
        return result
    }

    /// All matches in document order, at most `limit` of them (`truncated` says if more existed).
    static func search(query: String, caseSensitive: Bool, in blocks: [Block], limit: Int) -> (matches: [SearchMatch], truncated: Bool) {
        guard !query.isEmpty else { return ([], false) }
        var matches: [SearchMatch] = []
        for run in runs(in: blocks) {
            for (index, range) in ranges(of: query, in: run.text, caseSensitive: caseSensitive).enumerated() {
                if matches.count >= limit { return (matches, true) }
                matches.append(SearchMatch(key: run.key, topLevel: run.topLevel, range: range, indexInRun: index))
            }
        }
        return (matches, false)
    }
}
