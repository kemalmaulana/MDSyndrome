import AppKit
import CoreGraphics
import Foundation
import MarkdownCore
import PDFKit
import SwiftUI
import Testing
import WebRenderKit
@testable import PreviewKit

private let theme = PreviewTheme.github
private let mermaidSource = "flowchart LR\n  A --> B"
private let mermaidFence = "```mermaid\n\(mermaidSource)\n```"

private func tinyPNG() -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemRed.setFill()
    NSRect(x: 0, y: 0, width: 20, height: 20).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

private func temporaryFolder() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private let samplePicture = ExportResources.Outcome.picture(RenderedImage(pdf: samplePDF(), size: CGSize(width: 40, height: 20), baseline: 4))

@MainActor
@Suite struct ExportResourcesTests {
    @Test func aDocumentWithoutWebContentNeverCallsTheRenderer() async {
        let fake = FakeRenderer()
        let document = MarkdownParser.parse("# Title\n\nplain *text*, a native formula $x^2$ and a `code` span.")
        let resources = await ExportResources.prepare(document, baseURL: nil, renderer: fake, theme: theme, options: .html)
        #expect(fake.requests.isEmpty, "no web view may start for a document that needs none (NF-1)")
        #expect(resources.pictures.isEmpty)
    }

    @Test func aDiagramIsDrawnForLightAndDarkInHTMLAndForLightOnlyInPDF() async {
        let fake = FakeRenderer()
        let document = MarkdownParser.parse(mermaidFence)
        let light = PictureRequests.diagram(.mermaid, code: mermaidSource, theme: theme, scheme: .light)
        let dark = PictureRequests.diagram(.mermaid, code: mermaidSource, theme: theme, scheme: .dark)

        let forHTML = await ExportResources.prepare(document, baseURL: nil, renderer: fake, theme: theme, options: .html)
        #expect(forHTML.pictures.count == 2 && forHTML.pictures[light] != nil && forHTML.pictures[dark] != nil)

        let forPDF = await ExportResources.prepare(document, baseURL: nil, renderer: fake, theme: theme,
                                                   options: .pdf(contentWidth: 500, allowRemoteImages: false))
        #expect(forPDF.pictures.count == 1 && forPDF.pictures[light] != nil)
    }

    @Test func aSyntaxErrorIsRecordedAndTheOtherDiagramsStillRender() async {
        let fake = FakeRenderer()
        fake.answer = { request in
            if request.source == "bad" { throw RenderError.syntax("Parse error") }
            return RenderedImage(pdf: samplePDF(), size: CGSize(width: 40, height: 20))
        }
        let document = MarkdownParser.parse("```mermaid\nbad\n```\n\n\(mermaidFence)")
        let resources = await ExportResources.prepare(document, baseURL: nil, renderer: fake, theme: theme,
                                                      options: .pdf(contentWidth: 500, allowRemoteImages: false))
        #expect(resources.pictures[PictureRequests.diagram(.mermaid, code: "bad", theme: theme, scheme: .light)] == .failed(.syntax("Parse error")))
        #expect(resources.pictures.count == 2)
    }

    @Test func cancellingStopsBeforeAnyRequest() async {
        let fake = FakeRenderer()
        let document = MarkdownParser.parse((1...5).map { "```mermaid\nflowchart LR\n  A\($0) --> B\n```" }.joined(separator: "\n\n"))
        let work = Task { @MainActor in
            await ExportResources.prepare(document, baseURL: nil, renderer: fake, theme: theme, options: .html)
        }
        work.cancel()
        let resources = await work.value
        #expect(resources.pictures.count < 5 && fake.requests.count < 5)
    }

    @Test func localImagesAreReadAndMissingOrRemoteOnesAreRecorded() async throws {
        let dir = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try tinyPNG().write(to: dir.appendingPathComponent("a.png"))
        let document = MarkdownParser.parse("![a](a.png) ![b](missing.png) ![r](https://example.com/x.png)")
        let resources = await ExportResources.prepare(document, baseURL: dir, renderer: nil, theme: theme,
                                                      options: .pdf(contentWidth: 500, allowRemoteImages: false))
        #expect(resources.images[ImageSource.resolve("a.png", baseURL: dir)] != nil)
        #expect(resources.imageErrors[ImageSource.resolve("missing.png", baseURL: dir)] != nil)
        #expect(resources.imageErrors[ImageSource.resolve("https://example.com/x.png", baseURL: dir)] != nil, "remote loading is off, so nothing is fetched")
    }

