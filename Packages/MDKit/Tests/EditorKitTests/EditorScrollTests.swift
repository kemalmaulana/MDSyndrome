import AppKit
import SwiftUI
import Testing
@testable import EditorKit

private final class TextBox: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
}

/// The real editor stack in an off-screen window: scroll view, text view, coordinator, highlighter, controller.
@MainActor
private final class ScrollHarness {
    let box: TextBox
    let controller = EditorController()
    let coordinator: EditorCoordinator
    let scrollView: NSScrollView
    let textView: MarkdownTextView
    let window: NSWindow
    var reported: [Int] = []
    let lineCount: Int
    /// Each editor gets a place of its own off-screen: windows stacked on top of each other count as covered, and
    /// AppKit lays a covered window out lazily.
    private static var nextSlot = 0

    init(_ text: String) async {
        _ = NSApplication.shared
        Self.nextSlot += 1
        let y = -20_000 - Double(Self.nextSlot % 50) * 800
        box = TextBox(text)
        coordinator = EditorCoordinator(text: Binding(get: { [box] in box.value }, set: { [box] in box.value = $0 }))
        (scrollView, textView) = MarkdownEditorView.makeViews()
        window = NSWindow(contentRect: NSRect(x: -20000, y: y, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scrollView
        coordinator.attach(to: textView, scrollView: scrollView, theme: .tomorrowPlus, configuration: .macDownDefaults, controller: controller)
        coordinator.setText(text)
        window.orderFrontRegardless()
        lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        controller.onScroll = { [unowned self] line in reported.append(line) }
        await wait(500)
    }

    func close() { window.orderOut(nil) }

    func wait(_ milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

    /// The user (not our own jump) moves the clip view.
    func userScroll(to y: Double) {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    static func document(bytes: Int) -> String {
        var text = ""
        var n = 0
        while text.utf8.count < bytes {
            n += 1
            text += "## Section \(n)\n\nParagraph one of section \(n). Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.\n\n- [ ] first item of \(n)\n- [x] second item with `code` and **bold**\n\n```swift\nlet value\(n) = \(n)\n```\n\n"
        }
        return text
    }
}

@MainActor
@Suite(.requiresWindowServer, .serialized) struct EditorScrollTests {
    @Test func aFreshEditorIsAtLineOne() async {
        let editor = await ScrollHarness("# Title\n\ntext")
        defer { editor.close() }
        #expect(editor.controller.topLine == 1)
    }

    @Test func aJumpPutsTheLineAtTheTopExactlyAndAtOnce() async {
        let editor = await ScrollHarness(ScrollHarness.document(bytes: 400_000))
        defer { editor.close() }
        var rng = SystemRandomNumberGenerator()
        var wrongNow = 0
        var drift: [Int] = []
        for round in 0..<30 {
            let line = Int.random(in: 6..<(editor.lineCount - 40), using: &rng)
            if round % 4 == 0 {   // sometimes start from a place the user scrolled to
                editor.userScroll(to: Double.random(in: 0..<Double(editor.textView.frame.height - 800), using: &rng))
                await editor.wait(50)
            }
            editor.controller.scroll(toLine: line)
            if editor.controller.topLine != line { wrongNow += 1 }
            await editor.wait(150)
            drift.append(abs((editor.controller.topLine ?? Int.max) - line))
        }
        #expect(wrongNow == 0, "\(wrongNow) of 30 jumps were off at once")
        // TextKit may re-estimate heights once the jump has been drawn and nudge the top line a little. The window
        // that follows scrolls (SyncScrollCoordinator.echoLineTolerance) ignores a move that small right after a jump.
        #expect(drift.allSatisfy { $0 <= 3 }, "lines moved after the jump: \(drift.filter { $0 > 0 })")
    }

    @Test func ourOwnJumpsAreNotReported() async {
        let editor = await ScrollHarness(ScrollHarness.document(bytes: 200_000))
        defer { editor.close() }
        editor.controller.scroll(toLine: 2_000)
        editor.controller.scroll(toLine: 700)
        editor.controller.scroll(toLine: 1)
        await editor.wait(300)
        #expect(editor.reported.isEmpty, "\(editor.reported)")
    }

    @Test func aScrollThatIsNotOursIsReportedOncePerChangeOfTopLine() async {
        let editor = await ScrollHarness(ScrollHarness.document(bytes: 200_000))
        defer { editor.close() }
        editor.userScroll(to: 100_000)
        await editor.wait(250)
        #expect(editor.reported.count == 1)
        #expect(editor.reported.first == editor.controller.topLine)
        editor.userScroll(to: 100_001)   // one pixel: the same line is still at the top
        await editor.wait(250)
        #expect(editor.reported.count == 1)
        editor.userScroll(to: 40_000)
        await editor.wait(250)
        #expect(editor.reported.count == 2)
        #expect((editor.reported.last ?? 0) < (editor.reported.first ?? 0))
    }

    @Test func manyScrollStepsInOneTurnAreReportedOnceWithTheLastLine() async {
        let editor = await ScrollHarness(ScrollHarness.document(bytes: 200_000))
        defer { editor.close() }
        for step in 1...20 { editor.userScroll(to: Double(step) * 3_000) }
        await editor.wait(300)
        #expect(editor.reported.count == 1, "\(editor.reported)")
        #expect(editor.reported.last == editor.controller.topLine)
    }

    @Test func aJumpAfterAUserScrollIsStillSilentAndTheNextUserScrollStillReports() async {
        let editor = await ScrollHarness(ScrollHarness.document(bytes: 200_000))
        defer { editor.close() }
        editor.userScroll(to: 50_000)
        await editor.wait(250)
        editor.controller.scroll(toLine: 3_000)
        await editor.wait(250)
        #expect(editor.reported.count == 1)
        editor.userScroll(to: 20_000)
        await editor.wait(250)
        #expect(editor.reported.count == 2)
    }

    @Test func linesBeyondTheTextAreClampedAndNeverCrash() async {
        let editor = await ScrollHarness(ScrollHarness.document(bytes: 100_000))
        defer { editor.close() }
        editor.controller.scroll(toLine: 10_000_000)
        await editor.wait(150)
        let last = editor.controller.topLine ?? 0
        #expect(last > editor.lineCount - 60, "ended at line \(last) of \(editor.lineCount)")
        editor.controller.scroll(toLine: 0)
        #expect(editor.controller.topLine == 1)
        editor.controller.scroll(toLine: -50)
        #expect(editor.controller.topLine == 1)
    }

    @Test func anEmptyEditorIgnoresJumps() async {
        let editor = await ScrollHarness("")
        defer { editor.close() }
        editor.controller.scroll(toLine: 40)
        editor.controller.scroll(toLine: 1)
        #expect(editor.scrollView.contentView.bounds.minY == 0)
        #expect(editor.controller.topLine == nil || editor.controller.topLine == 1, "there is no line to be at the top of")
    }

    @Test func aHiddenEditorHasNoTopLineAndDoesNotScroll() async {
        let editor = await ScrollHarness(ScrollHarness.document(bytes: 100_000))
        defer { editor.close() }
        editor.controller.scroll(toLine: 800)
        let before = editor.scrollView.contentView.bounds.minY
        editor.scrollView.isHidden = true
        #expect(editor.controller.topLine == nil)
        editor.controller.scroll(toLine: 2)
        #expect(editor.scrollView.contentView.bounds.minY == before)
        editor.scrollView.isHidden = false
        await editor.wait(100)
        #expect(editor.controller.topLine != nil)
    }

    @Test func aJumpOnAMegabyteIsQuick() async {
        let editor = await ScrollHarness(ScrollHarness.document(bytes: 1_000_000))
        defer { editor.close() }
        var rng = SystemRandomNumberGenerator()
        let clock = ContinuousClock()
        var worst = Duration.zero
        for _ in 0..<12 {
            let line = Int.random(in: 6..<(editor.lineCount - 40), using: &rng)
            let elapsed = clock.measure { editor.controller.scroll(toLine: line) }
            worst = max(worst, elapsed)
            #expect(editor.controller.topLine == line)
        }
        #expect(worst < .budget(0.1), "the slowest jump took \(worst)")
        let reading = clock.measure { for _ in 0..<100 { _ = editor.controller.topLine } }
        #expect(reading < .budget(0.1), "100 reads of the top line took \(reading)")
    }
}

@MainActor
@Suite(.requiresWindowServer) struct EditorToggleTaskTests {
    private let text = "# Tasks\n\n- [ ] one\n- [x] two\n  - [ ] nested\n\nplain line\n"

    @Test func togglesTheItemInTheDocumentAsOneUndoableEdit() async throws {
        let editor = await ScrollHarness(text)
        defer { editor.close() }
        #expect(editor.controller.toggleTask(atLine: 3))
        #expect(editor.textView.string.hasPrefix("# Tasks\n\n- [x] one\n"))
        #expect(editor.box.value == editor.textView.string, "the document binding follows")
        editor.textView.undoManager?.undo()
        #expect(editor.textView.string == text)
        editor.textView.undoManager?.redo()
        #expect(editor.textView.string.hasPrefix("# Tasks\n\n- [x] one\n"))
    }

    @Test func refusesALineThatIsNotATask() async {
        let editor = await ScrollHarness(text)
        defer { editor.close() }
        #expect(!editor.controller.toggleTask(atLine: 1))
        #expect(!editor.controller.toggleTask(atLine: 7))
        #expect(!editor.controller.toggleTask(atLine: 0))
        #expect(!editor.controller.toggleTask(atLine: 99))
        #expect(editor.textView.string == text)
    }

    @Test func leavesTheSelectionAndTheScrollPositionAlone() async {
        let editor = await ScrollHarness(text)
        defer { editor.close() }
        editor.textView.setSelectedRange(NSRange(location: 12, length: 2))
        #expect(editor.controller.toggleTask(atLine: 5))
        #expect(editor.textView.selectedRange() == NSRange(location: 12, length: 2))
    }

    @Test func worksWhileTheEditorIsHidden() async {
        let editor = await ScrollHarness(text)
        defer { editor.close() }
        editor.scrollView.isHidden = true
        #expect(editor.controller.toggleTask(atLine: 4))
        #expect(editor.textView.string.contains("- [ ] two"))
    }

    @Test func aStaleLineIsRefusedAfterTheTextMoved() async {
        let editor = await ScrollHarness(text)
        defer { editor.close() }
        editor.textView.insertText("new first line\n", replacementRange: NSRange(location: 0, length: 0))
        // the preview still thinks "- [ ] one" is on line 3; it is on line 4 now and line 3 is blank
        #expect(!editor.controller.toggleTask(atLine: 2))
        #expect(editor.controller.toggleTask(atLine: 4))
    }
}

@MainActor
@Suite(.requiresWindowServer, .serialized) struct EditorOptionTests {
    @Test func wrappingAndSpellCheckFollowTheConfiguration() async {
        let editor = await ScrollHarness("a very long line " + String(repeating: "word ", count: 400))
        defer { editor.close() }
        #expect(editor.textView.textContainer?.widthTracksTextView == true)
        #expect(!editor.textView.isContinuousSpellCheckingEnabled)
        var configuration = EditorConfiguration.macDownDefaults
        configuration.softWrap = false
        configuration.spellCheck = true
        editor.coordinator.apply(theme: .tomorrowPlus, configuration: configuration)
        #expect(editor.textView.textContainer?.widthTracksTextView == false)
        #expect(editor.scrollView.hasHorizontalScroller)
        #expect(editor.textView.isContinuousSpellCheckingEnabled)
        configuration.softWrap = true
        configuration.spellCheck = false
        editor.coordinator.apply(theme: .tomorrowPlus, configuration: configuration)
        #expect(editor.textView.textContainer?.widthTracksTextView == true)
        #expect(!editor.scrollView.hasHorizontalScroller)
        #expect(!editor.textView.isContinuousSpellCheckingEnabled)
    }
}
