import AppKit
import Foundation
import MarkdownCore
import PDFKit
import Testing
import WebRenderKit
@testable import PreviewKit

/// The real web renderer feeding the exporters: a diagram and a formula SwiftMath rejects come out as pictures in the HTML and
/// in the PDF. Starts WebKit, so it runs locally only.
@MainActor
@Suite(.requiresWindowServer, .serialized) struct ExportIntegrationTests {
    private let markdown = """
    # Export

    ```mermaid
    flowchart LR
      A --> B
    ```

    A formula SwiftMath cannot typeset: $\\operatorname{lcm}(a,b)$.
    """

    @Test(.timeLimit(.minutes(2))) func htmlGetsLightAndDarkPicturesForTheDiagramAndTheFormula() async throws {
        let renderer = WebRenderer()
        let document = MarkdownParser.parse(markdown)
        let resources = await ExportResources.prepare(document, baseURL: nil, renderer: renderer, theme: .github, options: .html)
        let page = HTMLExporter.standalone(document, theme: .github, title: "Export", resources: resources)
        #expect(page.contains("<figure class=\"diagram\"><picture>"), "the diagram is a picture")
        #expect(page.contains("class=\"math-katex\""), "the fallback formula is a picture")
        #expect(page.contains("media=\"(prefers-color-scheme: dark)\" srcset="))
        #expect(!page.contains("language-mermaid") && !page.lowercased().contains("<script"))
    }

    @Test(.timeLimit(.minutes(2))) func thePDFDrawsTheDiagramInsteadOfItsSource() async throws {
        let renderer = WebRenderer()
        let document = MarkdownParser.parse(markdown)
        let margins = NSEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        let resources = await ExportResources.prepare(document, baseURL: nil, renderer: renderer, theme: .github,
                                                      options: .pdf(contentWidth: 540, allowRemoteImages: false))
        let data = try #require(PDFExporter.export(document, theme: .github, baseURL: nil, paperSize: CGSize(width: 612, height: 792),
                                                   margins: margins, resources: resources))
        let text = PDFDocument(data: data)?.string ?? ""
        #expect(text.contains("Export"))
        #expect(!text.contains("flowchart"), "the diagram's source is not printed when its picture is")
    }

    /// The whole kitchen sink, exported with the real renderer. Set `EXPORT_OUT_DIR` to keep the files for a look.
    @Test(.timeLimit(.minutes(3))) func theKitchenSinkExportsToBothFormats() async throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let source = try String(contentsOf: url.appendingPathComponent("Fixtures/kitchen-sink.md"), encoding: .utf8)
        let document = MarkdownParser.parse(source)
        let renderer = WebRenderer()
        let margins = NSEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        let images = url.appendingPathComponent("Fixtures")

        let htmlResources = await ExportResources.prepare(document, baseURL: images, renderer: renderer, theme: .github, options: .html)
        let page = HTMLExporter.standalone(document, theme: .github, title: "Kitchen sink", resources: htmlResources)
        let pdfResources = await ExportResources.prepare(document, baseURL: images, renderer: renderer, theme: .github,
                                                         options: .pdf(contentWidth: 540, allowRemoteImages: false))
        let pdf = try #require(PDFExporter.export(document, theme: .github, baseURL: images, paperSize: CGSize(width: 612, height: 792),
                                                  margins: margins, resources: pdfResources))
        #expect((PDFDocument(data: pdf)?.pageCount ?? 0) >= 1)
        #expect(page.contains("<picture>") && !page.lowercased().contains("<script"))
        if let out = ProcessInfo.processInfo.environment["EXPORT_OUT_DIR"] {
            try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
            try page.write(toFile: out + "/kitchen-sink.html", atomically: true, encoding: .utf8)
            try pdf.write(to: URL(fileURLWithPath: out + "/kitchen-sink.pdf"))
        }
    }
}
