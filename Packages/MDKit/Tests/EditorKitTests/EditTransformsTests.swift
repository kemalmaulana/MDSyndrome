import Foundation
import Testing
@testable import EditorKit

/// Text with a caret `‸` or a selection `«…»`.
private func parse(_ marked: String) -> (NSString, NSRange) {
    let ns = marked as NSString
    let caret = ns.range(of: "‸")
    if caret.location != NSNotFound {
        return (ns.replacingCharacters(in: caret, with: "") as NSString, NSRange(location: caret.location, length: 0))
    }
    let open = ns.range(of: "«"), close = ns.range(of: "»")
    precondition(open.location != NSNotFound && close.location != NSNotFound, "marker missing in \(marked)")
    let text = ns.replacingCharacters(in: close, with: "").replacingOccurrences(of: "«", with: "")
    return (text as NSString, NSRange(location: open.location, length: close.location - open.location - 1))
}

private func render(_ text: String, _ selection: NSRange) -> String {
    let ns = text as NSString
    if selection.length == 0 { return ns.replacingCharacters(in: selection, with: "‸") }
    return ns.replacingCharacters(in: selection, with: "«" + ns.substring(with: selection) + "»")
}

private func run(_ marked: String, _ op: (NSString, NSRange) -> TextEdit?) -> String? {
    let (text, selection) = parse(marked)
    guard let edit = op(text, selection) else { return nil }
    return render(edit.applied(to: text as String), edit.selection)
}

@Suite struct NewlineTests {
    @Test(arguments: [
        ("- a‸", "- a\n- ‸"),
        ("* a‸", "* a\n* ‸"),
        ("  + a‸", "  + a\n  + ‸"),
        ("1. a‸", "1. a\n2. ‸"),
        ("9) a‸", "9) a\n10) ‸"),
        ("- [x] done‸", "- [x] done\n- [ ] ‸"),
        ("> quote‸", "> quote\n> ‸"),
        ("> > nested‸", "> > nested\n> > ‸"),
        ("- split‸here", "- split\n- ‸here"),
    ])
    func continuesListsAndQuotes(input: String, expected: String) {
        #expect(run(input) { EditTransforms.newline(in: $0, selection: $1) } == expected)
    }

    @Test(arguments: [("- ‸", "‸"), ("1. ‸", "‸"), ("- [ ] ‸", "‸"), ("> ‸", "‸"), ("text\n- ‸", "text\n‸")])
    func emptyItemEndsTheList(input: String, expected: String) {
        #expect(run(input) { EditTransforms.newline(in: $0, selection: $1) } == expected)
    }

    @Test func plainLinesUseTheDefaultNewline() {
        #expect(run("plain‸") { EditTransforms.newline(in: $0, selection: $1) } == nil)
        #expect(run("«- a»") { EditTransforms.newline(in: $0, selection: $1) } == nil)
    }

    @Test func renumbersFollowingItems() {
        #expect(run("1. a‸\n2. b\n3. c\n\nafter") { EditTransforms.newline(in: $0, selection: $1) } == "1. a\n2. ‸\n3. b\n4. c\n\nafter")
        #expect(run("1. a‸\n2. b") { EditTransforms.newline(in: $0, selection: $1, renumber: false) } == "1. a\n2. ‸\n2. b")
    }
}

@Suite struct IndentTests {
    @Test func tabOnAListLineIndentsTheItem() {
        #expect(run("- a‸") { EditTransforms.indent(in: $0, selection: $1, unit: "    ") } == "    - a‸")
    }

    @Test func tabElsewhereInsertsTheUnit() {
        #expect(run("ab‸c") { EditTransforms.indent(in: $0, selection: $1, unit: "    ") } == "ab    ‸c")
    }

    @Test func indentsEverySelectedLine() {
        #expect(run("«one\ntwo»\nthree") { EditTransforms.indent(in: $0, selection: $1, unit: "  ") } == "«  one\n  two»\nthree")
    }

    @Test func theIndentCommandIndentsTheLineEvenWithoutASelection() {
        #expect(run("ab‸c") { EditTransforms.indent(in: $0, selection: $1, unit: "    ", wholeLines: true) } == "    ab‸c")
    }

    @Test func outdentRemovesOneUnitOrTab() {
        #expect(run("    - a‸") { EditTransforms.outdent(in: $0, selection: $1, unit: "    ") } == "- a‸")
        #expect(run("\t- a‸") { EditTransforms.outdent(in: $0, selection: $1, unit: "    ") } == "- a‸")
        #expect(run("«      x\n  y»") { EditTransforms.outdent(in: $0, selection: $1, unit: "    ") } == "«  x\ny»")
        #expect(run("flush‸") { EditTransforms.outdent(in: $0, selection: $1, unit: "    ") } == nil)
    }
}