    @Test func htmlBlocksGetTheirImagesInlinedAndAreSnapshottedAtTheContentWidth() async throws {
        let dir = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try tinyPNG().write(to: dir.appendingPathComponent("logo.png"))
        let fake = FakeRenderer()
        let block = "<table><tr><td><img src=\"logo.png\"></td></tr></table>"
        let resources = await ExportResources.prepare(MarkdownParser.parse(block), baseURL: dir, renderer: fake, theme: theme,
                                                      options: .pdf(contentWidth: 480, allowRemoteImages: false))
        let inlined = try #require(resources.inlinedHTML[block])
        #expect(inlined.contains("data:image/png;base64,"))
        let request = try #require(fake.requests.first)
        #expect(request.kind == .html && request.width == 480 && request.source == inlined)
    }
}

@MainActor
@Suite struct ExportNeedsTests {
    @Test func findsDiagramsAndImagesInsideQuotesListsAndEmphasis() {
        let markdown = "> quote\n>\n> ```mermaid\n> \(mermaidSource.replacingOccurrences(of: "\n", with: "\n> "))\n> ```\n\n- item\n\n  ![x](pic.png)\n\n*![e](emph.png)*"
        let needs = ExportNeeds.collect(MarkdownParser.parse(markdown).blocks, theme: theme, contextSizes: true)
        #expect(needs.diagrams.count == 1 && needs.diagrams.first?.kind == .mermaid)
        #expect(Set(needs.imageSources) == ["pic.png", "emph.png"])
    }

    @Test func aFormulaSwiftMathRejectsBecomesAKaTeXRequestAtItsOwnSize() {
        let markdown = "# Title with $\\operatorname{lcm}(a,b)$\n\nBody with $\\operatorname{lcm}(a,b)$.\n\n$$\n\\operatorname{sin} x\n$$"
        let needs = ExportNeeds.collect(MarkdownParser.parse(markdown).blocks, theme: theme, contextSizes: true)
        let requests = needs.requests(theme: theme, scheme: .light)
        let sizes = Set(requests.filter { $0.kind == .katex(display: false) }.map(\.fontSize))
        #expect(sizes == [theme.headingSize(level: 1), theme.bodyFontSize], "the heading's formula is drawn at the heading size, as in the preview")
        #expect(requests.contains { $0.kind == .katex(display: true) && $0.source == "\\operatorname{sin} x" })
    }

    @Test func htmlExportDrawsEveryFormulaAtTheBodySize() {
        let needs = ExportNeeds.collect(MarkdownParser.parse("# Title with $\\operatorname{lcm}(a,b)$").blocks, theme: theme, contextSizes: false)
        #expect(Set(needs.requests(theme: theme, scheme: .light).map(\.fontSize)) == [theme.bodyFontSize])
    }
}

@MainActor
@Suite struct ExportOutputTests {
    private let light = PictureRequests.diagram(.mermaid, code: mermaidSource, theme: theme, scheme: .light)
    private let dark = PictureRequests.diagram(.mermaid, code: mermaidSource, theme: theme, scheme: .dark)

    @Test func aPreparedDiagramBecomesAPictureWithADarkSource() {
        var resources = ExportResources()
        resources.pictures[light] = samplePicture
        resources.pictures[dark] = samplePicture
        let page = HTMLExporter.standalone(MarkdownParser.parse(mermaidFence), theme: theme, title: "T", resources: resources)
        #expect(page.contains("<figure class=\"diagram\"><picture>") && page.contains("srcset=\"data:image/png;base64,"))
        #expect(page.contains("media=\"(prefers-color-scheme: dark)\" srcset"))
        #expect(page.contains("alt=\"Diagram: flowchart LR\""))
        #expect(!page.contains("language-mermaid") && !page.lowercased().contains("<script"))
    }

