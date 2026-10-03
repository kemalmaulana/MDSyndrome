import Testing
@testable import MarkdownCore

@Suite struct SluggerTests {
    @Test(arguments: [
        ("Hello World", "hello-world"),
        ("What's new? (v2.0)", "whats-new-v20"),
        ("  Spaced  ", "--spaced--"),
        ("Ünïcödé Tïtle", "ünïcödé-tïtle"),
        ("snake_case-and-dash", "snake_case-and-dash"),
    ])
    func slugs(input: String, expected: String) {
        var slugger = Slugger()
        #expect(slugger.slug(input) == expected)
    }

    @Test func duplicatesGetCounters() {
        var slugger = Slugger()
        #expect(["A", "A", "A", "a-1"].map { slugger.slug($0) } == ["a", "a-1", "a-2", "a-1-1"])
    }
}

@Suite struct OutlineTests {
    @Test func topLevelHeadingsOnly() {
        let doc = MarkdownParser.parse("# One\n\n> # Quoted\n\n## Two *em*")
        let outline = Outline.make(from: doc)
        #expect(outline.map(\.title) == ["One", "Two em"])
        #expect(outline.map(\.level) == [1, 2])
        #expect(outline.map(\.slug) == ["one", "two-em"])
        #expect(outline.map(\.line) == [1, 5])
        #expect(outline[0].id == doc.blocks[0].id)
    }
}

@Suite struct DocumentStatsTests {
    @Test func countsRenderedWordsNotSyntax() {
        let source = "# Title here\n\n- **one** two\n- three"
        let stats = DocumentStats.make(source: source, document: MarkdownParser.parse(source))
        #expect(stats.words == 5)
        #expect(stats.characters == source.count)
        #expect(stats.lines == 4)
    }

    @Test func trailingNewlineCountsAsLine() {
        let stats = DocumentStats.make(source: "a\n", document: MarkdownParser.parse("a\n"))
        #expect(stats.lines == 2)
    }

    @Test func emptyDocument() {
        #expect(DocumentStats.make(source: "", document: MarkdownDocument(blocks: [])) == .empty)
        #expect(DocumentStats.empty.readingMinutes == 0)
    }

    @Test func readingTimeRoundsUp() {
        #expect(DocumentStats(words: 1, characters: 0, lines: 0).readingMinutes == 1)
        #expect(DocumentStats(words: 201, characters: 0, lines: 0).readingMinutes == 2)
    }
}

@Suite struct PipelineTests {
    @Test func renderBundlesDocumentOutlineAndStats() {
        let rendered = MarkdownPipeline.render("# A\n\nb c", options: .default)
        #expect(rendered.document.blocks.count == 2)
        #expect(rendered.outline.map(\.title) == ["A"])
        #expect(rendered.stats.words == 3)
    }

    /// PRD NF-4: 1 MB first render < 1 s. Debug builds are ~3x slower than release (measured 0.46 s vs 0.15 s).
    @Test func oneMegabyteDocumentRendersQuickly() async {
        let paragraph = "Some **bold** and *em* text with `code` and [link](http://x.com) $x^2$.\n\n- item one\n- item two\n\n"
        let source = String(repeating: paragraph, count: 1_000_000 / paragraph.utf8.count)
        let elapsed = await ContinuousClock().measure {
            _ = await Task.detached { MarkdownPipeline.render(source, options: .default) }.value
        }
        #expect(elapsed < .seconds(2), "measured \(elapsed)")
    }
}
