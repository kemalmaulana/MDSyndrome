import SwiftUI

@main
struct MDSyndromeApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownFileDocument()) { file in
            DocumentWindow(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            ViewCommands()
            FormatCommands()
        }
    }
}
