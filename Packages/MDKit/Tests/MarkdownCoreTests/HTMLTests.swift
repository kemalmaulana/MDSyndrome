import Testing
@testable import MarkdownCore

@Suite struct HTMLTagTests {
    @Test func parsesNameAttributesAndKinds() throws {
        let tag = try #require(HTMLTag.parse(#"<a href="https://x.com/?a=1&amp;b=2" title='T' data-x=y>"#))
        #expect(tag.name == "a")
        #expect(!tag.isClosing && !tag.isSelfClosing)
        #expect(tag.attributes == ["href": "https://x.com/?a=1&b=2", "title": "T", "data-x": "y"])
        #expect(HTMLTag.parse("</B>") == HTMLTag(name: "b", isClosing: true, isSelfClosing: false, attributes: [:]))
        #expect(HTMLTag.parse("<br>")?.isSelfClosing == true)
        #expect(HTMLTag.parse("<details open>")?.attributes["open"] == "")
    }

    @Test(arguments: ["<!-- c -->", "<!DOCTYPE html>", "<>", "< a>", "plain", "<1abc>"])
    func rejectsNonTags(_ raw: String) {
        #expect(HTMLTag.parse(raw) == nil)
    }

    @Test func decodesEntities() {
        #expect(HTMLEntities.decode("&lt;b&gt; &amp; &copy; &#169; &#xA9; &unknown; &") == "<b> & © © © &unknown; &")
    }
}

@Suite struct InlineHTMLTests {
    private func inlines(_ md: String) -> [Inline] {
        guard case .paragraph(let content)? = MarkdownParser.parse(md).blocks.first?.kind else { return [] }
        return content
    }

    @Test func formattingTags() {
        #expect(inlines("H<sub>2</sub>O x<sup>2</sup> <u>u</u> <mark>m</mark> <b>b</b> <i>i</i> <s>s</s> <code>c</code>") == [
            .text("H"), .subscript([.text("2")]), .text("O x"), .superscript([.text("2")]), .text(" "), .underline([.text("u")]),
            .text(" "), .highlight([.text("m")]), .text(" "), .strong([.text("b")]), .text(" "), .emphasis([.text("i")]),
            .text(" "), .strikethrough([.text("s")]), .text(" "), .code("c"),
        ])
    }

    @Test func linksImagesAndBreaks() {
        #expect(inlines(#"<a href="https://x.com">go <b>now</b></a><br><img src="a.png" alt="A" width="40px">"#) == [
            .link(destination: "https://x.com", title: nil, content: [.text("go "), .strong([.text("now")])]),
            .lineBreak,
            .image(source: "a.png", title: nil, alt: "A", width: 40),
        ])
    }

    @Test func nestedSameTagsMatchCorrectly() {
        #expect(inlines("<b>a <b>b</b> c</b>") == [.strong([.text("a "), .strong([.text("b")]), .text(" c")])])
    }

    @Test func unmatchedTagsStayRaw() {
        #expect(inlines("<b>never closed") == [.html("<b>"), .text("never closed")])
        #expect(inlines("stray </i> close") == [.text("stray "), .html("</i>"), .text(" close")])
    }
}

@Suite struct HTMLBlockTests {
    private func kinds(_ md: String) -> [Block.Kind] { MarkdownParser.parse(md).blocks.map(\.kind) }

