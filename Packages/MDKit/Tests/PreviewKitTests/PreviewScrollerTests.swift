import AppKit
import MarkdownCore
import SwiftUI
import Testing
@testable import PreviewKit

@MainActor
@Suite struct PreviewScrollerLogicTests {
    private let blocks = MarkdownParser.parse("# A\n\nb\n\nc\n\nd\n").blocks

    private func scroller() -> (PreviewScroller, Reports) {
        let scroller = PreviewScroller()
        let reports = Reports()
        scroller.blocksChanged(blocks)
        scroller.onUserScroll = { reports.ids.append($0) }
        scroller.jump = { id, anchor in reports.jumps.append((id, anchor)) }
        return (scroller, reports)
    }

    final class Reports {
        var ids: [BlockID] = []
        var jumps: [(BlockID, UnitPoint)] = []
    }

    @Test func theTopBlockIsTheFirstVisibleOneInDocumentOrder() {
        let (scroller, _) = scroller()
        scroller.visibleBlocksChanged([blocks[2].id, blocks[0].id, blocks[1].id])
        #expect(scroller.topBlock == blocks[0].id)
        scroller.visibleBlocksChanged([blocks[3].id, blocks[2].id])
        #expect(scroller.topBlock == blocks[2].id)
    }

    @Test func anEmptyReportKeepsTheLastTopBlock() {
        let (scroller, _) = scroller()
        scroller.visibleBlocksChanged([blocks[1].id])
        scroller.visibleBlocksChanged([])
        #expect(scroller.topBlock == blocks[1].id)
    }

    @Test func aJumpToTheTopSaysWhereTheTopIs() {
        let (scroller, reports) = scroller()
        scroller.scroll(to: blocks[2].id)
        #expect(reports.jumps.map(\.0) == [blocks[2].id])
        #expect(reports.jumps.first?.1 == .top)
        #expect(scroller.topBlock == blocks[2].id, "the visibility callback can lag or report nothing right after a jump")
        scroller.scroll(to: blocks[3].id, anchor: .center)
        #expect(reports.jumps.last?.1 == .center)
        #expect(scroller.topBlock == blocks[2].id, "a centred jump does not say what is at the top")
    }

    @Test func jumpsAreNotReportedAsUserScrolls() {
        let (scroller, reports) = scroller()
        scroller.scroll(to: blocks[2].id)
        scroller.visibleBlocksChanged([blocks[2].id, blocks[3].id])
        scroller.phaseChanged(.idle)
        #expect(reports.ids.isEmpty)
        #expect(!scroller.isUserScrolling)
    }

    @Test func aUserScrollIsReportedBlockByBlockAndOnlyOnChange() {
        let (scroller, reports) = scroller()
        scroller.phaseChanged(.interacting)
        #expect(scroller.isUserScrolling)
        scroller.visibleBlocksChanged([blocks[1].id])
        scroller.visibleBlocksChanged([blocks[1].id, blocks[2].id])
        scroller.visibleBlocksChanged([blocks[2].id])
        scroller.phaseChanged(.decelerating)
        scroller.visibleBlocksChanged([blocks[3].id])
        scroller.phaseChanged(.idle)
        #expect(reports.ids == [blocks[1].id, blocks[2].id, blocks[3].id])
        #expect(!scroller.isUserScrolling)
        scroller.visibleBlocksChanged([blocks[0].id])
        #expect(reports.ids.count == 3, "nothing is reported once the user has stopped")
    }

    @Test func aNewGestureReportsAgainEvenWhereTheLastOneStopped() {
        let (scroller, reports) = scroller()
        scroller.phaseChanged(.interacting)
        scroller.visibleBlocksChanged([blocks[1].id])
        scroller.phaseChanged(.idle)
        scroller.phaseChanged(.interacting)
        scroller.visibleBlocksChanged([blocks[1].id])
        scroller.phaseChanged(.idle)
        #expect(reports.ids == [blocks[1].id, blocks[1].id], "the editor may have been moved elsewhere in between")
    }

