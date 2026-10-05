import Testing
@testable import MarkdownCore

/// A document with a duplicate heading, a heading in a quote, one written as HTML, two footnotes (which cmark moves
/// to the end of the block list although they sit in the middle of the text) and a last heading.
private let sample = """
# Title

Intro with a note[^1] and another[^2].

## Section

text

> ## Quoted section

<h2 align="center">Html heading</h2>

## Section

- item
  - [ ] nested task

[^1]: First note.
[^2]: Second note.

## Last
"""

private func blockIndex(_ id: BlockID?, in document: MarkdownDocument) -> Int? {
    document.blocks.firstIndex { $0.id == id }
}

@Suite struct SourceMapTests {
    private let document = MarkdownParser.parse(sample)
    private var map: SourceMap { SourceMap(blocks: document.blocks) }

    @Test func everyLineBelongsToTheBlockThatStartedLastOnOrBeforeIt() {
        // Lines: 1 Title · 3 intro · 5 Section · 7 text · 9 quote · 11 html heading · 13 Section · 15-16 list ·
        // 18, 19 footnotes · 21 Last. Blank lines go to the block above.
        let expected: [(line: Int, text: String)] = [
            (1, "Title"), (2, "Title"), (3, "Intro"), (4, "Intro"), (5, "Section"), (6, "Section"), (7, "text"), (8, "text"),
            (9, "quote"), (10, "quote"), (11, "Html heading"), (13, "Section"), (15, "list"), (16, "list"), (17, "list"),
            (18, "footnote 1"), (19, "footnote 2"), (20, "footnote 2"), (21, "Last"), (500, "Last"),
        ]
        for (line, text) in expected {
            let index = blockIndex(map.blockID(atLine: line), in: document)
            let block = index.map { document.blocks[$0] }
            let description: String
            switch block?.kind {
            case .heading(_, let content)?, .htmlParagraph(_, _, let content)?: description = Inline.plainText(content)
            case .paragraph(let content)?: description = Inline.plainText(content).hasPrefix("Intro") ? "Intro" : Inline.plainText(content)
            case .blockQuote?: description = "quote"
            case .list?: description = "list"
            case .footnoteDefinition(let index, _, _)?: description = "footnote \(index)"
            default: description = "?"
            }
            #expect(description == text, "line \(line)")
        }
    }

    @Test func nothingBeforeTheFirstBlock() {
        let document = MarkdownParser.parse("\n\nFirst paragraph")
        let map = SourceMap(blocks: document.blocks)
        #expect(map.blockID(atLine: 1) == nil)
        #expect(map.blockID(atLine: 2) == nil)
        #expect(map.blockID(atLine: 3) == document.blocks[0].id)
        #expect(map.blockID(atLine: 0) == nil)
        #expect(map.blockID(atLine: -5) == nil)
    }

    @Test func footnoteDefinitionsAreFoundByTheirSourceLinesNotTheirPlaceInTheList() {
        let blocks = document.blocks
        let footnoteIndexes = blocks.indices.filter { if case .footnoteDefinition = blocks[$0].kind { true } else { false } }
        #expect(footnoteIndexes == [blocks.count - 2, blocks.count - 1], "cmark moves them to the end of the list")
        let first = blocks[footnoteIndexes[0]]
        #expect(first.lines.start < blocks[blocks.count - 3].lines.start, "but they keep the lines they were written on")
        #expect(map.blockID(atLine: first.lines.start) == first.id)
    }

    @Test func startLineOfEveryBlockIsItsFirstLine() {
        for block in document.blocks {
            #expect(map.startLine(of: block.id) == block.lines.start)
        }
        #expect(map.startLine(of: BlockID(12345)) == nil)
    }

    @Test func aLineAlwaysFindsABlockWhoseStartIsAtOrBeforeIt() {
        let lineCount = sample.split(separator: "\n", omittingEmptySubsequences: false).count
        for line in 1...lineCount {
            let id = map.blockID(atLine: line)
            let start = id.flatMap { map.startLine(of: $0) }
            #expect(start != nil && start! <= line, "line \(line)")
        }
    }

