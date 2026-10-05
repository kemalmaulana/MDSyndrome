import EditorKit
import PreviewKit
import Testing
@testable import MDSyndrome

@MainActor
@Suite struct FindRouterTests {
    private func router(_ layout: LayoutMode, pane: Pane = .editor, editor: Bool = true, preview: Bool = true) -> FindRouter {
        FindRouter(editor: editor ? EditorController() : nil, preview: preview ? PreviewSearch() : nil, layout: layout, pane: pane)
    }

    @Test func editorOnlyAndPreviewOnlyLayoutsHaveOneTarget() {
        #expect(router(.editor).target(for: .show) == .editor)
        #expect(router(.preview, editor: false).target(for: .show) == .preview)
        #expect(router(.preview, editor: false).target(for: .next) == .preview)
    }

    @Test func splitFollowsTheLastPaneUsed() {
        #expect(router(.split, pane: .editor).target(for: .show) == .editor)
        #expect(router(.split, pane: .preview).target(for: .show) == .preview)
        #expect(router(.split, pane: .preview).target(for: .next) == .preview)
        #expect(router(.split, pane: .preview).target(for: .previous) == .preview)
    }

    @Test func replaceOnlyExistsInTheEditor() {
        #expect(router(.split, pane: .preview).target(for: .showReplace) == .editor)
        #expect(router(.preview, editor: false).target(for: .showReplace) == nil)
    }

    @Test func nothingToSearchGivesNoTarget() {
        #expect(router(.editor, editor: false, preview: false).target(for: .show) == nil)
        #expect(router(.preview, editor: false, preview: false).target(for: .show) == nil)
    }

    @Test func runningAPreviewCommandDrivesThePreviewSearch() {
        let search = PreviewSearch()
        let router = FindRouter(editor: nil, preview: search, layout: .preview, pane: .preview)
        router.run(.show)
        #expect(search.isPresented)
        router.run(.next)     // nothing matched, must not crash
        router.run(.previous)
    }
}
