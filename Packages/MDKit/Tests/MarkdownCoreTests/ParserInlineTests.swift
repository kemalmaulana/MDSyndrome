import Testing
@testable import MarkdownCore

@Suite struct ParserInlineTests {
    private func inlines(_ md: String, options: MarkdownOptions = .default) -> [Inline] {
        guard case .paragraph(let content)? = MarkdownParser.parse(md, options: options).blocks.first?.kind else { return [] }
        return content
    }

    @Test func emphasisStrongAndCode() {
        #expect(inlines("*a* **b** `c`") == [
            .emphasis([.text("a")]), .text(" "), .strong([.text("b")]), .text(" "), .code("c"),
        ])
    }

    @Test func linkWithTitleAndImageAlt() {
        #expect(inlines("[go](http://a.com \"T\") ![the *alt*](p.png)") == [
            .link(destination: "http://a.com", title: "T", content: [.text("go")]),
            .text(" "),
            .image(source: "p.png", title: nil, alt: "the alt"),
        ])
    }

    @Test func softAndHardBreaks() {
        #expect(inlines("a\nb\\\nc") == [.text("a"), .softBreak, .text("b"), .lineBreak, .text("c")])
    }

    @Test func hardBreaksOptionTurnsNewlinesIntoBreaks() {
        var options = MarkdownOptions()
        options.hardBreaks = true
        #expect(inlines("a\nb", options: options) == [.text("a"), .lineBreak, .text("b")])
    }

    @Test func strikethroughAndAutolink() {
        #expect(inlines("~~x~~ www.example.com") == [
            .strikethrough([.text("x")]),
            .text(" "),
            .link(destination: "http://www.example.com", title: nil, content: [.text("www.example.com")]),
        ])
    }

    @Test func strikethroughCanBeDisabled() {
        var options = MarkdownOptions()
        options.strikethrough = false
        #expect(inlines("~~x~~", options: options) == [.text("~~x~~")])
    }

    @Test func inlineHTMLIsKeptAsHTML() {
        #expect(inlines("<kbd>K</kbd>") == [.html("<kbd>"), .text("K"), .html("</kbd>")])
    }

    @Test func smartPunctuationIsOptIn() {
        #expect(inlines("\"q\"") == [.text("\"q\"")])
        var options = MarkdownOptions()
        options.smartPunctuation = true
        #expect(inlines("\"q\"", options: options) == [.text("\u{201C}q\u{201D}")])
    }
}
