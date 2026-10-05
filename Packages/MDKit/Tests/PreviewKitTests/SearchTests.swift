import AppKit
import Foundation
import MarkdownCore
import SwiftUI
import Testing
@testable import PreviewKit

private func blocks(_ markdown: String) -> [Block] {
    MarkdownPipeline.render(markdown, options: .default).document.blocks
}

private let sample = """
# Title one

Paragraph with **bold** text and a [link](https://example.com).

- item a
- item b

> quoted words

| H1 | H2 |
|---|---|
| c1 | c2 |

```swift
let x = 1
```
"""

@Suite struct SearchIndexTests {
    @Test func listsTheTextTheViewsDraw() {
        let runs = SearchIndex.runs(in: blocks(sample))
        #expect(runs.map(\.text) == ["Title one", "Paragraph with bold text and a link.", "item a", "item b", "quoted words", "H1", "H2", "c1", "c2", "let x = 1"])
    }

    @Test func tableCellsGetOneSlotEach() {
        let runs = SearchIndex.runs(in: blocks(sample))
        let table = runs.filter { ["H1", "H2", "c1", "c2"].contains($0.text) }
        #expect(table.map(\.key.slot) == [0, 1, 1_000, 1_001])
        #expect(Set(table.map(\.key.line)).count == 1)
    }

    @Test func nestedTextBelongsToItsTopLevelBlock() {
        let top = blocks("> quote one\n>\n> - nested item\n\nafter")
        let runs = SearchIndex.runs(in: top)
        #expect(runs.map(\.text) == ["quote one", "nested item", "after"])
        #expect(runs[0].topLevel == top[0].id)
        #expect(runs[1].topLevel == top[0].id, "text deep inside a quote scrolls to the quote")
        #expect(runs[2].topLevel == top[1].id)
    }

    @Test func leavesOutWhatIsNotTextInThePreview() {
        let doc = blocks("""
        ---
        title: hidden
        ---

        $$
        x^2
        $$

        ![alt only](pic.png)

        ---

        <!-- a hidden comment -->

        visible
        """)
        #expect(SearchIndex.runs(in: doc).map(\.text) == ["visible"])
    }

    @Test func aParagraphLaidOutAsImagesAndWordsIsNotSearched() {
        let doc = blocks("A line with an ![inline](pic.png) image\n\nplain")
        #expect(SearchIndex.runs(in: doc).map(\.text) == ["plain"])
    }

    @Test func detailsSearchTheSummaryAndOnlyOpenBodies() {
        let closed = blocks("<details>\n<summary>Sum</summary>\n\nhidden body\n\n</details>")
        #expect(SearchIndex.runs(in: closed).map(\.text) == ["Sum"])
        let open = blocks("<details open>\n<summary>Sum</summary>\n\nshown body\n\n</details>")
        #expect(SearchIndex.runs(in: open).map(\.text) == ["Sum", "shown body"])
        let keys = SearchIndex.runs(in: open).map(\.key)
        #expect(keys[0].slot == SearchRunKey.summarySlot)
        #expect(Set(keys).count == keys.count)
    }

    @Test func footnoteDefinitionsAreSearched() {
        let doc = blocks("Text[^1]\n\n[^1]: The note body.")
        #expect(SearchIndex.runs(in: doc).map(\.text).contains("The note body."))
    }

    @Test func everyRunHasItsOwnKeyInTheKitchenSink() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fixtures/kitchen-sink.md"), encoding: .utf8)
        let runs = SearchIndex.runs(in: blocks(source))
        #expect(runs.count > 20)
        #expect(Set(runs.map(\.key)).count == runs.count, "two runs share a key, so their highlights would collide")
    }

    @Test func searchTextIsWhatTheTextPiecesHold() {
        let inlines: [Inline] = [.text("price "), .math(latex: "x^2", display: false), .text(" and "), .emphasis([.text("price")])]
        #expect(InlineRenderer.searchText(inlines) == "price  and price")
        // Past the typesetting limit the formulas are drawn as source, so that is what can be found.
        let many = (0...InlineRenderer.maxTypesetFormulas).map { _ in Inline.math(latex: "y", display: false) }
        #expect(InlineRenderer.searchText(many) == String(repeating: "y", count: many.count))
    }
}