    @Test func blocksThatShareTheirFirstLineGiveTheFirst() {
        // One HTML block can become several blocks; they all start on the same line.
        let source = "<p align=\"center\">a</p>\n<details>\n<summary>S</summary>\n\nbody\n\n</details>\n"
        let document = MarkdownParser.parse(source)
        let map = SourceMap(blocks: document.blocks)
        let sharing = document.blocks.filter { $0.lines.start == document.blocks[0].lines.start }
        #expect(sharing.count >= 2, "the fixture should produce blocks that share a line")
        #expect(map.blockID(atLine: document.blocks[0].lines.start) == sharing[0].id)
    }

    @Test func anEmptyDocumentHasNoBlocks() {
        let map = SourceMap(blocks: [])
        #expect(map.isEmpty)
        #expect(map.blockID(atLine: 1) == nil)
        #expect(SourceMap.empty == map)
    }

    @Test func aMegabyteMapBuildsQuickly() {
        let paragraph = "Some **bold** text with `code`.\n\n- item one\n- item two\n\n## Heading\n\n"
        let source = String(repeating: paragraph, count: 1_000_000 / paragraph.utf8.count)
        let document = MarkdownParser.parse(source)
        let elapsed = ContinuousClock().measure {
            let map = SourceMap(blocks: document.blocks)
            for line in stride(from: 1, to: 40_000, by: 7) { _ = map.blockID(atLine: line) }
        }
        #expect(elapsed < .budget(0.5), "\(document.blocks.count) blocks took \(elapsed)")
    }
}

@Suite struct DocumentAnchorsTests {
    private let document = MarkdownParser.parse(sample)
    private var anchors: DocumentAnchors { DocumentAnchors(blocks: document.blocks) }

    private func index(of fragment: String) -> Int? {
        blockIndex(anchors.target(for: fragment), in: document)
    }

    @Test func headingsAreFoundBySlugAndDuplicatesAreNumberedAcrossTheDocument() {
        #expect(index(of: "title") == 0)
        #expect(index(of: "section") == 2)
        #expect(index(of: "section-1") == 6)
        #expect(index(of: "last") == 8)
    }

    @Test func aHeadingInsideAQuoteIsFoundAndPointsAtTheQuote() {
        let index = index(of: "quoted-section")
        #expect(index == 4)
        if let index, case .blockQuote = document.blocks[index].kind {} else { Issue.record("expected the block quote") }
    }

    @Test func aHeadingWrittenAsHTMLCounts() {
        let index = index(of: "html-heading")
        #expect(index == 5)
        if let index, case .htmlParagraph(2, _, _) = document.blocks[index].kind {} else { Issue.record("expected the <h2> block") }
    }

    @Test func theMatchIgnoresCaseAndAcceptsALeadingHash() {
        #expect(index(of: "SECTION") == 2)
        #expect(index(of: "#last") == 8)
        #expect(index(of: "Title") == 0)
    }

    @Test func percentEncodedAndNonASCIIFragmentsMatch() {
        let document = MarkdownParser.parse("# Café au lait\n\n## Ünïcödé Tïtle\n\n## 日本語 の 見出し")
        let anchors = DocumentAnchors(blocks: document.blocks)
        #expect(anchors.target(for: "caf%C3%A9-au-lait") == document.blocks[0].id)
        #expect(anchors.target(for: "café-au-lait") == document.blocks[0].id)
        #expect(anchors.target(for: "ünïcödé-tïtle") == document.blocks[1].id)
        #expect(anchors.target(for: "%C3%9Cn%C3%AFc%C3%B6d%C3%A9-t%C3%AFtle") == document.blocks[1].id)
        #expect(anchors.target(for: "日本語-の-見出し") == document.blocks[2].id)
    }

    @Test func unknownAndEmptyFragmentsMatchNothing() {
        #expect(anchors.target(for: "no-such-heading") == nil)
        #expect(anchors.target(for: "") == nil)
        #expect(anchors.target(for: "#") == nil)
        #expect(anchors.target(for: "%") == nil)
        #expect(anchors.target(for: "fn-9") == nil)
        #expect(anchors.target(for: "fnref-9") == nil)
    }

    @Test func footnotesLinkBothWays() {
        let definition = index(of: "fn-1")
        #expect(definition.map { document.blocks[$0].kind } != nil)
        if let definition, case .footnoteDefinition(1, _, _) = document.blocks[definition].kind {} else { Issue.record("fn-1 should be footnote 1") }
        if let second = index(of: "fn-2"), case .footnoteDefinition(2, _, _) = document.blocks[second].kind {} else { Issue.record("fn-2 should be footnote 2") }
        #expect(index(of: "fnref-1") == 1, "the paragraph holding the first reference")
        #expect(index(of: "fnref-2") == 1)
    }