    @Test func centeredReadmeHeroBecomesNativeBlocks() {
        let md = """
        <p align="center">
          <img src="icon.png" width="148" alt="Icon">
        </p>

        <h1 align="center">MDSyndrome</h1>

        <p align="center">
          <b>A native editor.</b><br>
          Prescribed &amp; ready.
        </p>
        """
        #expect(kinds(md) == [
            .htmlParagraph(level: 0, alignment: .center, content: [.image(source: "icon.png", title: nil, alt: "Icon", width: 148)]),
            .htmlParagraph(level: 1, alignment: .center, content: [.text("MDSyndrome")]),
            .htmlParagraph(level: 0, alignment: .center, content: [.strong([.text("A native editor.")]), .lineBreak, .text("Prescribed & ready.")]),
        ])
    }

    @Test func badgeRowOfLinkedImages() {
        let md = #"<p align="center"><a href="https://ci"><img alt="CI" src="ci.svg"></a> <img alt="MIT" src="mit.svg"></p>"#
        #expect(kinds(md) == [.htmlParagraph(level: 0, alignment: .center, content: [
            .link(destination: "https://ci", title: nil, content: [.image(source: "ci.svg", title: nil, alt: "CI")]),
            .text(" "),
            .image(source: "mit.svg", title: nil, alt: "MIT"),
        ])])
    }

    @Test func pictureFallsBackToItsImage() {
        let image = Inline.image(source: "l.png", title: nil, alt: "Logo")
        // On one line it's inline HTML in a paragraph; on several lines cmark makes it an HTML block.
        #expect(kinds(#"<picture><source media="(prefers-color-scheme: dark)" srcset="d.png"><img src="l.png" alt="Logo"></picture>"#) == [.paragraph([image])])
        #expect(kinds("<picture>\n<source srcset=\"d.png\">\n<img src=\"l.png\" alt=\"Logo\">\n</picture>") == [.htmlParagraph(level: 0, alignment: .leading, content: [image])])
    }

    @Test func divAlignmentIsInheritedAndCenterTagWorks() {
        #expect(kinds("<div align=\"right\"><p>r</p></div>") == [.htmlParagraph(level: 0, alignment: .trailing, content: [.text("r")])])
        #expect(kinds("<center>c</center>") == [.htmlParagraph(level: 0, alignment: .center, content: [.text("c")])])
    }

    @Test func commentsAreHiddenAndUnsupportedHTMLStaysRaw() {
        #expect(kinds("<!-- hidden note -->").isEmpty)
        #expect(kinds("<form><input></form>") == [.htmlBlock("<form><input></form>")])
    }

    @Test func blockIdsStayDistinctForSiblingsFromOneHTMLBlock() {
        let blocks = MarkdownParser.parse("<p>a</p>\n<p>a</p>").blocks
        #expect(blocks.count == 2)
        #expect(blocks[0].id != blocks[1].id)
    }
}

@Suite struct DetailsTests {
    private func kinds(_ md: String) -> [Block.Kind] { MarkdownParser.parse(md).blocks.map(\.kind) }

    @Test func detailsWithMarkdownBodyIsOneCollapsibleBlock() throws {
        let md = """
        <details>
        <summary><b>Why the name?</b></summary>

        Because *reasons*.

        - one

        </details>

        after
        """
        let blocks = MarkdownParser.parse(md).blocks
        #expect(blocks.count == 2)
        guard case .details(let summary, let isOpen, let inner) = blocks[0].kind else { Issue.record("not details: \(blocks[0].kind)"); return }
        #expect(summary == [.strong([.text("Why the name?")])])
        #expect(!isOpen)
        #expect(inner.count == 2)
        #expect(blocks[0].lines == SourceLines(start: 1, end: 8))
        #expect(blocks[1].kind == .paragraph([.text("after")]))
    }

    @Test func openAttributeAndSingleBlockDetails() {
        #expect(kinds("<details open><summary>S</summary><p>body</p></details>") == [
            .details(summary: [.text("S")], isOpen: true, blocks: [
                Block(id: MarkdownParser.parse("<details open><summary>S</summary><p>body</p></details>").blocks[0].detailsChildren[0].id,
                      lines: SourceLines(start: 1, end: 1), kind: .htmlParagraph(level: 0, alignment: .leading, content: [.text("body")])),
            ]),
        ])
    }

    @Test func nestedDetails() {
        let md = "<details>\n<summary>outer</summary>\n\n<details>\n<summary>inner</summary>\n\nx\n\n</details>\n\n</details>"
        guard case .details(_, _, let outer)? = MarkdownParser.parse(md).blocks.first?.kind,
              case .details(let innerSummary, _, let inner)? = outer.first?.kind else { Issue.record("nesting lost"); return }
        #expect(innerSummary == [.text("inner")])
        #expect(inner.map(\.kind) == [.paragraph([.text("x")])])
    }

    @Test func unclosedDetailsStaysRaw() {
        #expect(kinds("<details>\n<summary>S</summary>\n\nbody") == [.htmlBlock("<details>\n<summary>S</summary>"), .paragraph([.text("body")])])
    }
}

extension Block {
    var detailsChildren: [Block] {
        if case .details(_, _, let blocks) = kind { return blocks }
        return []
    }
}
