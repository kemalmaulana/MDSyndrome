import Foundation
import Testing
@testable import EditorKit

/// (text, kind) pairs for one line, so assertions read like the source.
private func scan(_ line: String, _ state: LineState = .normal) -> (tokens: [String: EditorTokenKind], list: [(String, EditorTokenKind)], next: LineState) {
    let result = SourceHighlighter.tokens(line: line, state: state)
    let ns = line as NSString
    let list = result.tokens.map { (ns.substring(with: $0.range), $0.kind) }
    var byText: [String: EditorTokenKind] = [:]
    for (text, kind) in list { byText[text] = kind }
    return (byText, list, result.next)
}

private func kinds(_ line: String, _ state: LineState = .normal) -> [EditorTokenKind] {
    scan(line, state).list.map(\.1)
}

@Suite struct BlockTokenTests {
    @Test(arguments: [
        ("# One", EditorTokenKind.heading1), ("## Two", .heading2), ("### Three", .heading3),
        ("#### Four", .heading4), ("##### Five", .heading5), ("###### Six", .heading6), ("   # Indented", .heading1),
    ])
    func headings(line: String, kind: EditorTokenKind) {
        #expect(scan(line).list.first?.1 == kind)
        #expect(scan(line).list.first?.0 == line)
    }

    @Test func notHeadings() {
        #expect(kinds("#hashtag").isEmpty)
        #expect(kinds("####### seven").isEmpty)
        #expect(kinds("    # code-indented").isEmpty)
    }

    @Test func emphasisInsideAHeadingKeepsBothTokens() {
        let result = scan("## A *new* start")
        #expect(result.list.map(\.1) == [.heading2, .emphasis])
        #expect(result.list[1].0 == "*new*")
    }

    @Test func listAndTaskMarkers() {
        #expect(scan("- item").list.first?.0 == "-")
        #expect(scan("  * nested").list.first?.0 == "*")
        #expect(scan("12. twelfth").list.first?.0 == "12.")
        #expect(scan("3) paren").list.first?.0 == "3)")
        let task = scan("- [x] done")
        #expect(task.list.map(\.1) == [.listMarker, .taskMarker])
        #expect(task.list[1].0 == "[x]")
        #expect(kinds("-no space").isEmpty)
        #expect(kinds("**bold** start") == [.strong])
    }

    @Test func blockquotesAndRules() {
        #expect(kinds("> quoted") == [.blockquote])
        #expect(kinds("> quoted *em*") == [.blockquote, .emphasis])
        #expect(kinds("---") == [.horizontalRule])
        #expect(kinds("* * *") == [.horizontalRule])
        #expect(kinds("___") == [.horizontalRule])
        #expect(kinds("--") == [])
    }

    @Test func referenceDefinitionsAndFootnotes() {
        let reference = scan("[docs]: https://example.com/docs")
        #expect(reference.list.map(\.1) == [.reference, .url])
        #expect(reference.list[0].0 == "[docs]")
        #expect(scan("[^1]: A note.").list.first?.1 == .reference)
    }
}

@Suite struct MultiLineStateTests {
    @Test func backtickFenceOpensAndCloses() {
        let open = scan("```swift")
        #expect(open.list.map(\.1) == [.codeBlock])
        #expect(open.next == .fence("`", 3))
        #expect(scan("let x = 1 // *not* emphasis", open.next).list.map(\.1) == [.codeBlock])
        #expect(scan("let x = 1", open.next).next == open.next)
        #expect(scan("```", open.next).next == .normal)
        #expect(scan("   ```  ", open.next).next == .normal)
        #expect(scan("````", open.next).next == .normal)       // longer closers close
        #expect(scan("``", open.next).next == open.next)        // shorter ones don't
        #expect(scan("```swift", open.next).next == open.next)  // a closer has no info string
    }

    @Test func tildeFencesNeedTildeClosers() {
        let open = scan("~~~")
        #expect(open.next == .fence("~", 3))
        #expect(scan("```", open.next).next == open.next)
        #expect(scan("~~~~", open.next).next == .normal)
    }

    @Test func inlineTripleBackticksAreNotAFence() {
        #expect(scan("```code``` on one line").next == .normal)
    }

    @Test func fenceNeedsToBeShallow() {
        #expect(scan("    ```").next == .normal)
    }

    @Test func mathBlock() {
        let open = scan("$$")
        #expect(open.list.map(\.1) == [.math])
        #expect(open.next == .math)
        #expect(scan("\\frac{a}{b} * c", .math).list.map(\.1) == [.math])
        #expect(scan("$$", .math).next == .normal)
    }

    @Test func commentsSpanLines() {
        let open = scan("text <!-- start")
        #expect(open.list.last?.1 == .comment)
        #expect(open.next == .comment)
        #expect(scan("still inside", .comment).next == .comment)
        let close = scan("end --> and *em*", .comment)
        #expect(close.next == .normal)
        #expect(close.list.map(\.1) == [.comment, .emphasis])
        #expect(scan("one <!-- whole --> line").next == .normal)
    }

