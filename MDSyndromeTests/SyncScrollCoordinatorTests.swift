import Foundation
import MarkdownCore
import Testing
@testable import MDSyndrome

@MainActor
private final class ManualClock {
    var now = ContinuousClock.now
    func advance(_ duration: Duration) { now = now.advanced(by: duration) }
}

/// An editor that lands exactly where it is told and, like the real one, does not report its own scrolls.
@MainActor
private final class FakeEditor: EditorScrolling {
    var topLine: Int?
    var scrolls: [Int] = []
    var onScroll: ((Int) -> Void)?
    init(topLine: Int? = 1) { self.topLine = topLine }
    func scroll(toLine line: Int) {
        scrolls.append(line)
        topLine = line
    }
    func userScrolls(to line: Int) {
        topLine = line
        onScroll?(line)
    }
}

@MainActor
private final class FakePreview: PreviewScrolling {
    var jumps: [BlockID] = []
    var topScrolls = 0
    var onUserScroll: ((BlockID) -> Void)?
    func scroll(to id: BlockID) { jumps.append(id) }
    func scrollToTop() { topScrolls += 1 }
    func userScrolls(to id: BlockID) { onUserScroll?(id) }
}

/// Twelve paragraphs: block i starts on line 2i + 1 (1, 3, 5, …, 23); the even lines are blank.
@MainActor
private struct Rig {
    let blocks = MarkdownParser.parse((0..<12).map { "paragraph \($0)" }.joined(separator: "\n\n")).blocks
    let map: SourceMap
    let clock = ManualClock()
    let editor = FakeEditor()
    let preview = FakePreview()
    let coordinator: SyncScrollCoordinator
    var positions: [Int] = []

    init() {
        map = SourceMap(blocks: blocks)
        let clock = clock
        coordinator = SyncScrollCoordinator(clock: { clock.now }, afterLayout: { $0() })
        coordinator.attach(editor: editor, preview: preview)
        coordinator.renderDidChange(map)
    }

    func id(_ block: Int) -> BlockID { blocks[block].id }
    func line(_ block: Int) -> Int { 2 * block + 1 }
}

@MainActor
@Suite struct SyncScrollCoordinatorTests {
    @Test func theEditorLeadsAndThePreviewFollowsToTheBlockAtThatLine() {
        let rig = Rig()
        rig.editor.userScrolls(to: 7)    // paragraph 3
        rig.editor.userScrolls(to: 10)   // the blank line after paragraph 4 belongs to paragraph 4
        #expect(rig.preview.jumps == [rig.id(3), rig.id(4)])
        #expect(rig.coordinator.driver == .editor)
        #expect(rig.editor.scrolls.isEmpty, "the pane being followed is never moved back")
    }

    @Test func thePreviewLeadsAndTheEditorFollowsToTheBlocksFirstLine() {
        let rig = Rig()
        rig.preview.userScrolls(to: rig.id(4))
        rig.preview.userScrolls(to: rig.id(9))
        #expect(rig.editor.scrolls == [9, 19])
        #expect(rig.coordinator.driver == .preview)
        #expect(rig.preview.jumps.isEmpty)
    }

    @Test func aBlockThePreviewIsAlreadyOnIsNotJumpedToAgain() {
        let rig = Rig()
        rig.editor.userScrolls(to: 5)
        rig.editor.userScrolls(to: 6)   // still paragraph 2
        rig.editor.userScrolls(to: 5)
        #expect(rig.preview.jumps == [rig.id(2)])
    }

    @Test func eachUserScrollCausesAtMostOneScrollInTheOtherPane() {
        let rig = Rig()
        for step in 0..<20 {
            rig.clock.advance(.milliseconds(600))
            if step.isMultiple(of: 2) { rig.editor.userScrolls(to: 1 + 2 * ((step * 5) % 12)) } else { rig.preview.userScrolls(to: rig.id((step * 7) % 12)) }
        }
        #expect(rig.preview.jumps.count + rig.editor.scrolls.count <= 20)
    }