    @Test func aFootnoteReferenceInsideEmphasisAListAndATableIsFound() {
        let source = "text *with a note[^a]*\n\n- item[^b]\n\n| h |\n|---|\n| cell[^c] |\n\n[^a]: A.\n[^b]: B.\n[^c]: C.\n"
        let document = MarkdownParser.parse(source)
        let anchors = DocumentAnchors(blocks: document.blocks)
        #expect(blockIndex(anchors.target(for: "fnref-1"), in: document) == 0)
        #expect(blockIndex(anchors.target(for: "fnref-2"), in: document) == 1)
        #expect(blockIndex(anchors.target(for: "fnref-3"), in: document) == 2)
    }

    @Test func aDocumentWithoutHeadingsHasNoAnchors() {
        let document = MarkdownParser.parse("just text\n\nmore text")
        let anchors = DocumentAnchors(blocks: document.blocks)
        #expect(anchors.target(for: "just-text") == nil)
        #expect(DocumentAnchors.empty.target(for: "anything") == nil)
    }

    @Test func aMegabyteOfHeadingsBuildsQuickly() {
        let source = (0..<20_000).map { "## Heading \($0 % 50)\n\ntext\n" }.joined(separator: "\n")
        let document = MarkdownParser.parse(source)
        let elapsed = ContinuousClock().measure { _ = DocumentAnchors(blocks: document.blocks) }
        #expect(elapsed < .budget(1), "\(document.blocks.count) blocks took \(elapsed)")
    }
}

@Suite struct OutlineNavigationTests {
    @Test func everyOutlineItemsSlugResolvesToItsOwnBlock() {
        let document = MarkdownParser.parse(sample)
        let anchors = DocumentAnchors(blocks: document.blocks)
        let outline = Outline.make(from: document)
        #expect(outline.map(\.title) == ["Title", "Section", "Html heading", "Section", "Last"])
        for item in outline {
            #expect(anchors.target(for: item.slug) == item.id, "\(item.title)")
        }
    }

    @Test func slugsNumberDuplicatesAcrossNestedHeadingsToo() {
        let document = MarkdownParser.parse("# A\n\n> # A\n\n# A\n")
        let outline = Outline.make(from: document)
        #expect(outline.map(\.slug) == ["a", "a-2"], "the quoted heading took a-1, as on GitHub")
        let anchors = DocumentAnchors(blocks: document.blocks)
        #expect(blockIndex(anchors.target(for: "a-1"), in: document) == 1, "and points at the quote")
    }

    @Test func currentIsTheLastHeadingStartedOnOrBeforeTheLine() {
        let items = [1, 5, 9].map { OutlineItem(id: BlockID(UInt64($0)), level: 1, title: "h\($0)", slug: "h\($0)", line: $0) }
        #expect(Outline.current(in: items, atLine: 0) == nil)
        #expect(Outline.current(in: items, atLine: 1)?.title == "h1")
        #expect(Outline.current(in: items, atLine: 4)?.title == "h1")
        #expect(Outline.current(in: items, atLine: 5)?.title == "h5")
        #expect(Outline.current(in: items, atLine: 8)?.title == "h5")
        #expect(Outline.current(in: items, atLine: 9)?.title == "h9")
        #expect(Outline.current(in: items, atLine: 100_000)?.title == "h9")
        #expect(Outline.current(in: [], atLine: 3) == nil)
    }

    @Test func aDocumentWithoutHeadingsHasAnEmptyOutline() {
        for source in ["", "\n\n\n", "---\ntitle: x\n---\n", "text only"] {
            let document = MarkdownParser.parse(source)
            #expect(Outline.make(from: document).isEmpty, "\(source.debugDescription)")
        }
    }

    @Test func theRenderedDocumentCarriesTheMapAndTheAnchors() {
        let rendered = MarkdownPipeline.render(sample, options: .default)
        #expect(rendered.sourceMap == SourceMap(blocks: rendered.document.blocks))
        #expect(rendered.anchors == DocumentAnchors(blocks: rendered.document.blocks))
        #expect(RenderedDocument.empty.sourceMap.isEmpty)
    }
}
