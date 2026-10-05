import AppKit
import MarkdownCore
import PDFKit
import PreviewKit
import SwiftUI
import UniformTypeIdentifiers

/// What the export commands can do in the active window; nil outside a document window.
struct ExportActions {
    let exportHTML: DocumentAction
    let exportPDF: DocumentAction
    let copyHTML: DocumentAction
    let printDocument: DocumentAction
}

extension FocusedValues {
    @Entry var exportActions: ExportActions?
}

/// Export as HTML or PDF, Copy HTML and Print (PRD EX-1…EX-4). A failure shows an alert and leaves no partial file.
@MainActor
enum ExportService {
    struct Source {
        let document: MarkdownDocument
        let title: String
        let baseURL: URL?
        let theme: PreviewTheme
    }

    static func exportHTML(_ source: Source, window: NSWindow?) {
        let html = HTMLExporter.standalone(source.document, theme: source.theme, title: source.title)
        save(Data(html.utf8), as: .html, name: source.title + ".html", window: window)
    }

    static func exportPDF(_ source: Source, window: NSWindow?) {
        guard let data = pdf(source) else { return fail("The PDF could not be made.", window: window) }
        save(data, as: .pdf, name: source.title + ".pdf", window: window)
    }

    static func copyHTML(_ source: Source) {
        let html = HTMLExporter.fragment(source.document, theme: source.theme)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .html)
        NSPasteboard.general.setString(html, forType: .string)
    }

    static func printDocument(_ source: Source, window: NSWindow?) {
        guard let data = pdf(source), let document = PDFDocument(data: data),
              let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true) else {
            return fail("The document could not be prepared for printing.", window: window)
        }
        if let window { operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil) } else { operation.run() }
    }

    /// The PDF for the paper size and margins of the current print settings, on a light theme at normal size.
    private static func pdf(_ source: Source) -> Data? {
        let info = NSPrintInfo.shared
        let margins = NSEdgeInsets(top: info.topMargin, left: info.leftMargin, bottom: info.bottomMargin, right: info.rightMargin)
        return PDFExporter.export(source.document, theme: source.theme, baseURL: source.baseURL, paperSize: info.paperSize, margins: margins)
    }

    private static func save(_ data: Data, as type: UTType, name: String, window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic) } catch { fail(error.localizedDescription, window: window) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: write) } else { write(panel.runModal()) }
    }

    private static func fail(_ reason: String, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Export failed"
        alert.informativeText = reason
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