    @Test func theTopOfTheEditorShowsTheTopOfThePreviewMarginIncluded() {
        let rig = Rig()
        #expect(rig.preview.topScrolls == 1, "the first render puts the preview at the top, where the editor is")
        rig.editor.userScrolls(to: 9)
        rig.editor.userScrolls(to: 1)
        #expect(rig.preview.topScrolls == 2)
        #expect(rig.preview.jumps == [rig.id(4)], "block 0 is never jumped to: that would hide the margin above it")
        rig.editor.userScrolls(to: 2)   // the blank line under the first block still belongs to it, but is below its first line
        #expect(rig.preview.jumps == [rig.id(4), rig.id(0)])
    }

    @Test func aDocumentThatStartsWithBlankLinesTreatsThemAsTheTop() {
        let blocks = MarkdownParser.parse("\n\nfirst\n\nsecond").blocks   // first starts on line 3
        let coordinator = SyncScrollCoordinator(afterLayout: { $0() })
        let editor = FakeEditor(topLine: 1)
        let preview = FakePreview()
        coordinator.attach(editor: editor, preview: preview)
        coordinator.renderDidChange(SourceMap(blocks: blocks))
        editor.userScrolls(to: 2)
        editor.userScrolls(to: 3)
        #expect(preview.topScrolls >= 1)
        #expect(preview.jumps.isEmpty, "line 3 is where the first block starts: the top of the preview, not a jump to the block")
        editor.userScrolls(to: 4)
        #expect(preview.jumps == [blocks[0].id], "below its first line the block is jumped to")
    }

    // MARK: Echoes

    @Test func theEditorSettlingNextToOurJumpIsAnEchoNotTheUser() {
        let rig = Rig()
        rig.preview.userScrolls(to: rig.id(5))          // the editor jumps to line 11
        #expect(rig.editor.scrolls == [11])
        rig.clock.advance(.milliseconds(100))
        rig.editor.onScroll?(13)                        // TextKit re-estimated: the top line moved by two
        #expect(rig.preview.jumps.isEmpty)
        #expect(rig.coordinator.driver == .preview)
    }

    @Test func aMoveFarFromOurJumpIsTheUserEvenRightAfterwards() {
        let rig = Rig()
        rig.preview.userScrolls(to: rig.id(5))
        rig.editor.userScrolls(to: 3)
        #expect(rig.preview.jumps == [rig.id(1)])
        #expect(rig.coordinator.driver == .editor)
    }

    @Test func anEchoIsOnlyAnEchoForAShortWhile() {
        let rig = Rig()
        rig.preview.userScrolls(to: rig.id(5))
        rig.clock.advance(SyncScrollCoordinator.echoWindow + .milliseconds(1))
        rig.editor.userScrolls(to: 13)
        #expect(rig.preview.jumps == [rig.id(6)])
    }

    @Test func thePreviewReportingOurJumpIsAnEchoNotTheUser() {
        let rig = Rig()
        rig.editor.userScrolls(to: 9)                   // the preview jumps to paragraph 4
        rig.clock.advance(.milliseconds(100))
        rig.preview.onUserScroll?(rig.id(4))            // another OS may report a jump as a scroll
        #expect(rig.editor.scrolls.isEmpty)
        #expect(rig.coordinator.driver == .editor)
        rig.preview.userScrolls(to: rig.id(8))          // a different block is the user
        #expect(rig.editor.scrolls == [17])
    }

    @Test func aPreviewReportOfTheSameBlockAfterTheWindowIsTheUser() {
        let rig = Rig()
        rig.editor.userScrolls(to: 9)
        rig.clock.advance(SyncScrollCoordinator.echoWindow + .milliseconds(1))
        rig.editor.topLine = 15            // the editor is somewhere else by now
        rig.preview.userScrolls(to: rig.id(4))
        #expect(rig.editor.scrolls == [9])
    }

    // MARK: Switching it off, hidden panes, renders

    @Test func nothingFollowsWhileItIsOff() {
        let rig = Rig()
        rig.coordinator.isEnabled = false
        rig.editor.userScrolls(to: 9)
        rig.preview.userScrolls(to: rig.id(8))
        #expect(rig.preview.jumps.isEmpty && rig.editor.scrolls.isEmpty)
    }

    @Test func turningItOnBringsThePreviewToTheEditor() {
        let rig = Rig()
        rig.coordinator.isEnabled = false
        rig.editor.userScrolls(to: 15)
        rig.coordinator.isEnabled = true
        #expect(rig.preview.jumps == [rig.id(7)])
    }

