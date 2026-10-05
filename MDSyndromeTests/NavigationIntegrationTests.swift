import AppKit
import EditorKit
import MarkdownCore
import PreviewKit
import SwiftUI
import Testing
@testable import MDSyndrome

/// Forwards to the real editor and counts what the coordinator asks of it.
@MainActor
private final class CountingEditor: EditorScrolling {
    let controller: EditorController
    var jumps: [Int] = []
    init(_ controller: EditorController) { self.controller = controller }
    var topLine: Int? { controller.topLine }
    func scroll(toLine line: Int) {
        jumps.append(line)
        controller.scroll(toLine: line)
    }
    var onScroll: ((Int) -> Void)? {
        get { controller.onScroll }
        set { controller.onScroll = newValue }
    }
}

/// Forwards to the real preview and counts what the coordinator asks of it.
@MainActor
private final class CountingPreview: PreviewScrolling {
    let scroller: PreviewScroller
    var jumps: [BlockID] = []
    var topScrolls = 0
    init(_ scroller: PreviewScroller) { self.scroller = scroller }
    func scroll(to id: BlockID) {
        jumps.append(id)
        scroller.scroll(to: id)
    }
    func scrollToTop() {
        topScrolls += 1
        scroller.scrollToTop()
    }
    var onUserScroll: ((BlockID) -> Void)? {
        get { scroller.onUserScroll }
        set { scroller.onUserScroll = newValue }
    }
}

private final class TextBox: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
}

@MainActor
private func scrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    for sub in view.subviews { if let found = scrollView(in: sub) { return found } }
    return nil
}

/// The whole of NAV-2 on a 1 MB document: the real editor, the real preview and the real coordinator, the panes
/// in off-screen windows. "Without jitter" is checked as: one programmatic scroll per user scroll, the right place
/// at the end, and nothing at all once things are quiet (no echo ping-pong).
@MainActor
@Suite(.notOnCI) struct NavigationIntegrationTests {
    @MainActor private struct Rig {
        let rendered: RenderedDocument
        let controller = EditorController()
        let scroller = PreviewScroller()
        let editor: CountingEditor
        let preview: CountingPreview
        let coordinator = SyncScrollCoordinator()
        let editorScroll: NSScrollView
        let previewScroll: NSScrollView
        let windows: [NSWindow]
        let blocks: [Block]

        init() async throws {
            _ = NSApplication.shared
            var text = ""
            var n = 0
            while text.utf8.count < 1_000_000 {
                n += 1
                text += "## Section \(n)\n\nParagraph one of section \(n). Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.\n\n- [ ] first item of \(n)\n- [x] second item with `code` and **bold**\n\n```swift\nlet value\(n) = \(n)\n```\n\n| a | b |\n|---|---|\n| \(n) | x |\n\n"
            }
            rendered = MarkdownPipeline.render(text, options: .default)
            blocks = rendered.document.blocks
            let box = TextBox(text)
            let editorHost = NSHostingController(rootView: MarkdownEditorView(text: Binding(get: { box.value }, set: { box.value = $0 }), controller: controller))
            let editorWindow = NSWindow(contentViewController: editorHost)
            editorWindow.styleMask = [.titled, .resizable]
            editorWindow.setFrame(NSRect(x: -20000, y: -20000, width: 700, height: 700), display: false)
            editorWindow.orderFrontRegardless()
            let previewHost = NSHostingController(rootView: MarkdownPreview(rendered: rendered, baseURL: nil, scroller: scroller))
            let previewWindow = NSWindow(contentViewController: previewHost)
            previewWindow.styleMask = [.titled, .resizable]
            previewWindow.setFrame(NSRect(x: -20000, y: -21000, width: 900, height: 700), display: false)
            previewWindow.orderFrontRegardless()
            windows = [editorWindow, previewWindow]
            try? await Task.sleep(for: .milliseconds(1_500))
            editorScroll = try #require(scrollView(in: editorHost.view))
            previewScroll = try #require(scrollView(in: previewHost.view))
            editor = CountingEditor(controller)
            preview = CountingPreview(scroller)
            coordinator.attach(editor: editor, preview: preview)
            coordinator.renderDidChange(rendered.sourceMap)
        }

        func close() { windows.forEach { $0.orderOut(nil) } }

        func wait(_ milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

        /// A wheel event in the given phase, fed to the SwiftUI scroll view, which reports it as the user scrolling.
        func wheel(_ delta: Int32, phase: CGScrollPhase) {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { return }
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            if let event = NSEvent(cgEvent: cg) { previewScroll.scrollWheel(with: event) }
        }
    }

    @Test func theEditorLeadsAndThePreviewGoesToTheBlockOfItsTopLine() async throws {
        let rig = try await Rig()
        defer { rig.close() }
        var rng = SystemRandomNumberGenerator()
        var wrong = 0
        var rounds = 0
        for _ in 0..<30 {
            let y = Double.random(in: 0..<Double((rig.editorScroll.documentView?.frame.height ?? 10_000) - 800), using: &rng)
            rig.editorScroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            rig.editorScroll.reflectScrolledClipView(rig.editorScroll.contentView)
            await rig.wait(250)
            guard let line = rig.controller.topLine, let expected = rig.rendered.sourceMap.blockID(atLine: line) else { continue }
            rounds += 1
            if rig.preview.jumps.last != expected { wrong += 1 }
        }
        #expect(rounds >= 25)
        #expect(wrong == 0, "\(wrong) of \(rounds) scrolls left the preview on the wrong block")
        #expect(rig.preview.jumps.count <= rounds * 2, "\(rig.preview.jumps.count) jumps for \(rounds) scrolls")
        #expect(rig.editor.jumps.isEmpty, "the editor was never moved back")
        let (jumps, scrolls) = (rig.preview.jumps.count, rig.editor.jumps.count)
        await rig.wait(800)
        #expect(rig.preview.jumps.count == jumps && rig.editor.jumps.count == scrolls, "quiet means quiet")
    }

