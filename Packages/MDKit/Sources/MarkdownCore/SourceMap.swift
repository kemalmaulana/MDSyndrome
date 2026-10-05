/// Which top-level block a source line belongs to, and where a block starts. This is what lets the editor
/// and the preview follow each other's scrolling.
///
/// The block list is not in source order: cmark moves footnote definitions to the end but they keep the
/// lines they were written on, so the map keeps its own copy sorted by first line.
public struct SourceMap: Hashable, Sendable {
    public static let empty = SourceMap(blocks: [])

    /// First line of each block, ascending (blocks that start on the same line keep their order).
    private let starts: [Int]
    private let ids: [BlockID]
    private let lineByID: [BlockID: Int]

    public init(blocks: [Block]) {
        let ordered = blocks.enumerated().sorted { ($0.element.lines.start, $0.offset) < ($1.element.lines.start, $1.offset) }
        starts = ordered.map { $0.element.lines.start }
        ids = ordered.map { $0.element.id }
        var lines: [BlockID: Int] = [:]
        for block in blocks where lines[block.id] == nil { lines[block.id] = block.lines.start }
        lineByID = lines
    }

    public var isEmpty: Bool { starts.isEmpty }

    /// The block that starts first in the source, and the line it starts on. Above that line there is nothing to scroll to.
    public var firstBlock: (id: BlockID, line: Int)? {
        starts.isEmpty ? nil : (ids[0], starts[0])
    }

    /// The top-level block that starts last on or before `line` (1-based). Blank lines between blocks belong
    /// to the block above; blocks that share their first line (an HTML block that became several) give the
    /// first of them. nil before the first block.
    public func blockID(atLine line: Int) -> BlockID? {
        let next = firstIndex(where: { $0 > line })
        guard next > 0 else { return nil }
        let start = starts[next - 1]
        return ids[firstIndex(where: { $0 >= start })]
    }

    /// The first source line of a top-level block.
    public func startLine(of id: BlockID) -> Int? {
        lineByID[id]
    }

    /// The first index whose start satisfies `predicate` (starts are ascending), or `starts.count`.
    private func firstIndex(where predicate: (Int) -> Bool) -> Int {
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if predicate(starts[middle]) { high = middle } else { low = middle + 1 }
        }
        return low
    }
}
