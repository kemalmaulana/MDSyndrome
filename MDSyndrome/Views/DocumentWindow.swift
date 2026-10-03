import EditorKit
import SwiftUI

struct DocumentWindow: View {
    @Binding var document: MarkdownFileDocument
    let fileURL: URL?

    var body: some View {
        MarkdownEditorView(text: $document.text)
            .frame(minWidth: 600, minHeight: 400)
    }
}
