import Foundation
import Testing
@testable import MarkdownCore

/// Regressions found in the Plan 2 final review.
@Suite struct HostileNestingPlan2Tests {
    @Test func deeplyNestedInlineHTMLDoesNotOverflowTheStack() async {
        let md = String(repeating: "<b>", count: 2000) + "x" + String(repeating: "</b>", count: 2000)
        let blocks = await Task.detached { MarkdownParser.parse(md).blocks }.value
        #expect(blocks.count == 1)
        guard case .paragraph(let content)? = blocks.first?.kind else { Issue.record("no paragraph"); return }
        #expect(Self.strongDepth(content) <= NodeConverter.maxDepth, "nesting past the limit stays raw HTML")
    }

    @Test func deeplyNestedDetailsDoesNotOverflowTheStack() async {
        let md = String(repeating: "<details>\n\n", count: 2000) + "x\n\n" + String(repeating: "</details>\n\n", count: 2000)
        let blocks = await Task.detached { MarkdownParser.parse(md).blocks }.value
        #expect(!blocks.isEmpty)
    }

    static func strongDepth(_ inlines: [Inline]) -> Int {
        inlines.map { if case .strong(let c) = $0 { 1 + strongDepth(c) } else { 0 } }.max() ?? 0
    }
}

@Suite struct DetailsContentTests {
    private func kinds(_ md: String) -> [Block.Kind] { MarkdownParser.parse(md).blocks.map(\.kind) }

    @Test func contentSharingTheClosingBlockIsKept() {
        let md = "<details>\n<summary>S</summary>\n\nBody\n\n<p>More</p>\n</details>\n<p align=\"center\">Footer</p>"
        let blocks = kinds(md)
        #expect(blocks.count == 2)
        guard case .details(_, _, let inner) = blocks[0] else { Issue.record("not details: \(blocks)"); return }
        #expect(inner.map(\.kind) == [.paragraph([.text("Body")]), .htmlParagraph(level: 0, alignment: .leading, content: [.text("More")])])
        #expect(blocks[1] == .htmlParagraph(level: 0, alignment: .center, content: [.text("Footer")]))
    }

    @Test func backToBackDetailsWithoutBlankLines() {
        let md = """
        <details>
        <summary>Q1</summary>

        A1

        </details>
        <details>
        <summary>Q2</summary>

        A2

        </details>
        """
        let blocks = kinds(md)
        #expect(blocks.count == 2)
        guard case .details(let s1, _, let b1) = blocks[0], case .details(let s2, _, let b2) = blocks[1] else {
            Issue.record("expected two details: \(blocks)")
            return
        }
        #expect(s1 == [.text("Q1")] && s2 == [.text("Q2")])
        #expect(b1.map(\.kind) == [.paragraph([.text("A1")])])
        #expect(b2.map(\.kind) == [.paragraph([.text("A2")])])
    }

    @Test func htmlAfterTheSummaryBecomesTheFirstInnerBlock() {
        let md = "<details>\n<summary>S</summary>\n<p>Lead</p>\n\nMarkdown body\n\n</details>"
        guard case .details(_, _, let inner)? = kinds(md).first else { Issue.record("not details"); return }
        #expect(inner.map(\.kind) == [.htmlParagraph(level: 0, alignment: .leading, content: [.text("Lead")]), .paragraph([.text("Markdown body")])])
    }

    @Test func unsupportedBodyStaysRawInsteadOfVanishing() {
        guard case .details(_, _, let inner)? = kinds("<details><summary>S</summary><pre>code</pre></details>").first else {
            Issue.record("not details")
            return
        }
        #expect(inner.map(\.kind) == [.htmlBlock("<pre>code</pre>")])
    }

    @Test func strayClosingTagStaysRaw() {
        #expect(kinds("text\n\n</details>") == [.paragraph([.text("text")]), .htmlBlock("</details>")])
    }
}

@Suite struct FrontMatterGuardTests {
    @Test func markdownBetweenRulesIsNotSwallowed() {
        let kinds = MarkdownParser.parse("---\n# Title\nIntro paragraph.\n---\nMore text").blocks.map(\.kind)
        #expect(kinds.contains(.paragraph([.text("More text")])))
        #expect(kinds.contains { if case .heading = $0 { true } else { false } }, "the heading survives")
        #expect(!kinds.contains { if case .frontMatter = $0 { true } else { false } })
    }

    @Test func setextHeadingBetweenRulesSurvives() {
        let kinds = MarkdownParser.parse("---\nSome text\nHeading\n---").blocks.map(\.kind)
        #expect(!kinds.isEmpty)
        #expect(!kinds.contains { if case .frontMatter = $0 { true } else { false } })
    }

    @Test func realFrontMatterStillWorks() {
        #expect(MarkdownParser.parse("---\n# a comment\ntitle: T\n---\nx").blocks.first?.kind == .frontMatter([FrontMatterEntry(key: "title", value: "T")]))
    }
}

@Suite struct LinearHTMLParsingTests {
    private func parseTime(_ md: String) async -> Duration {
        await ContinuousClock().measure { _ = await Task.detached { MarkdownParser.parse(md) }.value }
    }

    /// Was quadratic: 100 KB of unmatched `<b>` took 31.7 s (release).
    @Test func manyUnmatchedInlineTags() async {
        let elapsed = await parseTime(String(repeating: "<b>x ", count: 20_000))
        #expect(elapsed < .budget(3), "measured \(elapsed)")
    }

    /// Was quadratic: 136 KB of unclosed `<details>` took 20.9 s (release).
    @Test func manyUnclosedDetails() async {
        let elapsed = await parseTime(String(repeating: "<details>\n\n", count: 12_000))
        #expect(elapsed < .budget(3), "measured \(elapsed)")
    }

    /// Was quadratic: an HTML block of 20k unclosed attribute quotes took 126 s (debug).
    @Test func manyUnclosedAttributeQuotes() async {
        let elapsed = await parseTime("<div>" + String(repeating: "<a title='x>", count: 20_000) + "</div>")
        #expect(elapsed < .budget(3), "measured \(elapsed)")
    }
}
