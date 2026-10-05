import AppKit
import Foundation
import Testing
@testable import EditorKit

/// Deterministic pseudo-random numbers, so a failing edit sequence can be replayed.
private struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(Swift.max(1, bound))) }
}

@Suite struct LineIndexTests {
    @Test func startsOfEachLine() {
        let index = LineIndex("ab\ncd\n\nef" as NSString)
        #expect(index.starts == [0, 3, 6, 7])
        #expect(index.lineCount == 4)
        #expect(index.range(ofLine: 0) == NSRange(location: 0, length: 3))
        #expect(index.contentRange(ofLine: 0) == NSRange(location: 0, length: 2))
        #expect(index.contentRange(ofLine: 3) == NSRange(location: 7, length: 2))
    }

    @Test func emptyAndTrailingNewline() {
        #expect(LineIndex("" as NSString).lineCount == 1)
        let index = LineIndex("a\n" as NSString)
        #expect(index.lineCount == 2)
        #expect(index.range(ofLine: 1) == NSRange(location: 2, length: 0))
    }

    @Test func findsTheLineAtALocation() {
        let index = LineIndex("ab\ncd\n\nef" as NSString)
        #expect([0, 1, 2, 3, 5, 6, 7, 9].map(index.line(containing:)) == [0, 0, 0, 1, 1, 2, 3, 3])
    }

    @Test func otherLineSeparatorsDoNotSplitLines() {
        #expect(LineIndex("a\u{2028}b\rc" as NSString).lineCount == 1)
    }

    @Test func randomEditsMatchARescan() {
        var random = SplitMix64(state: 7)
        let pieces = ["a", "\n", "bc", "\n\n", "😀", "日本\n", "", "x\ny\nz"]
        var text = "first\nsecond\n\nthird" as NSString
        var index = LineIndex(text)
        for _ in 0..<600 {
            let location = random.below(text.length + 1)
            let length = random.below(Swift.min(8, text.length - location) + 1)
            let range = NSRange(location: location, length: length)
            let piece = pieces[random.below(pieces.count)] as NSString
            text = text.replacingCharacters(in: range, with: piece as String) as NSString
            index.replace(range, with: piece)
            #expect(index == LineIndex(text))
        }
    }

    @Test func changeDescribesTheTouchedLines() {
        var index = LineIndex("a\nb\nc\nd" as NSString)
        // Replace "b\nc" (lines 1 and 2) with "x": two lines become one.
        let change = index.replace(NSRange(location: 2, length: 3), with: "x" as NSString)
        #expect(change == LineIndex.Change(first: 1, removed: 1, inserted: 0))
        let more = index.replace(NSRange(location: 2, length: 0), with: "p\nq\n" as NSString)
        #expect(more == LineIndex.Change(first: 1, removed: 0, inserted: 2))
    }
}

@MainActor
private func make(_ text: String, theme: EditorTheme = .tomorrowPlus, maxLines: Int = 1500) -> (NSTextStorage, EditorHighlighter) {
    let storage = NSTextStorage(string: text)
    let highlighter = EditorHighlighter(theme: theme, configuration: .macDownDefaults)
    highlighter.maxLinesPerPass = maxLines
    highlighter.attach(to: storage)
    return (storage, highlighter)
}


/// What the user sees at each UTF-16 position: colours, strike-through, paragraph style and — for
/// ASCII, where the font is ours — the font. (AppKit swaps in a fallback font for emoji and CJK when
/// text enters a storage on its own, which a re-colouring pass inside an edit does not repeat.)
@MainActor
private func appearance(_ storage: NSTextStorage) -> [String] {
    let text = storage.string as NSString
    return (0..<storage.length).map { i in
        let attributes = storage.attributes(at: i, effectiveRange: nil)
        let font = text.character(at: i) < 0x80 ? (attributes[.font] as? NSFont).map { "\($0.fontName) \($0.pointSize)" } ?? "-" : "fallback"
        return [String(describing: attributes[.foregroundColor]), String(describing: attributes[.backgroundColor]),
                String(describing: attributes[.strikethroughStyle]), String(describing: attributes[.paragraphStyle]), font].joined(separator: "|")
    }
}

@MainActor
private func color(_ storage: NSTextStorage, at location: Int) -> NSColor? {
    storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
}

@MainActor
private func font(_ storage: NSTextStorage, at location: Int) -> NSFont? {
    storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
}

@MainActor
@Suite struct EditorHighlighterTests {
    let theme = EditorTheme.tomorrowPlus