@Suite struct SearchRangeTests {
    private func found(_ query: String, in text: String, caseSensitive: Bool = false) -> [Range<Int>] {
        SearchIndex.ranges(of: query, in: text, caseSensitive: caseSensitive)
    }

    @Test func findsEveryOccurrence() {
        #expect(found("ab", in: "ab cab abab") == [0..<2, 4..<6, 7..<9, 9..<11])
    }

    @Test func matchesDoNotOverlap() {
        #expect(found("aa", in: "aaaaa") == [0..<2, 2..<4])
    }

    @Test func caseAndAccentsAreIgnoredUnlessAskedOtherwise() {
        #expect(found("cafe", in: "Café CAFE cafe") == [0..<4, 5..<9, 10..<14])
        #expect(found("cafe", in: "Café CAFE cafe", caseSensitive: true) == [10..<14])
        #expect(found("Café", in: "Café CAFE cafe", caseSensitive: true) == [0..<4])
    }

    @Test func offsetsCountCharactersNotUTF16Units() {
        #expect(found("a", in: "😀 a 👨‍👩‍👧 a e\u{301}a") == [2..<3, 6..<7, 9..<10])
    }

    @Test func emptyInputsFindNothing() {
        #expect(found("", in: "text").isEmpty)
        #expect(found("x", in: "").isEmpty)
        #expect(found("longer than the text", in: "short").isEmpty)
    }

    @Test func aMegabyteOfMatchesIsWalkedOnce() {
        let text = String(repeating: "ab ", count: 350_000)
        let start = ContinuousClock.now
        let result = found("ab", in: text)
        #expect(result.count == 350_000)
        #expect(ContinuousClock.now - start < .budget(5))
    }

    @Test func searchStopsAtTheLimitAndSaysSo() {
        let doc = blocks(String(repeating: "word ", count: 50))
        let result = SearchIndex.search(query: "word", caseSensitive: false, in: doc, limit: 10)
        #expect(result.matches.count == 10)
        #expect(result.truncated)
        #expect(!SearchIndex.search(query: "word", caseSensitive: false, in: doc, limit: 50).truncated)
    }
}

@Suite struct SearchHighlightTests {
    private let theme = PreviewTheme.github

    private func marked(_ text: AttributedString) -> [String] {
        text.runs.filter { $0.backgroundColor != nil }.map { String(text[$0.range].characters) }
    }

    @Test func colorsExactlyTheMatchedCharacters() {
        var text = AttributedString("Hello world, hello")
        text.applySearchHighlights([SearchHighlight(range: 0..<5, isCurrent: false), SearchHighlight(range: 13..<18, isCurrent: true)], offset: 0, theme: theme)
        #expect(marked(text) == ["Hello", "hello"])
        let colours = text.runs.compactMap(\.backgroundColor)
        #expect(colours.count == 2)
        #expect(colours[0] != colours[1], "the current match looks different")
    }

    @Test func offsetsAreRelativeToTheWholeRun() {
        var piece = AttributedString(" and price")   // the second piece of "price " + formula + " and price"
        piece.applySearchHighlights([SearchHighlight(range: 11..<16, isCurrent: false)], offset: 6, theme: theme)
        #expect(marked(piece) == ["price"])
    }

    @Test func rangesOutsideThePieceAreIgnoredAndClipped() {
        var piece = AttributedString("middle")
        piece.applySearchHighlights([
            SearchHighlight(range: 0..<3, isCurrent: false),     // before this piece (it covers 5..<11 of the run)
            SearchHighlight(range: 11..<14, isCurrent: false),   // after it
            SearchHighlight(range: 9..<13, isCurrent: false),    // straddles its end
        ], offset: 5, theme: theme)
        #expect(marked(piece) == ["le"])
    }

