import Testing
@testable import MarkdownCore

@Suite struct ParserBlockTests {
    private func kinds(_ md: String) -> [Block.Kind] {
        MarkdownParser.parse(md).blocks.map(\.kind)
    }

    @Test func headingAndParagraph() {
        #expect(kinds("## Hello\n\nWorld") == [
            .heading(level: 2, content: [.text("Hello")]),
            .paragraph([.text("World")]),
        ])
    }

    @Test func blockQuoteContainsBlocks() throws {
        let block = try #require(MarkdownParser.parse("> quoted\n> more").blocks.first)
        guard case .blockQuote(let children) = block.kind else { Issue.record("not a quote"); return }
        #expect(children.map(\.kind) == [.paragraph([.text("quoted"), .softBreak, .text("more")])])
        #expect(children[0].lines == SourceLines(start: 1, end: 2))
    }

    @Test func orderedListKeepsStartAndTightness() throws {
        let block = try #require(MarkdownParser.parse("3. three\n4. four").blocks.first)
        guard case .list(let list) = block.kind else { Issue.record("not a list"); return }
        #expect(list.ordered)
        #expect(list.start == 3)
        #expect(list.tight)
        #expect(list.items.count == 2)
        #expect(list.items[0].task == nil)
    }

    @Test func looseBulletListStartsAtOne() throws {
        let block = try #require(MarkdownParser.parse("- a\n\n- b").blocks.first)
        guard case .list(let list) = block.kind else { Issue.record("not a list"); return }
        #expect(!list.ordered)
        #expect(list.start == 1)
        #expect(!list.tight)
    }

    @Test func fencedCodeUsesFirstInfoWordAndDropsTrailingNewline() {
        #expect(kinds("```swift title=x\nlet a = 1\n```") == [.codeBlock(language: "swift", code: "let a = 1")])
    }

    @Test func indentedCodeHasNoLanguage() {
        #expect(kinds("    indented") == [.codeBlock(language: nil, code: "indented")])
    }

    @Test func htmlBlockAndThematicBreak() {
        #expect(kinds("<div>x</div>\n\n---") == [.htmlBlock("<div>x</div>"), .thematicBreak])
    }

    @Test func sourceLinesAreOneBasedAndInclusive() {
        let blocks = MarkdownParser.parse("# T\n\n- a\n- b\n\ntext").blocks
        #expect(blocks.map(\.lines) == [
            SourceLines(start: 1, end: 1),
            SourceLines(start: 3, end: 4),
            SourceLines(start: 6, end: 6),
        ])
    }

    @Test func emptyDocumentHasNoBlocks() {
        #expect(MarkdownParser.parse("").blocks.isEmpty)
        #expect(MarkdownParser.parse("\n\n   \n").blocks.isEmpty)
    }
}

@Suite struct NestingLimitTests {
    @Test func hostileQuoteNestingIsFlattenedNotCrashing() async {
        let md = String(repeating: ">", count: 5000) + " deep"
        let blocks = await Task.detached { MarkdownParser.parse(md).blocks }.value
        #expect(blocks.count == 1)
        #expect(Self.depth(of: blocks[0]) == NodeConverter.maxDepth + 1)
    }

    @Test func hostileListNestingIsFlattenedNotCrashing() async {
        let md = (0..<1000).map { String(repeating: "  ", count: $0) + "- item" }.joined(separator: "\n")
        let blocks = await Task.detached { MarkdownParser.parse(md).blocks }.value
        #expect(blocks.count == 1)
    }

    @Test func flattenedTextKeepsTheWords() {
        let md = String(repeating: ">", count: 100) + " deep *words*"
        var block = MarkdownParser.parse(md).blocks[0]
        while case .blockQuote(let children) = block.kind { block = children[0] }
        #expect(block.kind == .paragraph([.text("deep words")]))
    }

    @Test func normalNestingIsUntouched() {
        let block = MarkdownParser.parse("> > > three").blocks[0]
        #expect(Self.depth(of: block) == 4)
    }

    /// Number of nested blockQuote levels plus the innermost leaf block.
    static func depth(of block: Block) -> Int {
        if case .blockQuote(let children) = block.kind, let first = children.first { return 1 + depth(of: first) }
        return 1
    }
}
