import AppKit
import MarkdownCore
import PDFKit
import PreviewKit
import SwiftUI
import UniformTypeIdentifiers
import WebRenderKit

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
        /// Draws diagrams, formulas and HTML blocks; nil leaves them as source.
        var renderer: (any WebRendering)? = nil
        var allowRemoteImages = true
    }

    static func exportHTML(_ source: Source, window: NSWindow?) {
        prepare(source, options: .html, window: window) { resources in
            let html = HTMLExporter.standalone(source.document, theme: source.theme, title: source.title, resources: resources)
            save(Data(html.utf8), as: .html, name: source.title + ".html", window: window)
        }
    }

    static func exportPDF(_ source: Source, window: NSWindow?) {
        prepare(source, options: pdfOptions(source), window: window) { resources in
            guard let data = pdf(source, resources) else { return fail("The PDF could not be made.", window: window) }
            save(data, as: .pdf, name: source.title + ".pdf", window: window)
        }
    }

    static func copyHTML(_ source: Source) {
        let html = HTMLExporter.fragment(source.document, theme: source.theme)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .html)
        NSPasteboard.general.setString(html, forType: .string)
    }

    static func printDocument(_ source: Source, window: NSWindow?) {
        prepare(source, options: pdfOptions(source), window: window) { resources in
            guard let data = pdf(source, resources), let document = PDFDocument(data: data),
                  let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true) else {
                return fail("The document could not be prepared for printing.", window: window)
            }
            if let window { operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil) } else { operation.run() }
        }
    }

    private static func pdfOptions(_ source: Source) -> ExportResources.Options {
        let info = NSPrintInfo.shared
        return .pdf(contentWidth: info.paperSize.width - info.leftMargin - info.rightMargin, allowRemoteImages: source.allowRemoteImages)
    }

    /// Fetches what the export needs, showing a "Preparing export…" sheet with Cancel only when it takes a moment.
    /// Cancelling ends the export quietly: nothing is written.
    private static func prepare(_ source: Source, options: ExportResources.Options, window: NSWindow?,
                                then proceed: @escaping @MainActor (ExportResources) -> Void) {
        let work = Task { @MainActor in
            await ExportResources.prepare(source.document, baseURL: source.baseURL, renderer: source.renderer, theme: source.theme, options: options)
        }
        let sheet = PreparingSheet(window: window) { work.cancel() }
        sheet.show(after: .milliseconds(300))
        Task { @MainActor in
            let resources = await work.value
            sheet.dismiss()
            if !work.isCancelled { proceed(resources) }
        }
    }

    /// The PDF for the paper size and margins of the current print settings, on a light theme at normal size.
    private static func pdf(_ source: Source, _ resources: ExportResources) -> Data? {
        let info = NSPrintInfo.shared
        let margins = NSEdgeInsets(top: info.topMargin, left: info.leftMargin, bottom: info.bottomMargin, right: info.rightMargin)
        return PDFExporter.export(source.document, theme: source.theme, baseURL: source.baseURL, paperSize: info.paperSize, margins: margins,
                                  resources: resources)
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

/// "Preparing export…" with a Cancel button, shown on the window after a short delay.
@MainActor
private final class PreparingSheet {
    private let alert = NSAlert()
    private weak var window: NSWindow?
    private let onCancel: @MainActor () -> Void
    private var delay: Task<Void, Never>?
    private var isShown = false

    init(window: NSWindow?, onCancel: @escaping @MainActor () -> Void) {
        self.window = window
        self.onCancel = onCancel
        alert.messageText = "Preparing export…"
        alert.informativeText = "Drawing diagrams and loading images."
        alert.addButton(withTitle: "Cancel")
        let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 240, height: 16))
        spinner.style = .bar
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        alert.accessoryView = spinner
    }

    func show(after wait: Duration) {
        guard window != nil else { return }
        delay = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, let window = self.window else { return }
            self.isShown = true
            self.alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn { self?.onCancel() }
            }
        }
    }

    func dismiss() {
        delay?.cancel()
        if isShown, let window { window.endSheet(alert.window, returnCode: .continue) }
        isShown = false
    }
}
