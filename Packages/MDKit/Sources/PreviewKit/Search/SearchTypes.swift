import MarkdownCore

/// Names one piece of text in the preview: the block it belongs to (by its first source line) and a
/// slot for blocks that hold several pieces (table cells, a `<details>` summary).
public struct SearchRunKey: Hashable, Sendable {
    public let line: Int
    public let slot: Int

    public init(line: Int, slot: Int) {
        self.line = line
        self.slot = slot
    }

    /// The summary of a `<details>` block shares its first line with whatever follows it on that line.
    static let summarySlot = -1

    /// Table cells: row 0 is the header, then one slot per cell.
    static func cell(line: Int, row: Int, column: Int) -> SearchRunKey {
        SearchRunKey(line: line, slot: row * 1_000 + column)
    }
}

/// The text of one run, as the preview draws it.
struct SearchRun: Sendable {
    let key: SearchRunKey
    /// The top-level block to scroll to.
    let topLevel: BlockID
    let text: String
}

public struct SearchMatch: Hashable, Sendable {
    public let key: SearchRunKey
    public let topLevel: BlockID
    /// Offsets in `Character`s of the run's text.
    public let range: Range<Int>
    /// Which match of its run this is (0-based).
    public let indexInRun: Int
}

/// What a text view needs to colour: a range of its run, and whether it is the match the user is on.
struct SearchHighlight: Hashable, Sendable {
    let range: Range<Int>
    let isCurrent: Bool
}
