import CoreGraphics
import Foundation
import MarkdownCore
import Testing
@testable import PreviewKit

@MainActor
private func html(_ markdown: String) -> String {
    HTMLExporter.fragment(MarkdownParser.parse(markdown))
}

@MainActor
@Suite struct HTMLExporterTests {
    @Test func blocksBecomeTheirTags() {
        let out = html("# Title\n\nSome *em*, **strong**, ~~gone~~, `code` and [a link](https://example.com \"T\").\n\n> quote\n\n---")
        #expect(out.contains("<h1 id=\"title\">Title</h1>"))
        #expect(out.contains("<em>em</em>") && out.contains("<strong>strong</strong>") && out.contains("<del>gone</del>") && out.contains("<code>code</code>"))
        #expect(out.contains("<a href=\"https://example.com\" title=\"T\">a link</a>"))
        #expect(out.contains("<blockquote>") && out.contains("<hr>"))
    }

    @Test func headingIdsFollowGitHubSlugs() {
        let out = html("## Same\n\n## Same\n\n## Café au lait")
        #expect(out.contains("id=\"same\"") && out.contains("id=\"same-1\"") && out.contains("id=\"café-au-lait\""))
    }

    @Test func textIsEscaped() {
        let out = html("a < b & c > d \"quoted\"")
        #expect(out.contains("a &lt; b &amp; c &gt; d &quot;quoted&quot;"))
    }

    @Test func listsKeepOrderStartAndTasks() {
        let out = html("3. three\n4. four\n\n- [ ] todo\n- [x] done")
        #expect(out.contains("<ol start=\"3\">") && out.contains("<li>three</li>"))
        #expect(out.contains("<input type=\"checkbox\" disabled>") && out.contains("<input type=\"checkbox\" checked disabled>"))
    }

    @Test func tablesKeepAlignment() {
        let out = html("| a | b |\n|:-:|--:|\n| 1 | 2 |")
        #expect(out.contains("<th style=\"text-align:center\">a</th>") && out.contains("<td style=\"text-align:right\">2</td>"))
    }

    @Test func codeIsHighlightedWithSpans() {
        let out = html("```swift\nlet x = 1 // c\n```")
        #expect(out.contains("<code class=\"language-swift\">") && out.contains("class=\"tk-keyword\"") && out.contains("class=\"tk-comment\""))
        let plain = html("```\n<b>&</b>\n```")
        #expect(plain.contains("&lt;b&gt;&amp;&lt;/b&gt;") && !plain.contains("tk-"))
    }

    @Test func footnotesGoToTheEndWithBackLinks() {
        let out = html("Text[^1] more.\n\n[^1]: The note.")
        #expect(out.contains("<sup><a href=\"#fn-1\" id=\"fnref-1\">1</a></sup>"))
        #expect(out.contains("<li id=\"fn-1\">") && out.contains("href=\"#fnref-1\""))
        #expect(out.range(of: "fnref-1\">1")!.lowerBound < out.range(of: "<li id=\"fn-1\">")!.lowerBound)
    }

    @Test func mathBecomesAnImageWithItsSourceAsAlt() {
        let out = html("Inline $x^2$ and\n\n$$\\frac{a}{b}$$")
        #expect(out.contains("class=\"math\"") && out.contains("data:image/png;base64,") && out.contains("alt=\"x^2\""))
    }

    @Test func aStandalonePageHasLightAndDarkAndNoScript() {
        let page = HTMLExporter.standalone(MarkdownParser.parse("# Hi\n\n<script>alert(1)</script>\n\ntext"), theme: .github, title: "A <b> title")
        #expect(page.hasPrefix("<!doctype html>") && page.contains("prefers-color-scheme: dark"))
        #expect(page.contains("<title>A &lt;b&gt; title</title>"))
        #expect(!page.lowercased().contains("<script"))
        #expect(page.contains(PreviewTheme.github.link.light) && page.contains(PreviewTheme.github.link.dark))
    }

    @Test func aFragmentHasNoPageOrStyles() {
        let out = html("# T")
        #expect(!out.contains("<html") && !out.contains("<style"))
    }

    @Test func anEmptyDocumentExportsAnEmptyBody() {
        #expect(html("").isEmpty)
    }
}

@Suite struct HTMLSanitizerTests {
    @Test func scriptsAndFramesAreRemoved() {
        for hostile in ["<script>alert(1)</script>", "<SCRIPT src=x></SCRIPT>", "<iframe src=\"//evil\"></iframe>", "<object data=x></object>", "<embed src=x>", "<style>*{}</style>"] {
            let cleaned = HTMLSanitizer.clean("a\(hostile)b")
            #expect(cleaned == "ab", "\(hostile) → \(cleaned)")
        }
    }

    @Test func handlersAndScriptURLsAreRemoved() {
        #expect(!HTMLSanitizer.clean("<img src=x onerror=\"alert(1)\">").contains("onerror"))
        #expect(!HTMLSanitizer.clean("<a href='javascript:alert(1)'>x</a>").lowercased().contains("javascript"))
        #expect(!HTMLSanitizer.clean("<a HREF=\"JavaScript:alert(1)\">x</a>").lowercased().contains("javascript"))
        #expect(HTMLSanitizer.clean("<p onclick=a() class=b>x</p>") == "<p class=b>x</p>")
    }

    @Test func ordinaryHTMLSurvives() {
        let ok = "<p align=\"center\"><img src=\"a.png\" width=\"20\"> <kbd>⌘</kbd></p>"
        #expect(HTMLSanitizer.clean(ok) == ok)
    }

    @Test func linkAddressesThatRunCodeBecomeAHash() {
        #expect(HTMLSanitizer.safeURL("javascript:alert(1)") == "#")
        #expect(HTMLSanitizer.safeURL("  JavaScript:x") == "#")
        #expect(HTMLSanitizer.safeURL("data:text/html,hi") == "#")
        #expect(HTMLSanitizer.safeURL("https://example.com") == "https://example.com")
        #expect(HTMLSanitizer.safeURL("#anchor") == "#anchor" && HTMLSanitizer.safeURL("a/b.md") == "a/b.md")
    }
}

@MainActor
@Suite(.requiresWindowServer) struct PDFExporterTests {
    private let letter = CGSize(width: 612, height: 792)
    private let margins = NSEdgeInsets(top: 72, left: 72, bottom: 72, right: 72)

    private func pages(_ markdown: String) -> Int? {
        guard let data = PDFExporter.export(MarkdownParser.parse(markdown), theme: .github, baseURL: nil, paperSize: letter, margins: margins),
              let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider) else { return nil }
        return pdf.numberOfPages
    }

    @Test func aShortDocumentIsOnePage() {
        #expect(pages("# Title\n\nHello.") == 1)
    }

    @Test func anEmptyDocumentIsOneBlankPage() {
        #expect(pages("") == 1)
    }

    @Test func aLongDocumentSpansPages() {
        let text = (0..<200).map { "Paragraph \($0) with some words in it to fill a line or two of the page." }.joined(separator: "\n\n")
        #expect((pages(text) ?? 0) >= 3)
    }

    @Test func aBlockTallerThanAPageIsSliced() {
        let code = (0..<150).map { "line \($0)" }.joined(separator: "\n")
        #expect((pages("```\n\(code)\n```") ?? 0) >= 2)
    }

    @Test func aTinyPaperGivesNothingRatherThanCrashing() {
        let data = PDFExporter.export(MarkdownParser.parse("x"), theme: .github, baseURL: nil, paperSize: CGSize(width: 100, height: 100), margins: margins)
        #expect(data == nil)
    }
}
