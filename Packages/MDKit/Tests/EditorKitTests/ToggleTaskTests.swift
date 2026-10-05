import Foundation
import Testing
@testable import EditorKit

@Suite struct ToggleTaskTransformTests {
    /// The edit for the line of `text` that starts at `lineStart` and runs to its end.
    private func toggle(_ text: String, line lineIndex: Int = 0, selection: NSRange = NSRange(location: 0, length: 0)) -> TextEdit? {
        let ns = text as NSString
        var location = 0
        var start = 0
        var current = 0
        while current < lineIndex, location < ns.length {
            if ns.character(at: location) == 0x0A { current += 1; start = location + 1 }
            location += 1
        }
        let end = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start))
        let length = (end.location == NSNotFound ? ns.length : end.location) - start
        return EditTransforms.toggleTask(in: ns, lineRange: NSRange(location: start, length: length), selection: selection)
    }

    @Test(arguments: [
        ("- [ ] a", "- [x] a"),
        ("- [x] a", "- [ ] a"),
        ("- [X] a", "- [ ] a"),
        ("* [ ] a", "* [x] a"),
        ("+ [ ] a", "+ [x] a"),
        ("1. [ ] a", "1. [x] a"),
        ("12) [x] a", "12) [ ] a"),
        ("  - [ ] nested", "  - [x] nested"),
        ("\t- [ ] tab", "\t- [x] tab"),
        ("> - [ ] quoted", "> - [x] quoted"),
        (">- [ ] tight quote", ">- [x] tight quote"),
        ("> > 2. [x] deep", "> > 2. [ ] deep"),
        ("-   [ ]   spaced", "-   [x]   spaced"),
        ("- [ ] text with [brackets] and [ ] again", "- [x] text with [brackets] and [ ] again"),
        ("- [ ]\ttab after", "- [x]\ttab after"),
        ("- [ ]", "- [x]"),
    ])
    func flipsTheMarker(line: String, expected: String) throws {
        let edit = try #require(toggle(line))
        #expect(edit.applied(to: line) == expected)
        #expect(edit.range.length == 1)
        #expect(edit.replacement == "x" || edit.replacement == " ")
    }

    @Test(arguments: ["- a", "- [] a", "- [ ]a", "- [x]a", "[ ] a", "- [y] a", "- [  ] a", "text - [ ] a", "-[ ] a", "1.[ ] a", "", "   ", "# - [ ] heading", "```", "> text", "- ( ) a", "-- [ ] a", "- [-] a"])
    func refusesALineWithoutATaskMarker(line: String) {
        #expect(toggle(line) == nil, "\(line.debugDescription)")
    }

    @Test func keepsTheSelectionWhereItWas() throws {
        let text = "- [ ] first\n- [ ] second"
        let selection = NSRange(location: 14, length: 3)
        let edit = try #require(toggle(text, line: 1, selection: selection))
        #expect(edit.selection == selection)
        #expect(edit.applied(to: text) == "- [ ] first\n- [x] second")
    }

    @Test func worksOnAnyLineOfALongerText() throws {
        let text = "# Title\n\n- [ ] one\n- [x] two\n  - [ ] three\n\nplain\n"
        #expect(try #require(toggle(text, line: 2)).applied(to: text) == "# Title\n\n- [x] one\n- [x] two\n  - [ ] three\n\nplain\n")
        #expect(try #require(toggle(text, line: 3)).applied(to: text) == "# Title\n\n- [ ] one\n- [ ] two\n  - [ ] three\n\nplain\n")
        #expect(try #require(toggle(text, line: 4)).applied(to: text) == "# Title\n\n- [ ] one\n- [x] two\n  - [x] three\n\nplain\n")
        #expect(toggle(text, line: 0) == nil)
        #expect(toggle(text, line: 6) == nil)
    }

    @Test func aStaleLineNumberIsRefusedNotAppliedToTheWrongLine() {
        // The preview was drawn from "- [ ] a / - [ ] b"; since then a line was added above, so line 1 is now plain text.
        let now = "intro\n- [ ] a\n- [ ] b"
        #expect(toggle(now, line: 0) == nil)
    }

    @Test func rangesOutsideTheTextAreRefused() {
        let text = "- [ ] a" as NSString
        #expect(EditTransforms.toggleTask(in: text, lineRange: NSRange(location: 3, length: 50), selection: NSRange(location: 0, length: 0)) == nil)
        #expect(EditTransforms.toggleTask(in: text, lineRange: NSRange(location: NSNotFound, length: 0), selection: NSRange(location: 0, length: 0)) == nil)
    }

    @Test func worksWithNonASCIIAndLongLines() throws {
        let line = "- [ ] 日本語 😀 " + String(repeating: "x", count: 10_000)
        let edit = try #require(toggle(line))
        #expect(edit.applied(to: line).hasPrefix("- [x] 日本語"))
        #expect(edit.range == NSRange(location: 3, length: 1))
    }
}