    @Test func withoutAPictureOrWithAFailedOneTheDiagramStaysCode() {
        let document = MarkdownParser.parse(mermaidFence)
        #expect(HTMLExporter.standalone(document, theme: theme, title: "T").contains("class=\"language-mermaid\""))
        var failed = ExportResources()
        failed.pictures[light] = .failed(.syntax("x"))
        #expect(HTMLExporter.standalone(document, theme: theme, title: "T", resources: failed).contains("class=\"language-mermaid\""))
    }

    @Test func aLightPictureAloneHasNoDarkSource() {
        var resources = ExportResources()
        resources.pictures[light] = samplePicture
        let page = HTMLExporter.standalone(MarkdownParser.parse(mermaidFence), theme: theme, title: "T", resources: resources)
        #expect(page.contains("<picture>") && !page.contains("srcset"))
    }

    @Test func aPreparedKaTeXFormulaBecomesAnImageAndAnUnpreparedOneStaysCode() {
        let latex = "\\operatorname{sin} x"
        let document = MarkdownParser.parse("$$\n\(latex)\n$$")
        #expect(HTMLExporter.fragment(document).contains("<code>"))
        var resources = ExportResources()
        resources.pictures[PictureRequests.blockFormula(latex, theme: theme, scheme: .light)] = samplePicture
        let page = HTMLExporter.standalone(document, theme: theme, title: "T", resources: resources)
        #expect(page.contains("class=\"math-katex\"") && page.contains("alt=\"\\operatorname{sin} x\""))
    }

    @Test func aPreparedImageChangesThePDFAndAMissingOneStillExports() throws {
        let dir = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let document = MarkdownParser.parse("Before\n\n![pic](pic.png)\n\nAfter")
        var prepared = ExportResources()
        prepared.images[ImageSource.resolve("pic.png", baseURL: dir)] = tinyPNG()
        let margins = NSEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        let withImage = try #require(PDFExporter.export(document, theme: theme, baseURL: dir, paperSize: CGSize(width: 612, height: 792), margins: margins, resources: prepared))
        let without = try #require(PDFExporter.export(document, theme: theme, baseURL: dir, paperSize: CGSize(width: 612, height: 792), margins: margins))
        #expect(PDFDocument(data: withImage)?.pageCount == 1 && PDFDocument(data: without)?.pageCount == 1)
        #expect(withImage != without, "the picture is in the first and a failure label in the second")
    }

    @Test func aPreparedDiagramIsInThePDF() throws {
        var resources = ExportResources()
        resources.pictures[light] = samplePicture
        let margins = NSEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        let document = MarkdownParser.parse(mermaidFence)
        let drawn = try #require(PDFExporter.export(document, theme: theme, baseURL: nil, paperSize: CGSize(width: 612, height: 792), margins: margins, resources: resources))
        let asCode = try #require(PDFExporter.export(document, theme: theme, baseURL: nil, paperSize: CGSize(width: 612, height: 792), margins: margins))
        #expect(drawn != asCode)
        #expect(PDFDocument(data: drawn)?.string?.contains("flowchart") != true, "the source is not printed when the picture is")
    }

    @Test func codeTablesAndFootnotesArePrintedNotReplacedByAPlaceholder() throws {
        // ImageRenderer cannot draw a scroll view, a button or a link control and shows a "no entry" symbol instead.
        let document = MarkdownParser.parse("```swift\nlet answer = 42\n```\n\n| Left | Right |\n|---|---|\n| alpha | beta |\n\nA note[^1].\n\n[^1]: The note text.\n\n[![badge](pic.png)](https://example.com)")
        let margins = NSEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        let data = try #require(PDFExporter.export(document, theme: theme, baseURL: nil, paperSize: CGSize(width: 612, height: 792), margins: margins))
        let text = PDFDocument(data: data)?.string ?? ""
        for expected in ["answer", "alpha", "beta", "The note text"] { #expect(text.contains(expected), "\(expected) is missing from the PDF: \(text)") }
    }
}
