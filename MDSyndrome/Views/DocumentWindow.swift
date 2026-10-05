import EditorKit
import MarkdownCore
import PreviewKit
import SwiftUI

struct DocumentWindow: View {
    @Binding var document: MarkdownFileDocument
    let fileURL: URL?

    @State private var session = DocumentSession()
    @State private var editor = EditorController()
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
                MarkdownPreview(rendered: session.rendered, baseURL: fileURL?.deletingLastPathComponent())
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
        .task { await session.renderNow(document.text) }
        .onChange(of: document.text) { _, newText in session.textDidChange(newText) }
    }
}