    @Test func unsortedInputIsFine() {
        var text = AttributedString("a b c")
        text.applySearchHighlights([SearchHighlight(range: 4..<5, isCurrent: false), SearchHighlight(range: 0..<1, isCurrent: false)], offset: 0, theme: theme)
        #expect(marked(text) == ["a", "c"])
    }

    @Test func emojiAndCombiningMarksCountAsOneCharacter() {
        var text = AttributedString("😀 a e\u{301}a")
        text.applySearchHighlights([SearchHighlight(range: 2..<3, isCurrent: false), SearchHighlight(range: 5..<6, isCurrent: false)], offset: 0, theme: theme)
        #expect(marked(text) == ["a", "a"])
    }

    @Test func aFormulaDoesNotShiftTheTextAfterIt() {
        let inlines: [Inline] = [.text("price "), .math(latex: "x^2", display: false), .text(" and price")]
        let runText = InlineRenderer.searchText(inlines)
        #expect(runText == "price  and price")
        let second = SearchIndex.ranges(of: "price", in: runText, caseSensitive: false)[1]
        let pieces = InlineRenderer.highlightedPieces(inlines, theme: theme, highlights: [SearchHighlight(range: second, isCurrent: true)])
        let texts: [AttributedString] = pieces.compactMap { if case .text(let text) = $0 { text } else { nil } }
        #expect(texts.count == 2)
        #expect(marked(texts[0]).isEmpty)
        #expect(marked(texts[1]) == ["price"])
    }

    @Test func noHighlightsLeavesTheTextAlone() {
        let inlines: [Inline] = [.text("plain "), .strong([.text("bold")])]
        let plain = InlineRenderer.pieces(inlines, theme: theme)
        let same = InlineRenderer.highlightedPieces(inlines, theme: theme, highlights: [])
        #expect(plain.count == same.count)
        if case .text(let a) = plain[0], case .text(let b) = same[0] { #expect(a == b) }
    }
}

@MainActor
@Suite struct PreviewSearchTests {
    private func search(_ markdown: String = sample, query: String, caseSensitive: Bool = false) async -> PreviewSearch {
        let search = PreviewSearch(debounce: .milliseconds(1))
        search.update(blocks: blocks(markdown))
        search.show()
        search.query = query
        search.caseSensitive = caseSensitive
        search.queryChanged()
        await search.settle()
        return search
    }

    @Test func findsAcrossBlocksAndStartsOnTheFirst() async {
        let search = await search(query: "i")
        #expect(search.matches.count == 5, "Title, with, link, item, item: \(search.matches.map(\.range))")
        #expect(search.currentIndex == 0)
        #expect(search.status == "1 of 5")
    }

    @Test func nextAndPreviousWrapAround() async {
        let search = await search(query: "item")
        #expect(search.matches.count == 2)
        search.next()
        #expect(search.currentIndex == 1)
        search.next()
        #expect(search.currentIndex == 0)
        search.previous()
        #expect(search.currentIndex == 1)
        #expect(search.status == "2 of 2")
    }

    @Test func movingAsksThePreviewToScroll() async {
        let search = await search(query: "item")
        let before = search.revealToken
        search.next()
        #expect(search.revealToken == before + 1)
        #expect(search.currentMatch?.topLevel != nil)
    }

    @Test func statusReportsEmptyAndMissing() async {
        let none = await search(query: "zzz")
        #expect(none.status == "No results")
        #expect(none.currentIndex == nil)
        none.next()   // must not crash with nothing to go to
        let empty = await search(query: "")
        #expect(empty.status == "")
        #expect(empty.matches.isEmpty)
    }