@Suite struct AutoPairTests {
    @Test(arguments: [
        ("(", "‸", "(‸)"), ("[", "x ‸", "x [‸]"), ("\"", "say ‸", "say \"‸\""), ("`", "‸", "`‸`"),
    ])
    func insertsThePair(typed: String, input: String, expected: String) {
        #expect(run(input) { EditTransforms.typed(typed, in: $0, selection: $1) } == expected)
    }

    @Test func typesOverTheCloser() {
        #expect(run("(a‸)") { EditTransforms.typed(")", in: $0, selection: $1) } == "(a)‸")
    }

    @Test func wrapsTheSelection() {
        #expect(run("«word»") { EditTransforms.typed("(", in: $0, selection: $1) } == "(«word»)")
    }

    @Test func noPairInsideWordsOrApostrophes() {
        #expect(run("don‸") { EditTransforms.typed("'", in: $0, selection: $1) } == nil)
        #expect(run("‸word") { EditTransforms.typed("(", in: $0, selection: $1) } == nil)
        #expect(run("‸") { EditTransforms.typed("a", in: $0, selection: $1) } == nil)
    }

    @Test func backspaceDeletesAnEmptyPair() {
        #expect(run("(‸)") { EditTransforms.deleteBackward(in: $0, selection: $1) } == "‸")
        #expect(run("(x‸)") { EditTransforms.deleteBackward(in: $0, selection: $1) } == nil)
    }
}

@Suite struct FormatTransformTests {
    @Test(arguments: [
        ("**", "«word»", "**«word»**"),
        ("**", "**«word»**", "«word»"),
        ("**", "«**word**»", "«word»"),
        ("*", "a wo‸rd b", "a *«word»* b"),
        ("`", "‸", "`‸`"),
        ("~~", "«gone»", "~~«gone»~~"),
        ("==", "«mark»", "==«mark»=="),
        // Italic and bold share the star, so each leaves the other alone.
        ("*", "**«word»**", "***«word»***"),
        ("**", "*«word»*", "***«word»***"),
        ("**", "***«word»***", "*«word»*"),
        ("*", "***«word»***", "**«word»**"),
        ("*", "*«word»*", "«word»"),
        ("*", "«*word*»", "«word»"),
        ("**", "**‸**", "‸"),
        ("**", "* «item»", "* **«item»**"),
        ("**", "a ‸ b", "a **‸** b"),
    ])
    func toggleWrap(marker: String, input: String, expected: String) {
        #expect(run(input) { EditTransforms.toggleWrap(marker, in: $0, selection: $1) } == expected)
    }

    @Test func links() {
        #expect(run("«MDSyndrome»") { EditTransforms.insertLink(image: false, in: $0, selection: $1) } == "[MDSyndrome](«url»)")
        #expect(run("«logo»") { EditTransforms.insertLink(image: true, in: $0, selection: $1) } == "![logo](«url»)")
        #expect(run("«https://x.com»") { EditTransforms.insertLink(image: false, in: $0, selection: $1) } == "[‸](https://x.com)")
    }

    @Test func headings() {
        #expect(run("Title‸") { EditTransforms.setHeading(level: 2, in: $0, selection: $1) } == "## Title‸")
        #expect(run("# Title‸") { EditTransforms.setHeading(level: 3, in: $0, selection: $1) } == "### Title‸")
        #expect(run("## Title‸") { EditTransforms.setHeading(level: 2, in: $0, selection: $1) } == "Title‸")
    }

    @Test func linePrefixes() {
        #expect(run("«a\nb»") { EditTransforms.toggleLinePrefix(.bullet, in: $0, selection: $1) } == "«- a\n- b»")
        #expect(run("«- a\n- b»") { EditTransforms.toggleLinePrefix(.bullet, in: $0, selection: $1) } == "«a\nb»")
        #expect(run("«a\nb»") { EditTransforms.toggleLinePrefix(.numbered, in: $0, selection: $1) } == "«1. a\n2. b»")
        #expect(run("«- a\n- b»") { EditTransforms.toggleLinePrefix(.task, in: $0, selection: $1) } == "«- [ ] a\n- [ ] b»")
        #expect(run("quote‸") { EditTransforms.toggleLinePrefix(.blockquote, in: $0, selection: $1) } == "> quote‸")
        #expect(run("> quote‸") { EditTransforms.toggleLinePrefix(.blockquote, in: $0, selection: $1) } == "quote‸")
    }

    @Test func codeBlocks() {
        #expect(run("‸") { EditTransforms.codeBlock(in: $0, selection: $1) } == "```\n‸\n```")
        #expect(run("«let x = 1»") { EditTransforms.codeBlock(in: $0, selection: $1) } == "```\n«let x = 1»\n```")
    }

    @Test func emojiAndCJKKeepUTF16Ranges() {
        #expect(run("«日本😀»") { EditTransforms.toggleWrap("**", in: $0, selection: $1) } == "**«日本😀»**")
        #expect(run("- 😀 item‸") { EditTransforms.newline(in: $0, selection: $1) } == "- 😀 item\n- ‸")
    }
}
