import SwiftUI
import WebRenderKit

@main
struct MDSyndromeApp: App {
    /// One renderer for every window. Creating it starts nothing: the hidden web views are made when a
    /// document first needs a diagram, a fallback formula or a complex HTML block.
    @State private var webRenderer = WebRenderer()

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownFileDocument()) { file in
            DocumentWindow(document: file.$document, fileURL: file.fileURL, webRenderer: webRenderer)
        }
        .commands {
            FileCommands()
            ViewCommands()
            FormatCommands()
            FindCommands()
        }
    }
}