    @Test func aFastDragOfTheEditorEndsWithThePreviewOnTheRightBlock() async throws {
        let rig = try await Rig()
        defer { rig.close() }
        let height = Double((rig.editorScroll.documentView?.frame.height ?? 10_000) - 800)
        for step in 0..<80 {
            rig.editorScroll.contentView.scroll(to: NSPoint(x: 0, y: Double(step) / 79 * height))
            rig.editorScroll.reflectScrolledClipView(rig.editorScroll.contentView)
            await rig.wait(16)
        }
        await rig.wait(500)
        let line = try #require(rig.controller.topLine)
        #expect(rig.preview.jumps.last == rig.rendered.sourceMap.blockID(atLine: line))
        #expect(rig.preview.jumps.count <= 120, "\(rig.preview.jumps.count) jumps for 80 steps")
        #expect(rig.editor.jumps.isEmpty)
        let jumps = rig.preview.jumps.count
        await rig.wait(800)
        #expect(rig.preview.jumps.count == jumps)
    }

    @Test func thePreviewLeadsAndTheEditorGoesToTheFirstLineOfItsTopBlock() async throws {
        let rig = try await Rig()
        defer { rig.close() }
        var rng = SystemRandomNumberGenerator()
        var reports: [BlockID] = []
        let coordinatorHandler = rig.scroller.onUserScroll
        rig.scroller.onUserScroll = { reports.append($0); coordinatorHandler?($0) }
        var wrong = 0
        for _ in 0..<30 {
            let y = Double.random(in: 0..<Double((rig.previewScroll.documentView?.frame.height ?? 10_000) - 800), using: &rng)
            let before = reports.count
            rig.wheel(-1, phase: .began)
            rig.previewScroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            rig.previewScroll.reflectScrolledClipView(rig.previewScroll.contentView)
            await rig.wait(120)
            rig.wheel(0, phase: .ended)
            await rig.wait(250)
            guard reports.count > before, let last = reports.last, let line = rig.rendered.sourceMap.startLine(of: last), let top = rig.controller.topLine else { wrong += 1; continue }
            if abs(top - line) > 1 { wrong += 1 }
        }
        #expect(wrong == 0, "\(wrong) of 30 scrolls left the editor on the wrong line")
        #expect(rig.editor.jumps.count <= reports.count, "one editor scroll per report: \(rig.editor.jumps.count) for \(reports.count)")
        #expect(rig.preview.jumps.isEmpty, "the preview was never moved back")
        let scrolls = rig.editor.jumps.count
        await rig.wait(800)
        #expect(rig.editor.jumps.count == scrolls && rig.preview.jumps.isEmpty, "quiet means quiet")
    }

    @Test func aFastDragOfThePreviewEndsWithTheEditorOnTheLastBlocksFirstLine() async throws {
        let rig = try await Rig()
        defer { rig.close() }
        var reports: [BlockID] = []
        let coordinatorHandler = rig.scroller.onUserScroll
        rig.scroller.onUserScroll = { reports.append($0); coordinatorHandler?($0) }
        let height = Double((rig.previewScroll.documentView?.frame.height ?? 10_000) - 800)
        rig.wheel(-1, phase: .began)
        for step in 0..<80 {
            rig.previewScroll.contentView.scroll(to: NSPoint(x: 0, y: Double(step) / 79 * height))
            rig.previewScroll.reflectScrolledClipView(rig.previewScroll.contentView)
            await rig.wait(16)
        }
        rig.wheel(0, phase: .ended)
        await rig.wait(600)
        let last = try #require(reports.last)
        #expect(reports.count > 40, "\(reports.count) reports for 80 steps")
        #expect(rig.controller.topLine == rig.rendered.sourceMap.startLine(of: last))
        #expect(rig.editor.jumps.count <= reports.count)
        #expect(rig.preview.jumps.isEmpty)
        let scrolls = rig.editor.jumps.count
        await rig.wait(800)
        #expect(rig.editor.jumps.count == scrolls)
    }

    @Test func navigatingTakesBothPanesToABlock() async throws {
        let rig = try await Rig()
        defer { rig.close() }
        let target = rig.blocks[rig.blocks.count / 2]
        rig.coordinator.navigate(to: target.id)
        await rig.wait(600)
        #expect(rig.preview.jumps == [target.id])
        #expect(rig.editor.jumps == [target.lines.start])
        #expect(rig.controller.topLine.map { abs($0 - target.lines.start) <= 3 } == true)
        await rig.wait(800)
        #expect(rig.preview.jumps.count == 1 && rig.editor.jumps.count == 1, "the echoes of a navigation start nothing")
    }
}