    @Test func whenTheScrollComesToRestTheTopBlockIsReportedIfItWasNot() {
        let (scroller, reports) = scroller()
        scroller.phaseChanged(.interacting)
        scroller.visibleBlocksChanged([blocks[1].id])
        // the last visibility callback has not arrived, but a jump to the top told us where we are
        scroller.scroll(to: blocks[3].id)
        scroller.phaseChanged(.idle)
        #expect(reports.ids == [blocks[1].id, blocks[3].id])
    }

    @Test func keyboardScrollingCountsAsTheUsers() {
        let (scroller, reports) = scroller()
        scroller.phaseChanged(.animating)
        scroller.visibleBlocksChanged([blocks[2].id])
        #expect(reports.ids == [blocks[2].id])
    }

    @Test func blocksOutsideTheListAreRankedLast() {
        let (scroller, _) = scroller()
        scroller.visibleBlocksChanged([BlockID(999), blocks[1].id])
        #expect(scroller.topBlock == blocks[1].id)
    }
}

// MARK: - In a real (off-screen) window

private func navigationDocument(bytes: Int) -> String {
    var text = ""
    var n = 0
    while text.utf8.count < bytes {
        n += 1
        text += "## Section \(n)\n\nParagraph one of section \(n). Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.\n\n- [ ] first item of \(n)\n- [x] second item with `code` and **bold**\n\n```swift\nlet value\(n) = \(n)\n```\n\n| a | b |\n|---|---|\n| \(n) | x |\n\n"
    }
    return text
}

@MainActor
private func scrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    for sub in view.subviews { if let found = scrollView(in: sub) { return found } }
    return nil
}

@MainActor
private func wait(_ milliseconds: Int) async {
    try? await Task.sleep(for: .milliseconds(milliseconds))
}

/// Waits until the scroll offset has not moved for `quiet` milliseconds (at most `limit`).
@MainActor
private func settledOffset(of scroll: NSScrollView, quiet: Int = 150, limit: Int = 3_000) async -> CGFloat {
    var last = scroll.contentView.bounds.minY
    var still = 0
    var elapsed = 0
    while still < quiet, elapsed < limit {
        await wait(15)
        elapsed += 15
        let now = scroll.contentView.bounds.minY
        if abs(now - last) < 0.5 { still += 15 } else { still = 0; last = now }
    }
    return last
}

@MainActor
private final class PreviewWindow {
    let scroller = PreviewScroller()
    let rendered: RenderedDocument
    let window: NSWindow
    let scroll: NSScrollView

    init(bytes: Int) async throws {
        _ = NSApplication.shared
        rendered = MarkdownPipeline.render(navigationDocument(bytes: bytes), options: .default)
        let host = NSHostingController(rootView: MarkdownPreview(rendered: rendered, baseURL: nil, scroller: scroller))
        window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .resizable]
        window.setFrame(NSRect(x: -20000, y: -21000, width: 900, height: 700), display: false)
        window.orderFrontRegardless()
        await wait(1_200)
        scroll = try #require(scrollView(in: host.view))
    }

    deinit { MainActor.assumeIsolated { window.orderOut(nil) } }

    /// Where a jump really landed. The preview's own "top block" is not asked right after a jump (SwiftUI's
    /// visibility callback can lag or report nothing then, and offsets differ between visits because LazyVStack
    /// re-estimates the heights of blocks it has not drawn), so the user is imitated instead: a short scroll down
    /// makes the visible set change, and the first block of the new set is read from what is reported, which is
    /// reliable while the user scrolls. Returns that block's index.
    func blockAfterNudge() async -> Int? {
        let order = Dictionary(rendered.document.blocks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var reported: BlockID?
        let previous = scroller.onUserScroll
        scroller.onUserScroll = { reported = $0 }
        wheel(-1, phase: .began)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.minY + 120))
        scroll.reflectScrolledClipView(scroll.contentView)
        await wait(150)
        wheel(0, phase: .ended)
        await wait(100)
        scroller.onUserScroll = previous
        return reported.flatMap { order[$0] }
    }

    /// A wheel event in the given scroll phase, fed to the SwiftUI scroll view, which reports it as the user scrolling.
    func wheel(_ delta: Int32, phase: CGScrollPhase) {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { return }
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        if let event = NSEvent(cgEvent: cg) { scroll.scrollWheel(with: event) }
    }
}