    @Test func turningItOnAfterThePreviewLedBringsTheEditorToThePreview() {
        let rig = Rig()
        rig.coordinator.isEnabled = false
        rig.preview.userScrolls(to: rig.id(6))
        rig.coordinator.isEnabled = true
        #expect(rig.editor.scrolls == [13])
    }

    @Test func aHiddenPaneIsNeverScrolled() {
        let rig = Rig()
        rig.coordinator.layoutDidChange(editorVisible: true, previewVisible: false)
        rig.editor.userScrolls(to: 9)
        #expect(rig.preview.jumps.isEmpty)
        rig.coordinator.layoutDidChange(editorVisible: false, previewVisible: true)
        rig.preview.userScrolls(to: rig.id(3))
        #expect(rig.editor.scrolls.isEmpty)
    }

    @Test func aPaneThatShowsAgainCatchesUpFromTheOneThatLed() {
        let rig = Rig()
        rig.coordinator.layoutDidChange(editorVisible: true, previewVisible: false)   // Editor only
        rig.editor.userScrolls(to: 15)
        rig.coordinator.layoutDidChange(editorVisible: true, previewVisible: true)    // Split
        #expect(rig.preview.jumps == [rig.id(7)])

        let other = Rig()
        other.coordinator.layoutDidChange(editorVisible: false, previewVisible: true) // Preview only
        other.preview.userScrolls(to: other.id(9))
        other.coordinator.layoutDidChange(editorVisible: true, previewVisible: true)
        #expect(other.editor.scrolls == [19])
    }

    @Test func aRenderPutsThePreviewBackOnTheEditorsLineWhileTheEditorLeads() {
        let rig = Rig()
        rig.editor.userScrolls(to: 9)
        #expect(rig.preview.jumps == [rig.id(4)])
        // an edit made new blocks (new ids) for the same lines
        let edited = MarkdownParser.parse((0..<12).map { "changed \($0)" }.joined(separator: "\n\n")).blocks
        rig.coordinator.renderDidChange(SourceMap(blocks: edited))
        #expect(rig.preview.jumps.last == edited[4].id)
        #expect(rig.preview.jumps.count == 2)
    }

    @Test func aRenderLeavesThePreviewAloneWhileThePreviewLeads() {
        let rig = Rig()
        rig.preview.userScrolls(to: rig.id(6))
        let edited = MarkdownParser.parse((0..<12).map { "changed \($0)" }.joined(separator: "\n\n")).blocks
        rig.coordinator.renderDidChange(SourceMap(blocks: edited))
        #expect(rig.preview.jumps.isEmpty)
    }

    @Test func clickingInTheEditorMakesItTheLeaderAgain() {
        let rig = Rig()
        rig.preview.userScrolls(to: rig.id(6))
        rig.coordinator.editorActivity()
        #expect(rig.coordinator.driver == .editor)
        let edited = MarkdownParser.parse((0..<12).map { "changed \($0)" }.joined(separator: "\n\n")).blocks
        rig.editor.topLine = 13
        rig.coordinator.renderDidChange(SourceMap(blocks: edited))
        #expect(rig.preview.jumps == [edited[6].id])
    }

    // MARK: Navigation

    @Test func navigatingScrollsBothPanesAndTheirEchoesAreIgnored() {
        let rig = Rig()
        rig.coordinator.navigate(to: rig.id(8))
        #expect(rig.preview.jumps == [rig.id(8)])
        #expect(rig.editor.scrolls == [17])
        #expect(rig.coordinator.driver == .none)
        rig.editor.onScroll?(18)
        rig.preview.onUserScroll?(rig.id(8))
        #expect(rig.preview.jumps.count == 1 && rig.editor.scrolls.count == 1)
    }

    @Test func aNavigationThePreviewStartedOnlyMovesTheEditor() {
        let rig = Rig()
        rig.coordinator.previewDidNavigate(to: rig.id(5))   // an anchor or a search match: the preview has scrolled itself
        #expect(rig.preview.jumps.isEmpty, "the preview keeps the way it placed the block, a centred search match for one")
        #expect(rig.editor.scrolls == [11])
        #expect(rig.coordinator.driver == .none)
        rig.editor.onScroll?(12)
        rig.preview.onUserScroll?(rig.id(5))
        #expect(rig.preview.jumps.isEmpty && rig.editor.scrolls.count == 1, "the echoes start nothing")
    }