    @Test func closingClearsEverythingTheViewsShow() async {
        let search = await search(query: "item")
        let key = try! #require(search.matches.first?.key)
        #expect(!search.highlights(for: key).isEmpty)
        search.close()
        #expect(!search.isPresented)
        #expect(search.matches.isEmpty)
        #expect(search.highlights(for: key).isEmpty)
        #expect(search.query == "item", "the query is remembered for next time")
    }

    @Test func caseSensitivityChangesTheResult() async {
        let insensitive = await search(query: "TITLE")
        #expect(insensitive.matches.count == 1)
        let sensitive = await search(query: "TITLE", caseSensitive: true)
        #expect(sensitive.matches.isEmpty)
    }

    @Test func onlyTheCurrentMatchIsMarkedCurrent() async {
        let search = await search("one one one", query: "one")
        let key = try! #require(search.matches.first?.key)
        func current() -> [Bool] { search.highlights(for: key).map(\.isCurrent) }
        #expect(current() == [true, false, false])
        search.next()
        #expect(current() == [false, true, false])
        search.previous()
        search.previous()
        #expect(current() == [false, false, true])
    }

    @Test func editingTheDocumentKeepsTheSearchAndPosition() async {
        let search = await search("one one one", query: "one")
        search.next()
        search.update(blocks: blocks("one one one one\n\nand one more"))
        await search.settle()
        #expect(search.matches.count == 5)
        #expect(search.currentIndex == 1, "the position stays where it was")
        search.update(blocks: blocks("only one left"))
        await search.settle()
        #expect(search.matches.count == 1)
        #expect(search.currentIndex == 0, "and is clamped when matches disappear")
    }

    @Test func aDocumentChangeWhileClosedDoesNotSearch() async {
        let search = PreviewSearch(debounce: .milliseconds(1))
        search.query = "one"
        search.update(blocks: blocks("one"))
        await search.settle()
        #expect(search.matches.isEmpty)
        search.show()
        await search.settle()
        #expect(search.matches.count == 1, "opening the bar searches what it already has")
    }

    @Test func theLastSearchWins() async {
        let search = PreviewSearch(debounce: .milliseconds(30))
        search.update(blocks: blocks("alpha beta"))
        search.show()
        search.query = "alpha"
        search.queryChanged()
        search.query = "beta"
        search.queryChanged()
        await search.settle()
        #expect(search.matches.map(\.range) == [6..<10])
    }

    @Test func tooManyMatchesAreCappedAndMarked() async {
        let search = await search(String(repeating: "a ", count: PreviewSearch.maxMatches + 500), query: "a")
        #expect(search.matches.count == PreviewSearch.maxMatches)
        #expect(search.isTruncated)
        #expect(search.status == "1 of \(PreviewSearch.maxMatches)+")
    }

    @Test func askingForFindAgainRefocusesTheField() async {
        let search = await search(query: "item")
        let before = search.focusToken
        search.show()
        #expect(search.focusToken == before + 1)
    }

    @Test func nextWhileClosedOpensTheBar() {
        let search = PreviewSearch()
        search.next()
        #expect(search.isPresented)
    }
}

@MainActor
@Suite(.requiresWindowServer) struct PreviewSearchRenderTests {
    @Test func theRealPreviewDrawsWithAnActiveSearch() async throws {
        _ = NSApplication.shared
        let rendered = MarkdownPipeline.render(sample + "\n\nMore item text.\n", options: .default)
        let search = PreviewSearch(debounce: .milliseconds(1))
        let host = NSHostingController(rootView: MarkdownPreview(rendered: rendered, baseURL: nil, search: search))
        let window = NSWindow(contentViewController: host)
        window.setFrame(NSRect(x: -20000, y: -20000, width: 700, height: 800), display: false)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))
        search.show()
        search.query = "item"
        search.queryChanged()
        await search.settle()
        #expect(search.matches.count == 3)
        search.next()
        search.next()
        try await Task.sleep(for: .milliseconds(300))   // let SwiftUI draw the highlights and scroll
        search.close()
        try await Task.sleep(for: .milliseconds(100))
        #expect(search.matches.isEmpty)
    }
}
