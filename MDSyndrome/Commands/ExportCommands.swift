import SwiftUI

struct ExportCommands: Commands {
    @FocusedValue(\.exportActions) private var export

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export as HTML…") { export?.exportHTML.run() }.disabled(export == nil)
            Button("Export as PDF…") { export?.exportPDF.run() }.disabled(export == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { export?.printDocument.run() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(export == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy HTML") { export?.copyHTML.run() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(export == nil)
        }
    }
}