    @Test func aNavigationThePreviewStartedReachesTheEditorEvenWhileFollowingIsOff() {
        let rig = Rig()
        rig.coordinator.isEnabled = false
        rig.coordinator.previewDidNavigate(to: rig.id(2))
        #expect(rig.editor.scrolls == [5])
        let hidden = Rig()
        hidden.coordinator.layoutDidChange(editorVisible: false, previewVisible: true)
        hidden.coordinator.previewDidNavigate(to: hidden.id(2))
        #expect(hidden.editor.scrolls.isEmpty)
        hidden.coordinator.layoutDidChange(editorVisible: true, previewVisible: true)
        #expect(hidden.editor.scrolls == [5], "a hidden editor catches up when it shows, the preview having led")
        #expect(hidden.preview.jumps.isEmpty, "and the preview is not pulled back to where the editor was")
    }

    @Test func navigatingWhileOnePaneIsHiddenLetsThePaneThatMovedLead() {
        let previewOnly = Rig()
        previewOnly.coordinator.layoutDidChange(editorVisible: false, previewVisible: true)
        previewOnly.coordinator.navigate(to: previewOnly.id(6))
        #expect(previewOnly.coordinator.driver == .preview)
        previewOnly.coordinator.layoutDidChange(editorVisible: true, previewVisible: true)
        #expect(previewOnly.editor.scrolls == [13])
        #expect(previewOnly.preview.jumps == [previewOnly.id(6)], "only the navigation itself, no pull back")

        let editorOnly = Rig()
        editorOnly.coordinator.layoutDidChange(editorVisible: true, previewVisible: false)
        editorOnly.coordinator.navigate(to: editorOnly.id(6))
        #expect(editorOnly.coordinator.driver == .editor)
        editorOnly.coordinator.layoutDidChange(editorVisible: true, previewVisible: true)
        #expect(editorOnly.preview.jumps == [editorOnly.id(6)])
    }

    @Test func navigatingWorksWhileFollowingIsOff() {
        let rig = Rig()
        rig.coordinator.isEnabled = false
        rig.coordinator.navigate(to: rig.id(2))
        #expect(rig.preview.jumps == [rig.id(2)])
        #expect(rig.editor.scrolls == [5])
    }

    @Test func navigatingSkipsAHiddenPane() {
        let rig = Rig()
        rig.coordinator.layoutDidChange(editorVisible: true, previewVisible: false)
        rig.coordinator.navigate(to: rig.id(3))
        #expect(rig.preview.jumps.isEmpty)
        #expect(rig.editor.scrolls == [7])
    }

    @Test func theWindowIsToldWhereTheDocumentIsEvenWhileFollowingIsOff() {
        let rig = Rig()
        var seen: [Int] = []
        rig.coordinator.onPosition = { seen.append($0) }
        rig.coordinator.isEnabled = false
        rig.editor.userScrolls(to: 9)
        rig.preview.userScrolls(to: rig.id(8))
        rig.coordinator.navigate(to: rig.id(2))
        #expect(seen == [9, 17, 5])
    }

    // MARK: Nothing to do

    @Test func aDocumentWithoutBlocksIsLeftAlone() {
        let editor = FakeEditor()
        let preview = FakePreview()
        let coordinator = SyncScrollCoordinator(afterLayout: { $0() })
        coordinator.attach(editor: editor, preview: preview)
        coordinator.renderDidChange(SourceMap.empty)
        editor.userScrolls(to: 40)
        preview.userScrolls(to: BlockID(1))
        coordinator.navigate(to: BlockID(2))
        coordinator.layoutDidChange(editorVisible: false, previewVisible: true)
        coordinator.layoutDidChange(editorVisible: true, previewVisible: true)
        #expect(preview.jumps == [BlockID(2)] && editor.scrolls.isEmpty, "only the explicit navigation reaches the preview, and the editor has no line for it")
    }

    @Test func anEditorThatDoesNotKnowItsTopLineIsScrolledAnyway() {
        let rig = Rig()
        rig.editor.topLine = nil
        rig.preview.userScrolls(to: rig.id(3))
        #expect(rig.editor.scrolls == [7])
        let other = Rig()
        other.editor.topLine = nil
        other.coordinator.isEnabled = false
        other.coordinator.isEnabled = true   // catching up needs the editor's line, which it cannot tell
        #expect(other.preview.jumps.isEmpty)
    }
}
