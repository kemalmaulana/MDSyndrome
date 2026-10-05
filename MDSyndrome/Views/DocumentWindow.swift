import AppKit
import EditorKit
import MarkdownCore
import PreviewKit
import SwiftUI
import WebRenderKit

struct DocumentWindow: View {
    @Binding var document: MarkdownFileDocument
    let fileURL: URL?
    let webRenderer: WebRenderer

    @State private var session = DocumentSession()
    @State private var editor = EditorController()
    /// Bumped by ⌘R so the preview reads its images from disk again.
    @State private var previewReloadToken = 0
    @State private var previewSearch = PreviewSearch()
    @State private var previewScroller = PreviewScroller()
    /// Keeps the two panes at the same place in the document.
    @State private var sync = SyncScrollCoordinator()
    @AppStorage("syncScroll") private var syncScroll = true
    /// The outline column (⌃⌘S); closed until the person opens it.
    @SceneStorage("outlineVisible") private var outlineVisible = false
    /// The heading the document is at, for the outline's highlight.
    @State private var currentHeading: BlockID?
    /// Where Find goes in the split layout: the pane the user clicked or typed in last.
    @State private var activePane: Pane = .editor
    @SceneStorage("layoutMode") private var layoutMode: LayoutMode = .split
    @SceneStorage("splitRatio") private var splitRatio: Double = 0.5
    @AppStorage(EditorTheme.storageKey) private var editorThemeName = EditorTheme.tomorrowPlus.name

    private var editorIsVisible: Bool { layoutMode != .preview }
    private static let outlineWidth: Double = 220

    var body: some View {
        HStack(spacing: 0) {
            if outlineVisible {
                OutlineSidebar(items: session.rendered.outline, current: currentHeading, select: { sync.navigate(to: $0.id) })
                    .frame(width: Self.outlineWidth)
                Divider()
            }
            VStack(spacing: 0) {
                PaneLayout(mode: layoutMode, ratio: $splitRatio) {
                    MarkdownEditorView(text: $document.text, theme: EditorTheme.named(editorThemeName),
                                       isHidden: !editorIsVisible, controller: editor)
                } preview: {
                    MarkdownPreview(rendered: session.rendered, baseURL: fileURL?.deletingLastPathComponent(), reloadToken: previewReloadToken,
                                    search: layoutMode == .editor ? nil : previewSearch, webRenderer: webRenderer, scroller: previewScroller,
                                    linkHandler: { LinkOpener.handle($0, window: NSApp.keyWindow) }, onToggleTask: toggleTask)
                        .simultaneousGesture(TapGesture().onEnded { activePane = .preview })
                }
                Divider()
                StatusBar(stats: session.rendered.stats)
            }
            .frame(minWidth: 600)
        }
        .frame(minHeight: 400)
        .toolbar(id: "document") {
            DocumentToolbar(layoutMode: $layoutMode, outlineVisible: $outlineVisible, editor: editor, editorIsVisible: editorIsVisible)
        }
        .focusedSceneValue(\.layoutMode, $layoutMode)
        .focusedSceneValue(\.outlineVisible, $outlineVisible)
        .focusedSceneValue(\.editorController, editorIsVisible ? editor : nil)
        .focusedSceneValue(\.findRouter, FindRouter(editor: editorIsVisible ? editor : nil, preview: layoutMode == .editor ? nil : previewSearch,
                                                   layout: layoutMode, pane: activePane))
        .focusedSceneValue(\.reloadDocument, fileURL == nil ? nil : DocumentAction(run: reloadFromDisk))
        .onAppear {
            let pane = $activePane
            let sync = sync
            editor.onFocus = {
                if pane.wrappedValue != .editor { pane.wrappedValue = .editor }
                sync.editorActivity()
            }
            sync.attach(editor: editor, preview: previewScroller)
            sync.isEnabled = syncScroll
            sync.onPosition = { line in
                let heading = Outline.current(in: session.rendered.outline, atLine: line)?.id
                if heading != currentHeading { currentHeading = heading }
            }
            previewScroller.onNavigate = { [weak sync] id in sync?.navigate(to: id) }
        }
        .onChange(of: syncScroll) { _, enabled in sync.isEnabled = enabled }
        .onChange(of: layoutMode, initial: true) { _, mode in
            sync.layoutDidChange(editorVisible: mode != .preview, previewVisible: mode != .editor)
        }
        .onChange(of: session.renderCount, initial: true) { _, _ in sync.renderDidChange(session.rendered.sourceMap) }
        .onChange(of: previewSearch.isPresented) { _, isPresented in if isPresented { activePane = .preview } }
        .onChange(of: layoutMode) { _, mode in if mode == .editor { previewSearch.close() } }
        .task { await session.renderNow(document.text) }
        .onChange(of: document.text) { _, newText in session.textDidChange(newText) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in pullChangesFromDisk() }
    }

    /// A click on a task checkbox in the preview. The line number belongs to the render the preview shows, so it
    /// is only used while that render is the latest (an edit still waiting for its render would have moved lines);
    /// the editor then refuses a line that holds no task marker.
    private func toggleTask(atLine line: Int) {
        guard session.isCurrent, editor.toggleTask(atLine: line) else {
            NSSound.beep()
            return
        }
    }

    /// Back from another app: if it saved this file meanwhile, show the new text.
    private func pullChangesFromDisk() {
        guard let fileURL, let nsDocument = NSDocumentController.shared.document(for: fileURL) else { return }
        DocumentReloader.reloadIfChangedOnDisk(nsDocument, completion: { reloaded in
            if reloaded { previewReloadToken += 1 }
        })
    }

    /// ⌘R: read the file again and refresh what the preview shows from disk. The text itself reaches the
    /// editor and the preview through the document binding, like any other change.
    private func reloadFromDisk() {
        guard let fileURL, let nsDocument = NSDocumentController.shared.document(for: fileURL) else {
            NSSound.beep()
            return
        }
        DocumentReloader.reload(nsDocument, completion: { reloaded in
            if reloaded { previewReloadToken += 1 }
        })
    }
}
