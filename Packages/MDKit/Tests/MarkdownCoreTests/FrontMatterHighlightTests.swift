import Testing
@testable import MarkdownCore

@Suite struct FrontMatterTests {
    @Test func entriesAndLineNumbers() {
        let md = "---\ntitle: \"Hello\"\ntags:\n  - a\n  - b\n# comment\n---\n# Body"
        let blocks = MarkdownParser.parse(md).blocks
        #expect(blocks.first?.kind == .frontMatter([FrontMatterEntry(key: "title", value: "Hello"), FrontMatterEntry(key: "tags", value: "- a\n- b")]))
        #expect(blocks.first?.lines == SourceLines(start: 1, end: 7))
        #expect(blocks[1].kind == .heading(level: 1, content: [.text("Body")]))
        #expect(blocks[1].lines == SourceLines(start: 8, end: 8), "body line numbers are unchanged")
    }

    @Test func dotsCloseFrontMatterToo() {
        #expect(MarkdownParser.parse("---\na: 1\n...\ntext").blocks.first?.kind == .frontMatter([FrontMatterEntry(key: "a", value: "1")]))
    }

    @Test func thematicBreakWithoutClosingIsNotFrontMatter() {
        #expect(MarkdownParser.parse("---\n\nJust text").blocks.map(\.kind) == [.thematicBreak, .paragraph([.text("Just text")])])
    }

    @Test func mustStartOnLineOne() {
        let blocks = MarkdownParser.parse("intro\n\n---\na: 1\n---").blocks
        #expect(!blocks.contains { if case .frontMatter = $0.kind { true } else { false } })
    }

    @Test func canBeDisabled() {
        var options = MarkdownOptions()
        options.frontMatter = false
        #expect(!MarkdownParser.parse("---\na: 1\n---\nx", options: options).blocks.contains { if case .frontMatter = $0.kind { true } else { false } })
    }
}

@Suite struct HighlightMarkTests {
    private func inlines(_ md: String, highlight: Bool = true) -> [Inline] {
        var options = MarkdownOptions()
        options.highlight = highlight
        guard case .paragraph(let content)? = MarkdownParser.parse(md, options: options).blocks.first?.kind else { return [] }
        return content
    }

    @Test func markedText() {
        #expect(inlines("a ==b c== d ==e==") == [.text("a "), .highlight([.text("b c")]), .text(" d "), .highlight([.text("e")])])
    }

    @Test func notMarks() {
        #expect(inlines("x == y and a ==b") == [.text("x == y and a ==b")])
        #expect(inlines("== spaced ==") == [.text("== spaced ==")])
        #expect(inlines("`==code==`") == [.code("==code==")])
    }

    @Test func canBeDisabled() {
        #expect(inlines("==b==", highlight: false) == [.text("==b==")])
    }
}

@Suite struct MathFollowUpTests {
    @Test func displayDelimiterNeverPairsWithOneInsideCode() {
        let md = "$$\n\n```\n$$\n```"
        let kinds = MarkdownParser.parse(md).blocks.map(\.kind)
        #expect(kinds == [.paragraph([.text("$$")]), .codeBlock(language: nil, code: "$$")])
    }

    @Test func privateUseCharactersAreNotMistakenForMath() {
        let nerdFont = "\u{E000}0\u{E001} icon $x$"
        guard case .paragraph(let content)? = MarkdownParser.parse(nerdFont).blocks.first?.kind else { Issue.record("no paragraph"); return }
        #expect(content == [.text("\u{E000}0\u{E001} icon "), .math(latex: "x", display: false)])
    }

    @Test func emptyQuoteLeftByAFootnoteDisappears() {
        let blocks = MarkdownParser.parse("Text[^1].\n\n> [^1]: note").blocks
        #expect(!blocks.contains { if case .blockQuote = $0.kind { true } else { false } })
    }
}
