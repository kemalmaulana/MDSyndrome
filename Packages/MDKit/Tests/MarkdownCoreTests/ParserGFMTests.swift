import Testing
@testable import MarkdownCore

@Suite struct ParserGFMTests {
    @Test func tableAlignmentsHeaderAndRows() throws {
        let md = """
        | a | b | c | d |
        |:--|:-:|--:|---|
        | 1 | 2 | 3 | 4 |
        | x |
        """
        let block = try #require(MarkdownParser.parse(md).blocks.first)
        guard case .table(let table) = block.kind else { Issue.record("not a table"); return }
        #expect(table.alignments == [.left, .center, .right, .none])
        #expect(table.header == [[.text("a")], [.text("b")], [.text("c")], [.text("d")]])
        #expect(table.rows.count == 2)
        #expect(table.rows[1] == [[.text("x")], [], [], []], "short rows are padded to the column count")
    }

    @Test func taskItems() throws {
        let block = try #require(MarkdownParser.parse("- [x] done\n- [ ] todo\n- plain").blocks.first)
        guard case .list(let list) = block.kind else { Issue.record("not a list"); return }
        #expect(list.items.map(\.task) == [.checked, .unchecked, nil])
    }

    @Test func footnotesAreNumberedInReferenceOrder() {
        let md = """
        First[^b] then[^a].

        [^a]: Alpha.
        [^b]: Beta.
        """
        let blocks = MarkdownParser.parse(md).blocks
        #expect(blocks[0].kind == .paragraph([
            .text("First"), .footnoteReference(index: 1), .text(" then"), .footnoteReference(index: 2), .text("."),
        ]))
        guard case .footnoteDefinition(1, "b", let first) = blocks[1].kind,
              case .footnoteDefinition(2, "a", _) = blocks[2].kind else {
            Issue.record("unexpected footnotes: \(blocks.dropFirst().map(\.kind))")
            return
        }
        #expect(first.first?.kind == .paragraph([.text("Beta.")]))
    }

    @Test func unreferencedFootnoteIsDropped() {
        let blocks = MarkdownParser.parse("Text.\n\n[^x]: never used").blocks
        #expect(blocks.count == 1)
    }
}