    @Test func appliesThemeColoursAndFonts() throws {
        let (storage, _) = make("# Title\n\nplain *em* and **strong**\n")
        let heading = try #require(editorColor(theme.style(for: .heading1)?.color))
        #expect(color(storage, at: 2) == heading)
        #expect(font(storage, at: 2)?.pointSize ?? 0 > 14 * 1.5)    // H1 is 24/14 of the body size
        #expect(color(storage, at: 9) == editorColor(theme.foreground))
        let ns = storage.string as NSString
        let emphasis = ns.range(of: "*em*").location
        #expect(color(storage, at: emphasis) == editorColor(theme.style(for: .emphasis)?.color))
        #expect(font(storage, at: emphasis)?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        let strong = ns.range(of: "**strong**").location
        #expect(font(storage, at: strong)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func emphasisInsideAHeadingKeepsTheHeadingSize() throws {
        let (storage, _) = make("# Big *italic* title")
        let location = (storage.string as NSString).range(of: "italic").location
        let heading = try #require(font(storage, at: 2))
        let inner = try #require(font(storage, at: location))
        #expect(inner.pointSize == heading.pointSize)
        #expect(inner.fontDescriptor.symbolicTraits.contains(.italic))
        #expect(inner.fontDescriptor.symbolicTraits.contains(.bold), "H1 is bold in Tomorrow+")
    }

    @Test func codeFencesColourEveryLineUntilTheCloser() throws {
        let (storage, highlighter) = make("before\n```swift\nlet x = *y*\n```\nafter *em*\n")
        highlighter.finishPending()
        let code = try #require(editorColor(theme.style(for: .codeBlock)?.color))
        let ns = storage.string as NSString
        #expect(color(storage, at: ns.range(of: "let x").location) == code)
        #expect(color(storage, at: ns.range(of: "*y*").location) == code, "no emphasis inside a fence")
        #expect(color(storage, at: ns.range(of: "*em*").location) == editorColor(theme.style(for: .emphasis)?.color))
        #expect(color(storage, at: 0) == editorColor(theme.foreground))
    }

    @Test func typingAFenceRecoloursTheLinesBelowAndClosingItRestoresThem() throws {
        let (storage, highlighter) = make("intro\n\n# Heading\nsome *text*\n")
        let ns = { storage.string as NSString }
        let emphasis = try #require(editorColor(theme.style(for: .emphasis)?.color))
        #expect(color(storage, at: ns().range(of: "*text*").location) == emphasis)

        storage.replaceCharacters(in: NSRange(location: 6, length: 0), with: "```\n")   // open a fence on its own line
        highlighter.finishPending()
        let code = try #require(editorColor(theme.style(for: .codeBlock)?.color))
        #expect(color(storage, at: ns().range(of: "*text*").location) == code)
        #expect(color(storage, at: ns().range(of: "# Heading").location) == code)

        storage.replaceCharacters(in: NSRange(location: 6, length: 4), with: "")        // take it away again
        highlighter.finishPending()
        #expect(color(storage, at: ns().range(of: "*text*").location) == emphasis)
    }

    @Test func anEditStopsOnceTheStateSettles() {
        var text = ""
        for i in 0..<300 { text += "line \(i) *x*\n" }
        let (storage, highlighter) = make(text)
        highlighter.finishPending()
        // Mark every attribute run so a re-coloured line can be told apart from an untouched one.
        let probe = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        storage.beginEditing()
        storage.addAttribute(.backgroundColor, value: probe, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        storage.replaceCharacters(in: NSRange(location: 20, length: 0), with: "z")
        let ns = storage.string as NSString
        // The edited line was recoloured (base attributes drop the probe); a distant line was not.
        #expect(storage.attribute(.backgroundColor, at: 20, effectiveRange: nil) == nil)
        #expect(storage.attribute(.backgroundColor, at: ns.length - 3, effectiveRange: nil) as? NSColor == probe)
        #expect(highlighter.isUpToDate)
    }

    @Test func longRunsAreSplitIntoPasses() {
        var text = "```\n"
        for i in 0..<500 { text += "code \(i)\n" }
        let (storage, highlighter) = make(text, maxLines: 100)
        #expect(!highlighter.isUpToDate, "500 fenced lines can't finish in a 100-line pass")
        let tail = (storage.string as NSString).range(of: "code 499").location
        #expect(color(storage, at: tail) == editorColor(theme.foreground), "not coloured yet, but readable")
        highlighter.finishPending()
        #expect(highlighter.isUpToDate)
        #expect(color(storage, at: tail) == editorColor(theme.style(for: .codeBlock)?.color))
    }

    @Test func editingWhileColouringIsPendingStaysCorrect() {
        var text = "```\n"
        for i in 0..<400 { text += "code \(i)\n" }
        text += "```\nafter *em*\n"
        let (storage, highlighter) = make(text, maxLines: 50)
        // Edit near the top, near the middle (inside the stale zone), and at the end before finishing.
        storage.replaceCharacters(in: NSRange(location: 8, length: 0), with: "!")
        storage.replaceCharacters(in: NSRange(location: 1500, length: 0), with: "?\n")
        storage.replaceCharacters(in: NSRange(location: storage.length - 2, length: 0), with: " more")
        highlighter.finishPending()
        let (fresh, freshHighlighter) = make(storage.string, maxLines: 50)
        freshHighlighter.finishPending()
        #expect(appearance(storage) == appearance(fresh))
        #expect(highlighter.lineStates == freshHighlighter.lineStates)
    }

    @Test func anEditBeforeUnfinishedColouringDoesNotAbandonIt() throws {
        var text = "intro\npara *em*\n"
        for i in 0..<200 { text += "text \(i) *x*\n" }
        let (storage, highlighter) = make(text, maxLines: 20)
        highlighter.finishPending()

        storage.replaceCharacters(in: NSRange(location: 6, length: 0), with: "```\n")   // a fence now swallows 200 lines
        #expect(!highlighter.isUpToDate, "20 lines per pass can't reach the end")
        storage.replaceCharacters(in: NSRange(location: 12, length: 0), with: "x")      // an edit inside it, before the unfinished part
        highlighter.finishPending()

        let tail = (storage.string as NSString).range(of: "text 199").location
        #expect(color(storage, at: tail) == editorColor(theme.style(for: .codeBlock)?.color))
        #expect(highlighter.lineStates.last == .fence("`", 3))
    }

    @Test func changingTheThemeRecolours() throws {
        let (storage, highlighter) = make("# Title\n")
        highlighter.theme = .solarizedLight
        highlighter.restyleAll()
        #expect(color(storage, at: 2) == editorColor(EditorTheme.solarizedLight.style(for: .heading1)?.color))
        #expect(color(storage, at: 2) != editorColor(theme.style(for: .heading1)?.color))
    }

    @Test func frontMatterIsColouredOnlyAtTheTop() throws {
        let (storage, highlighter) = make("---\ntitle: Hi\n---\n# Doc\n\n---\nnot: front matter\n---\n")
        highlighter.finishPending()
        let comment = try #require(editorColor(theme.style(for: .frontMatter)?.color))
        let ns = storage.string as NSString
        #expect(color(storage, at: ns.range(of: "title").location) == comment)
        #expect(color(storage, at: ns.range(of: "not: front").location) != comment)
        #expect(highlighter.lineStates.prefix(4) == [.documentStart, .frontMatterCandidate, .frontMatter, .normal])
    }

    @Test func replacingEverythingRebuildsTheIndex() {
        let (storage, highlighter) = make("# One\ntwo\n")
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "```\nx\n```\n")
        highlighter.finishPending()
        #expect(highlighter.lineCount == 4)
        #expect(highlighter.lineStates == [.documentStart, .fence("`", 3), .fence("`", 3), .normal])
    }