    @Test func frontMatterNeedsAKeyOnTheSecondLine() {
        let first = scan("---", .documentStart)
        #expect(first.list.map(\.1) == [.horizontalRule])
        #expect(first.next == .frontMatterCandidate)

        let key = scan("title: My *doc*", .frontMatterCandidate)
        #expect(key.list.map(\.1) == [.frontMatter])
        #expect(key.next == .frontMatter)
        #expect(scan("  - tag", .frontMatter).list.map(\.1) == [.frontMatter])
        #expect(scan("---", .frontMatter).next == .normal)
        #expect(scan("...", .frontMatter).next == .normal)
        #expect(scan("---", .frontMatter).list.map(\.1) == [.horizontalRule])
    }

    @Test func aThematicBreakAtTheTopIsNotFrontMatter() {
        let break_ = scan("---", .documentStart)
        let next = scan("Just a paragraph", break_.next)
        #expect(next.next == .normal)
        #expect(next.list.isEmpty)
        let heading = scan("# Title", break_.next)
        #expect(heading.list.map(\.1) == [.heading1])
    }

    @Test func frontMatterOnlyOpensAtTheStart() {
        #expect(scan("---", .normal).next == .normal)
        #expect(scan("---", .normal).list.map(\.1) == [.horizontalRule])
    }

    @Test func plainLinesKeepTheirState() {
        #expect(scan("hello", .documentStart).next == .normal)
        #expect(scan("", .normal).next == .normal)
        #expect(scan("", .fence("`", 3)).next == .fence("`", 3))
    }
}

@Suite struct InlineTokenTests {
    @Test func codeSpansProtectTheirContent() {
        let result = scan("use `*a* and **b**` here")
        #expect(result.list.map(\.1) == [.code])
        #expect(result.list[0].0 == "`*a* and **b**`")
        #expect(scan("``a ` b``").list.first?.0 == "``a ` b``")
    }

    @Test func emphasisAndStrong() {
        let result = scan("*one* **two** _three_ __four__")
        #expect(result.list.map(\.0) == ["**two**", "__four__", "*one*", "_three_"])
        #expect(result.list.map(\.1) == [.strong, .strong, .emphasis, .emphasis])
    }

    @Test func emphasisHeuristicsLikeCommonMark() {
        #expect(kinds("2 * 3 * 4").isEmpty)
        #expect(kinds("snake_case_name").isEmpty)
        #expect(kinds(#"\*not emphasis\*"#).isEmpty)
        #expect(kinds("a*b*c").isEmpty)
    }

    @Test func strikethroughAndHighlight() {
        #expect(scan("~~gone~~").list.first?.1 == .strikethrough)
        #expect(scan("==marked==").list.first?.1 == .highlight)
        #expect(kinds("a == b").isEmpty)
    }

    @Test func linksImagesAndReferences() {
        let link = scan("see [the docs](https://example.com \"Title\") now")
        #expect(link.list.map(\.1) == [.link, .url, .url])   // the label, the ( … ) part, then the bare URL inside it
        #expect(link.list[0].0 == "[the docs]")
        #expect(scan("![alt text](img.png)").list.map(\.1) == [.image])
        #expect(scan("[text][ref]").list.first?.1 == .link)
        #expect(scan("note[^1] here").list.first?.1 == .reference)
    }

    @Test func autolinksAndHTML() {
        #expect(scan("go to https://example.com/path now").list.first?.0 == "https://example.com/path")
        #expect(scan("<https://example.com>").list.first?.1 == .url)
        #expect(scan("a <span class=\"x\">b</span>").list.map(\.1) == [.html, .html])
        #expect(scan("<!-- note -->").list.map(\.1) == [.comment])
        #expect(scan("AT&amp;T &#169; &copy;").list.map(\.1) == [.htmlEntity, .htmlEntity, .htmlEntity])
        #expect(kinds("1 < 2 and 3 > 2").isEmpty)
    }

    @Test func inlineMath() {
        #expect(scan("energy $E = mc^2$ here").list.first?.0 == "$E = mc^2$")
        #expect(scan("$$x^2$$").list.first?.1 == .math)
        #expect(kinds("costs $5 and $10").isEmpty)
        #expect(kinds("`$a$` code").contains(.math) == false)
    }

    @Test func rangesAreUTF16() {
        let line = "😀 日本 **bold** 😀"
        let strong = scan(line).list.first { $0.1 == .strong }
        #expect(strong?.0 == "**bold**")
        let ns = line as NSString
        let tokens = SourceHighlighter.tokens(line: line, state: .normal).tokens
        #expect(tokens.allSatisfy { NSMaxRange($0.range) <= ns.length })
    }

    @Test func veryLongLinesSkipInlineColouring() {
        let long = String(repeating: "*a* ", count: SourceHighlighter.maxInlineLength)
        #expect(SourceHighlighter.tokens(line: long, state: .normal).tokens.isEmpty)
        let heading = "# " + long
        #expect(SourceHighlighter.tokens(line: heading, state: .normal).tokens.map(\.kind) == [.heading1])
    }

    @Test func pathologicalLinesFinishQuickly() {
        let lines = [String(repeating: "*", count: 3000), String(repeating: "[a](", count: 800), String(repeating: "`", count: 3500),
                     String(repeating: "_a ", count: 1300), String(repeating: "<", count: 3900)]
        let start = ContinuousClock.now
        for line in lines { _ = SourceHighlighter.tokens(line: line, state: .normal) }
        #expect(ContinuousClock.now - start < .budget(2))
    }
}
