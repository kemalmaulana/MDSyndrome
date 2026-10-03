import Testing
@testable import MarkdownCore

@Suite struct MathExtractorTests {
    private func inlines(_ md: String, singleDollar: Bool = true) -> [Inline] {
        var options = MarkdownOptions()
        options.singleDollarMath = singleDollar
        guard case .paragraph(let content)? = MarkdownParser.parse(md, options: options).blocks.first?.kind else { return [] }
        return content
    }

    @Test func inlineMathIsProtectedFromEmphasis() {
        #expect(inlines("Area $a*b*c$ here") == [.text("Area "), .math(latex: "a*b*c", display: false), .text(" here")])
    }

    @Test func currencyIsNotMath() {
        #expect(inlines("costs $5 and $10 total") == [.text("costs $5 and $10 total")])
    }

    @Test func escapedDollarStaysLiteral() {
        #expect(inlines("\\$x$") == [.text("$x$")])
    }

    @Test func singleDollarCanBeDisabled() {
        #expect(inlines("$x$ and $$y$$", singleDollar: false) == [.text("$x$ and "), .math(latex: "y", display: true)])
    }

    @Test func mathInsideCodeSpanStaysCode() {
        #expect(inlines("`$x$` and $y$") == [.code("$x$"), .text(" and "), .math(latex: "y", display: false)])
    }

    @Test func mathInsideFencedCodeStaysCode() {
        let blocks = MarkdownParser.parse("```\n$x$\n```").blocks
        #expect(blocks.map(\.kind) == [.codeBlock(language: nil, code: "$x$")])
    }

    @Test func mathInsideIndentedCodeIsRestored() {
        let blocks = MarkdownParser.parse("    $x$").blocks
        #expect(blocks.map(\.kind) == [.codeBlock(language: nil, code: "$x$")])
    }

    @Test func displayBlockBetweenDollarLines() {
        let md = "before\n\n$$\nx^2 + y_1\n$$\n\nafter"
        let blocks = MarkdownParser.parse(md).blocks
        #expect(blocks.map(\.kind) == [
            .paragraph([.text("before")]),
            .mathBlock(latex: "x^2 + y_1"),
            .paragraph([.text("after")]),
        ])
        #expect(blocks[1].lines == SourceLines(start: 3, end: 5), "line numbers still match the user's text")
    }

    @Test func oneLineDisplayMathParagraphBecomesMathBlock() {
        #expect(MarkdownParser.parse("$$E=mc^2$$").blocks.map(\.kind) == [.mathBlock(latex: "E=mc^2")])
    }

    @Test func mathFenceBecomesMathBlock() {
        #expect(MarkdownParser.parse("```math\n\\frac{a}{b}\n```").blocks.map(\.kind) == [.mathBlock(latex: "\\frac{a}{b}")])
    }

    @Test func unclosedDisplayDelimiterIsLeftAlone() {
        #expect(MarkdownParser.parse("$$\nno close").blocks.map(\.kind) == [.paragraph([.text("$$"), .softBreak, .text("no close")])])
    }

    @Test func pipeInsideMathDoesNotSplitTableCell() throws {
        let block = try #require(MarkdownParser.parse("| m |\n|---|\n| $|x|$ |").blocks.first)
        guard case .table(let table) = block.kind else { Issue.record("not a table"); return }
        #expect(table.rows == [[[.math(latex: "|x|", display: false)]]])
    }

    @Test func mathDisabledLeavesDollarsAsText() {
        var options = MarkdownOptions()
        options.math = false
        guard case .paragraph(let c)? = MarkdownParser.parse("$x$", options: options).blocks.first?.kind else { Issue.record("no paragraph"); return }
        #expect(c == [.text("$x$")])
    }

    @Test func protectPreservesLineCount() {
        let source = "a $x$\n$$\ny\n$$\n```\n$z$\n```\n"
        let protected = MathExtractor.protect(source, singleDollar: true)
        #expect(protected.text.filter { $0 == "\n" }.count == source.filter { $0 == "\n" }.count)
    }
}