    @Test func emptyDocument() {
        let (storage, highlighter) = make("")
        #expect(highlighter.lineCount == 1)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Hi")
        #expect(color(storage, at: 0) == editorColor(theme.style(for: .heading1)?.color))
        storage.replaceCharacters(in: NSRange(location: 0, length: 4), with: "")
        #expect(highlighter.lineCount == 1)
    }

    @Test(arguments: [3, 11, 29, 101])
    func randomEditSequencesMatchAFreshPass(seed: UInt64) {
        var random = SplitMix64(state: seed)
        let pieces = ["# ", "```", "\n", "*", "**", "- ", "> ", "`", "$$", "<!--", "-->", "---", "word ", "日本", "😀", "~~~", "1. ",
                      "[x](y) ", "==", "&amp; ", "title: ", "...", "\n\n", ""]
        var base = "# Start\n\n- one\n- two\n\n```swift\ncode\n```\n\n> quote *em*\n"
        for i in 0..<60 { base += i % 15 == 7 ? "```\n" : "line \(i) with *em* and `code`\n" }
        let (storage, highlighter) = make(base, maxLines: 4)
        for step in 0..<250 {
            let location = random.below(storage.length + 1)
            let length = random.below(Swift.min(6, storage.length - location) + 1)
            storage.replaceCharacters(in: NSRange(location: location, length: length), with: pieces[random.below(pieces.count)])
            if random.below(3) == 0 { highlighter.finishPending() }   // sometimes edit again while a pass is pending
            if step % 25 == 24 {
                highlighter.finishPending()
                let (fresh, freshHighlighter) = make(storage.string, maxLines: 4)
                freshHighlighter.finishPending()
                #expect(highlighter.lineStates == freshHighlighter.lineStates, "line states diverged at step \(step), seed \(seed)")
                #expect(appearance(storage) == appearance(fresh), "attributes diverged at step \(step), seed \(seed)")
            }
        }
    }

    @Test(.timeLimit(.minutes(1))) func aMegabyteLoadsAndTypesQuickly() {
        var text = ""
        for i in 0..<20_000 { text += "Line \(i) with *emphasis*, `code` and a [link](https://example.com/\(i)).\n" }
        #expect(text.utf8.count > 1_000_000)
        let start = ContinuousClock.now
        let (storage, highlighter) = make(text)
        let loaded = ContinuousClock.now - start
        #expect(loaded < .budget(1.5), "first pass must be bounded, took \(loaded)")
        highlighter.finishPending()

        let typing = ContinuousClock.now
        for i in 0..<50 { storage.replaceCharacters(in: NSRange(location: 40_000 + i, length: 0), with: "x") }
        let perKey = (ContinuousClock.now - typing) / 50
        #expect(perKey < .budget(0.016), "typing in the middle of a 1 MB file took \(perKey) per key")
    }
}
