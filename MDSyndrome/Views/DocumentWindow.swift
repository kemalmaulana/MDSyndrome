import AppKit
import EditorKit
import MarkdownCore
import PreviewKit
import SwiftUI

struct DocumentWindow: View {
    @Binding var document: MarkdownFileDocument
    let fileURL: URL?

    @State private var session = DocumentSession()
    @State private var editor = EditorController()
    /// Bumped by ⌘R so the preview reads its images from disk again.
    @State private var previewReloadToken = 0
    @SceneStorage("layoutMode") private var layoutMode: LayoutMode = .split
    @SceneStorage("splitRatio") private var splitRatio: Double = 0.5
    @AppStorage(EditorTheme.storageKey) private var editorThemeName = EditorTheme.tomorrowPlus.name

    private var editorIsVisible: Bool { layoutMode != .preview }

    var body: some View {
        VStack(spacing: 0) {
            PaneLayout(mode: layoutMode, ratio: $splitRatio) {
                MarkdownEditorView(text: $document.text, theme: EditorTheme.named(editorThemeName),
                                   isHidden: !editorIsVisible, controller: editor)
            } preview: {
                MarkdownPreview(rendered: session.rendered, baseURL: fileURL?.deletingLastPathComponent(), reloadToken: previewReloadToken)
            }
            Divider()
            StatusBar(stats: session.rendered.stats)
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar(id: "document") {
            DocumentToolbar(layoutMode: $layoutMode, editor: editor, editorIsVisible: editorIsVisible)
        }
        .focusedSceneValue(\.layoutMode, $layoutMode)
        .focusedSceneValue(\.editorController, editorIsVisible ? editor : nil)
        .focusedSceneValue(\.reloadDocument, fileURL == nil ? nil : DocumentAction(run: reloadFromDisk))
        .task { await session.renderNow(document.text) }
        .onChange(of: document.text) { _, newText in session.textDidChange(newText) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in pullChangesFromDisk() }
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
