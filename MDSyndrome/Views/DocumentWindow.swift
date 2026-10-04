import EditorKit
import MarkdownCore
import PreviewKit
import SwiftUI

struct DocumentWindow: View {
    @Binding var document: MarkdownFileDocument
    let fileURL: URL?

    @State private var session = DocumentSession()
    @SceneStorage("layoutMode") private var layoutMode: LayoutMode = .split
    @SceneStorage("splitRatio") private var splitRatio: Double = 0.5

    var body: some View {
        VStack(spacing: 0) {
            PaneLayout(mode: layoutMode, ratio: $splitRatio) {
                MarkdownEditorView(text: $document.text, isHidden: layoutMode == .preview)
            } preview: {
                MarkdownPreview(rendered: session.rendered, baseURL: fileURL?.deletingLastPathComponent())
            }
            Divider()
            StatusBar(stats: session.rendered.stats)
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Layout", selection: $layoutMode) {
                    ForEach(LayoutMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Switch between editor, split view and preview")
            }
        }
        .focusedSceneValue(\.layoutMode, $layoutMode)
        .task { await session.renderNow(document.text) }
        .onChange(of: document.text) { _, newText in session.textDidChange(newText) }
    }
}
