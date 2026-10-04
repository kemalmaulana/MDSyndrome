import Foundation
import Testing
@testable import MarkdownCore

/// Regressions found in the Plan 1 final review.
@Suite struct WindowsLineEndingTests {
    @Test func crlfDocumentParsesLikeLF() {
        let lf = "Costs $5 per item.\n\nAnother para with total$ here."
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(MarkdownParser.parse(crlf) == MarkdownParser.parse(lf))
        #expect(MarkdownParser.parse(crlf).blocks.count == 2)
    }

    @Test func crlfDisplayMathKeepsLineNumbers() {
        let blocks = MarkdownParser.parse("before\r\n\r\n$$\r\nx\r\n$$\r\n\r\nafter").blocks
        #expect(blocks.map(\.kind) == [.paragraph([.text("before")]), .mathBlock(latex: "x"), .paragraph([.text("after")])])
        #expect(blocks.map(\.lines) == [SourceLines(start: 1, end: 1), SourceLines(start: 3, end: 5), SourceLines(start: 7, end: 7)])
    }

    @Test func crlfBlockIdsMatchLFAndStayDistinct() {
        let lf = MarkdownParser.parse("one\n\ntwo\n\nthree").blocks
        let crlf = MarkdownParser.parse("one\r\n\r\ntwo\r\n\r\nthree").blocks
        #expect(crlf.map(\.id) == lf.map(\.id))
        #expect(Set(crlf.map(\.id)).count == 3)
    }

    @Test func classicMacLineEndingsToo() {
        #expect(MarkdownParser.parse("one\r\rtwo").blocks.count == 2)
    }

    @Test func statsCountWindowsAndClassicLines() {
        for source in ["a\r\nb\r\nc", "a\rb\rc", "a\nb\r\nc"] {
            #expect(DocumentStats.make(source: source, document: MarkdownParser.parse(source)).lines == 3, "\(source.debugDescription)")
        }
    }
}

@Suite struct DollarInURLTests {
    private func firstInlines(_ md: String) -> [Inline] {
        guard case .paragraph(let content)? = MarkdownParser.parse(md).blocks.first?.kind else { return [] }
        return content
    }

    @Test func linkDestinationKeepsDollarParameters() {
        let url = "https://graph.microsoft.com/v1.0/users?$filter=a&$top=10"
        #expect(firstInlines("[q](\(url))") == [.link(destination: url, title: nil, content: [.text("q")])])
    }

    @Test func autolinkTextAndDestinationKeepDollars() {
        let url = "https://example.com/users?$filter=a&$top=10"
        #expect(firstInlines(url) == [.link(destination: url, title: nil, content: [.text(url)])])
    }

    @Test func imageSourceAndTitleKeepDollars() {
        #expect(firstInlines("![x](img/$a$.png \"cost $a$\")") == [.image(source: "img/$a$.png", title: "cost $a$", alt: "x")])
    }

    @Test func mathInOrdinaryLinkTextStillRendersAsMath() {
        #expect(firstInlines("[see $x$](https://example.com)") == [
            .link(destination: "https://example.com", title: nil, content: [.text("see "), .math(latex: "x", display: false)]),
        ])
    }
}

@Suite struct HostileMathInputTests {
    private func renderTime(_ source: String) async -> Duration {
        await ContinuousClock().measure {
            _ = await Task.detached { MarkdownPipeline.render(source, options: .default) }.value
        }
    }

    /// Was quadratic: 99 KB of "$a " took 11 s per render in a release build.
    @Test func longLineOfUnclosedDollarsIsLinear() async {
        let elapsed = await renderTime(String(repeating: "$a ", count: 33_000))
        #expect(elapsed < .seconds(2), "measured \(elapsed)")
    }

    /// Was quadratic: 40,000 U+E000 characters plus one math span took 23.6 s.
    @Test func privateUseCharactersDoNotSlowPlaceholderRestore() async {
        let elapsed = await renderTime(String(repeating: "\u{E000}", count: 40_000) + " $x$")
        #expect(elapsed < .seconds(2), "measured \(elapsed)")
    }

    @Test func manyUnmatchedBacktickRunsAreFine() async {
        let line = (1...300).map { String(repeating: "`", count: $0) }.joined(separator: " x ") + " $y$"
        let elapsed = await renderTime(line)
        #expect(elapsed < .seconds(2), "measured \(elapsed)")
    }
}