@MainActor
@Suite(.requiresWindowServer) struct PreviewScrollerWindowTests {
    @Test func aJumpLandsOnTheBlockAnywhereInTheDocument() async throws {
        let preview = try await PreviewWindow(bytes: 400_000)
        let blocks = preview.rendered.document.blocks
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<12 {
            let target = Int.random(in: 30..<(blocks.count - 60), using: &rng)
            preview.scroller.scroll(to: blocks[target].id)
            _ = await settledOffset(of: preview.scroll)
            let landed = await preview.blockAfterNudge()
            #expect(landed.map { (target...(target + 4)).contains($0) } == true, "jumped to block \(target), found \(String(describing: landed))")
        }
    }

    @Test func theLastOfManyRapidJumpsWins() async throws {
        let preview = try await PreviewWindow(bytes: 400_000)
        let blocks = preview.rendered.document.blocks
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<5 {
            var last = 0
            for _ in 0..<15 {
                last = Int.random(in: 30..<(blocks.count - 60), using: &rng)
                preview.scroller.scroll(to: blocks[last].id)
                await wait(16)
            }
            _ = await settledOffset(of: preview.scroll)
            let landed = await preview.blockAfterNudge()
            #expect(landed.map { (last...(last + 4)).contains($0) } == true, "the last jump was to block \(last), found \(String(describing: landed))")
        }
    }

    @Test func ourOwnJumpsAreNeverReportedAsTheUsersScrolling() async throws {
        let preview = try await PreviewWindow(bytes: 400_000)
        let blocks = preview.rendered.document.blocks
        var reports: [BlockID] = []
        preview.scroller.onUserScroll = { reports.append($0) }
        for index in [500, 2_000, 40, 3_000] where index < blocks.count {
            preview.scroller.scroll(to: blocks[index].id)
            _ = await settledOffset(of: preview.scroll)
        }
        await wait(300)
        #expect(reports.isEmpty, "\(reports.count) reports")
        #expect(!preview.scroller.isUserScrolling)
    }

    @Test func aUserScrollIsReportedWithTheBlockAtTheTop() async throws {
        let preview = try await PreviewWindow(bytes: 400_000)
        let blocks = preview.rendered.document.blocks
        let order = Dictionary(uniqueKeysWithValues: blocks.enumerated().map { ($1.id, $0) })
        var reports: [BlockID] = []
        preview.scroller.onUserScroll = { reports.append($0) }
        var sawScrolling = false
        let height = Double((preview.scroll.documentView?.frame.height ?? 20_000) - 800)
        preview.wheel(-1, phase: .began)
        for step in 1...30 {
            preview.scroll.contentView.scroll(to: NSPoint(x: 0, y: Double(step) / 30 * height))
            preview.scroll.reflectScrolledClipView(preview.scroll.contentView)
            await wait(16)
            if preview.scroller.isUserScrolling { sawScrolling = true }
        }
        preview.wheel(0, phase: .ended)
        await wait(400)
        #expect(sawScrolling)
        #expect(!reports.isEmpty)
        let indexes = reports.compactMap { order[$0] }
        #expect(indexes == indexes.sorted(), "scrolling down reports later and later blocks: \(indexes.prefix(12))")
        #expect((indexes.last ?? 0) > blocks.count * 3 / 4, "the drag ended near the bottom, at block \(indexes.last ?? -1) of \(blocks.count)")
        #expect(!preview.scroller.isUserScrolling)
    }

    @Test func searchRevealJumpsWithoutAnimating() async throws {
        let preview = try await PreviewWindow(bytes: 200_000)
        let blocks = preview.rendered.document.blocks
        let before = preview.scroll.contentView.bounds.minY
        preview.scroller.scroll(to: blocks[blocks.count / 2].id, anchor: .center)
        let offset = await settledOffset(of: preview.scroll)
        #expect(offset > before + 1_000)
    }
}
