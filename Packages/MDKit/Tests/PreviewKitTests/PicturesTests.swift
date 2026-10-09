import AppKit
import Foundation
import MarkdownCore
import SwiftUI
import Testing
import WebRenderKit
@testable import PreviewKit

/// A renderer that answers from a closure and remembers what it was asked.
@MainActor
final class FakeRenderer: WebRendering {
    private(set) var requests: [RenderRequest] = []
    var answer: (RenderRequest) throws -> RenderedImage = { _ in RenderedImage(pdf: samplePDF(), size: CGSize(width: 40, height: 20), baseline: 4) }

    func render(_ request: RenderRequest) async throws -> RenderedImage {
        requests.append(request)
        return try answer(request)
    }
}

func samplePDF(width: Double = 40, height: Double = 20, color: NSColor = .systemBlue) -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: width, height: height)
    guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
    context.beginPDFPage(nil)
    context.setFillColor(color.cgColor)
    context.fill(box)
    context.endPDFPage()
    context.closePDF()
    return data as Data
}

@Suite struct DiagramLanguageTests {
    @Test func knowsTheDiagramFences() {
        #expect(DiagramLanguage.kind(of: "mermaid") == .mermaid)
        #expect(DiagramLanguage.kind(of: "Mermaid") == .mermaid)
        #expect(DiagramLanguage.kind(of: "dot") == .graphviz)
        #expect(DiagramLanguage.kind(of: "GRAPHVIZ") == .graphviz)
        #expect(DiagramLanguage.kind(of: "swift") == nil)
        #expect(DiagramLanguage.kind(of: "mermaidx") == nil)
        #expect(DiagramLanguage.kind(of: nil) == nil)
    }
}

@Suite struct RenderErrorSummaryTests {
    @Test func aParseErrorKeepsItsFirstAndLastLine() {
        let message = "Error: Parse error on line 3:\n...lowchart LR  A -->\n---------------------^\nExpecting 'AMP', 'COLON', 'PIPE', got 'EOF'"
        let summary = RenderError.syntax(message).summary
        #expect(summary.hasPrefix("Parse error on line 3:"))
        #expect(summary.hasSuffix("got 'EOF'"))
        #expect(!summary.contains("\n"))
        #expect(!summary.contains("Error: "))
    }

    @Test func aLongExpectationListIsCut() {
        let message = "Parse error on line 2:\n^\nExpecting " + (0..<100).map { "'TOKEN\($0)'" }.joined(separator: ", ")
        #expect(RenderError.syntax(message).summary.count < 200)
    }

    @Test func anUnknownDiagramTypeIsExplained() {
        let summary = RenderError.syntax("UnknownDiagramError: No diagram type detected matching given configuration for text: hello").summary
        #expect(summary.contains("Unknown diagram type"))
        #expect(summary.contains("flowchart"))
    }

    @Test func oneLineMessagesPassThrough() {
        #expect(RenderError.syntax("ParseError: KaTeX parse error: Undefined control sequence: \\foo").summary == "ParseError: KaTeX parse error: Undefined control sequence: \\foo")
        #expect(RenderError.syntax("").summary == "The source could not be drawn.")
    }

    @Test func otherErrorsHaveFriendlyText() {
        #expect(RenderError.timeout.summary.contains("too long"))
        #expect(RenderError.crashed.summary.contains("stopped"))
        #expect(RenderError.unavailable("shell.html is missing").summary.contains("shell.html is missing"))
    }

    @Test func theFullMessageStaysAvailable() {
        #expect(RenderError.syntax("line one\nline two").fullMessage == "line one\nline two")
    }
}

@Suite struct HTMLStyleSheetTests {
    @Test func usesTheThemeColoursOfTheAppearance() {
        let theme = PreviewTheme.github
        let light = theme.htmlStyleSheet(for: .light)
        let dark = theme.htmlStyleSheet(for: .dark)
        #expect(light.contains(theme.link.light) && !light.contains(theme.link.dark))
        #expect(dark.contains(theme.link.dark) && !dark.contains(theme.link.light))
        #expect(light.contains(theme.border.light))
        #expect(light.contains("table { border-collapse: collapse; }"))
    }

    @Test func sizesHeadingsLikeThePreview() {
        let css = PreviewTheme.github.htmlStyleSheet(for: .light)
        #expect(css.contains("h1 { font-size: 2.000em"))
        #expect(css.contains("h3 { font-size: 1.250em"))
    }
}

@Suite struct HTMLImageInlinerTests {
    private func folder(_ files: [String: Data]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("inline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: url.appendingPathComponent(name)) }
        return url
    }

    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
    private static let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"/>"#.utf8)

    @Test func replacesRelativeSourcesWithDataURIs() async throws {
        let dir = try folder(["a.png": Self.png, "b.svg": Self.svg])
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = await HTMLImageInliner.inline(#"<p><img src="a.png" width="10"> and <img alt="x" src='b.svg'></p>"#, baseURL: dir)
        #expect(result.contains("src=\"data:image/png;base64,\(Self.png.base64EncodedString())\""))
        #expect(result.contains("src='data:image/svg+xml;base64,\(Self.svg.base64EncodedString())'"))
        #expect(result.contains(#"width="10""#), "other attributes stay")
        #expect(!result.contains("a.png"))
    }

    @Test func leavesWhatItCannotOrShouldNotInline() async throws {
        let dir = try folder(["notes.png": Data("just text".utf8)])
        defer { try? FileManager.default.removeItem(at: dir) }
        let html = #"<img src="missing.png"><img src="data:image/gif;base64,R0lGOD"><img src="notes.png"><img src="ftp://example.com/x.png">"#
        #expect(await HTMLImageInliner.inline(html, baseURL: dir) == html, "missing files, data: URIs, files that are not pictures and odd schemes stay as written")
    }

    @Test func htmlWithoutPicturesIsReturnedAsIs() async {
        let html = "<table><tr><td>1</td></tr></table>"
        #expect(await HTMLImageInliner.inline(html, baseURL: nil) == html)
    }

    @Test func aSourceUsedTwiceIsReadOnce() async throws {
        let dir = try folder(["a.png": Self.png])
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = await HTMLImageInliner.inline(#"<img src="a.png"><img src="a.png">"#, baseURL: dir)
        #expect(result.components(separatedBy: "data:image/png").count == 3)
    }

    @Test func stopsAtTheImageLimit() async throws {
        var files: [String: Data] = [:]
        var html = ""
        for index in 0..<(HTMLImageInliner.maxImages + 3) {
            files["p\(index).png"] = Self.png + Data([UInt8(index)])
            html += #"<img src="p\#(index).png">"#
        }
        let dir = try folder(files)
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = await HTMLImageInliner.inline(html, baseURL: dir)
        #expect(result.components(separatedBy: "data:image/png").count - 1 == HTMLImageInliner.maxImages)
    }

    @Test func skipsHugeFiles() async throws {
        let dir = try folder(["big.png": Self.png + Data(count: HTMLImageInliner.maxBytesPerImage)])
        defer { try? FileManager.default.removeItem(at: dir) }
        let html = #"<img src="big.png">"#
        #expect(await HTMLImageInliner.inline(html, baseURL: dir) == html)
    }

    @Test func unsavedDocumentsCannotResolveRelativePaths() async {
        let html = #"<img src="a.png">"#
        #expect(await HTMLImageInliner.inline(html, baseURL: nil) == html)
    }

    @Test(arguments: [
        ([0x89, 0x50, 0x4E, 0x47, 0, 0], "image/png"), ([0xFF, 0xD8, 0xFF, 0xE0], "image/jpeg"), (Array("GIF89a".utf8).map { $0 }, "image/gif"),
        (Array("BM....".utf8).map { $0 }, "image/bmp"),
    ] as [([UInt8], String)])
    func recognisesPictureFormatsByTheirFirstBytes(bytes: [UInt8], mime: String) {
        #expect(HTMLImageInliner.mimeType(of: Data(bytes)) == mime)
    }

    @Test func recognisesWebPAndSVGAndRejectsTheRest() {
        #expect(HTMLImageInliner.mimeType(of: Data(Array("RIFF\0\0\0\0WEBPVP8 ".utf8))) == "image/webp")
        #expect(HTMLImageInliner.mimeType(of: Data("<?xml version=\"1.0\"?><svg></svg>".utf8)) == "image/svg+xml")
        #expect(HTMLImageInliner.mimeType(of: Data("hello world".utf8)) == nil)
        #expect(HTMLImageInliner.mimeType(of: Data()) == nil)
    }
}

@MainActor
@Suite struct FormulaFallbackTests {
    @Test func listsOnlyFormulasSwiftMathRejects() {
        let inlines: [Inline] = [.text("a "), .math(latex: "x^2", display: false), .math(latex: "\\operatorname{lcm}(a,b)", display: false),
                                 .math(latex: "\\operatorname{lcm}(a,b)", display: false)]
        let failing = InlineRenderer.failingFormulas(inlines, fontSize: 16, dark: true)
        #expect(failing == [FormulaKey(latex: "\\operatorname{lcm}(a,b)", display: false, fontSize: 16, dark: true)], "once, with the size and appearance that decide how it is drawn")
    }

    @Test func formulasInsideEmphasisAreLeftToTheSourceFallback() {
        let inlines: [Inline] = [.emphasis([.math(latex: "\\operatorname{x}", display: false)])]
        #expect(InlineRenderer.failingFormulas(inlines, fontSize: 16, dark: false).isEmpty)
    }

    @Test func tooManyFormulasAreNotSentToTheRenderer() {
        let many = (0...InlineRenderer.maxTypesetFormulas).map { Inline.math(latex: "\\operatorname{f\($0)}", display: false) }
        #expect(InlineRenderer.failingFormulas(many, fontSize: 16, dark: false).isEmpty)
    }

    @Test func picturesArriveWithTheirBaseline() async throws {
        let fake = FakeRenderer()
        let pictures = FormulaPictures()
        let key = FormulaKey(latex: "\\operatorname{lcm}", display: false, fontSize: 18, dark: true)
        await pictures.load([key], using: fake, foreground: "#e6edf3", background: "#0d1117")
        let request = try #require(fake.requests.first)
        #expect(request.kind == .katex(display: false))
        #expect(request.source == key.latex)
        #expect(request.appearance == .dark && request.foreground == "#e6edf3" && request.background == "#0d1117" && request.fontSize == 18)
        #expect(pictures.loaded[key]?.baseline == 4)
    }

    @Test func eachFormulaIsRequestedOnce() async {
        let fake = FakeRenderer()
        let pictures = FormulaPictures()
        let key = FormulaKey(latex: "\\operatorname{a}", display: true, fontSize: 18, dark: false)
        await pictures.load([key, key], using: fake, foreground: "#000", background: "#fff")
        await pictures.load([key], using: fake, foreground: "#000", background: "#fff")
        #expect(fake.requests.count == 1)
    }

    @Test func aFailureLeavesTheSourceFallbackInPlace() async {
        let fake = FakeRenderer()
        fake.answer = { _ in throw RenderError.syntax("nope") }
        let pictures = FormulaPictures()
        await pictures.load([FormulaKey(latex: "\\bad", display: false, fontSize: 16, dark: false)], using: fake, foreground: "#000", background: "#fff")
        #expect(pictures.loaded.isEmpty)
    }
}


@MainActor
@Suite struct PictureLoaderTests {
    private func request(_ source: String = "flowchart LR\n  A --> B") -> RenderRequest {
        RenderRequest(kind: .mermaid, source: source)
    }

    @Test func startsLoadingAndEndsWithThePicture() async {
        let loader = PictureLoader()
        guard case .loading = loader.phase else { Issue.record("should start loading"); return }
        let fake = FakeRenderer()
        await loader.load(request(), using: fake)
        guard case .loaded(let image) = loader.phase else { Issue.record("expected a picture"); return }
        #expect(image.size == NSSize(width: 40, height: 20))
        #expect(fake.requests.count == 1)
    }

    @Test func aFailureIsKeptAsTheError() async {
        let loader = PictureLoader()
        let fake = FakeRenderer()
        fake.answer = { _ in throw RenderError.syntax("Parse error on line 2") }
        await loader.load(request(), using: fake)
        guard case .failed(let error) = loader.phase else { Issue.record("expected a failure"); return }
        #expect(error == .syntax("Parse error on line 2"))
    }

    @Test func aPictureThatCannotBeReadIsAFailureNotACrash() async {
        let loader = PictureLoader()
        let fake = FakeRenderer()
        fake.answer = { _ in RenderedImage(pdf: Data("not a pdf".utf8), size: CGSize(width: 10, height: 10)) }
        await loader.load(request(), using: fake)
        guard case .failed(let error) = loader.phase else { Issue.record("expected a failure"); return }
        #expect(error == .unavailable("The picture could not be read"))
    }

    @Test func withoutARendererItFails() async {
        let loader = PictureLoader()
        await loader.load(request(), using: nil)
        guard case .failed(.unavailable) = loader.phase else { Issue.record("expected unavailable"); return }
    }

    @Test func theOldPictureStaysUntilTheNewOneArrives() async throws {
        let loader = PictureLoader()
        let fake = FakeRenderer()
        await loader.load(request("flowchart LR\n  A --> B"), using: fake)
        fake.answer = { _ in
            RenderedImage(pdf: samplePDF(width: 80, height: 30), size: CGSize(width: 80, height: 30))
        }
        // The second render takes a while: the renderer answers only after the delay.
        let slow = SlowRenderer(delay: .milliseconds(300), pdf: samplePDF(width: 80, height: 30))
        let pending = Task { await loader.load(request("flowchart LR\n  C --> D"), using: slow) }
        try await Task.sleep(for: .milliseconds(100))
        guard case .loaded(let during) = loader.phase else { Issue.record("the old picture should still be showing"); return }
        #expect(during.size == NSSize(width: 40, height: 20))
        await pending.value
        guard case .loaded(let after) = loader.phase else { Issue.record("expected the new picture"); return }
        #expect(after.size == NSSize(width: 80, height: 30))
    }

    @Test func aCancelledLoadChangesNothing() async throws {
        let loader = PictureLoader()
        let slow = SlowRenderer(delay: .milliseconds(300), pdf: samplePDF())
        let task = Task { await loader.load(request(), using: slow) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value
        guard case .loading = loader.phase else { Issue.record("a view that went away must not leave a picture behind"); return }
    }

    @Test func debouncingMeansACancelledLoadNeverAsks() async throws {
        let loader = PictureLoader()
        let fake = FakeRenderer()
        let task = Task { await loader.load(request(), using: fake, debounce: .milliseconds(300)) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value
        try await Task.sleep(for: .milliseconds(400))
        #expect(fake.requests.isEmpty, "dragging a window edge must not queue a render per step")
    }
}

/// Answers after a delay.
@MainActor
final class SlowRenderer: WebRendering {
    let delay: Duration
    let pdf: Data
    init(delay: Duration, pdf: Data) {
        self.delay = delay
        self.pdf = pdf
    }

    func render(_ request: RenderRequest) async throws -> RenderedImage {
        try await Task.sleep(for: delay)
        return RenderedImage(pdf: pdf, size: CGSize(width: 1, height: 1))
    }
}

// MARK: - The views, in a real (off-screen) window

@MainActor
private final class OffscreenWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
private func showPreview(_ markdown: String, renderer: (any WebRendering)?, dark: Bool = false, baseURL: URL? = nil, width: Double = 760) -> NSWindow {
    _ = NSApplication.shared
    let rendered = MarkdownPipeline.render(markdown, options: .default)
    let host = NSHostingController(rootView: MarkdownPreview(rendered: rendered, baseURL: baseURL, webRenderer: renderer))
    let window = OffscreenWindow(contentViewController: host)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.styleMask = [.titled, .resizable]
    window.setFrame(NSRect(x: -20000, y: -20000, width: width, height: 900), display: false)
    window.orderFrontRegardless()
    // The window is off screen, so its first layout would wait for a display cycle that a busy main thread (other suites
    // starting WebKit) can delay; lay it out now so the width and the pictures do not depend on that timing.
    window.contentView?.layoutSubtreeIfNeeded()
    return window
}

/// Waits for `condition`, which is checked every 30 ms. The ceiling is generous because a passing test never waits for it.
@MainActor
private func waitFor(_ what: String, seconds: Double = 15, _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while !condition() {
        guard ContinuousClock.now < deadline else { Issue.record("timed out waiting for \(what)"); return }
        try? await Task.sleep(for: .milliseconds(30))
    }
}

/// What a window's content looks like, counted by hue: the fake renderer's picture is a solid blue, the
/// theme's error colour is red, so counting them tells what was actually drawn.
@MainActor
private func inkCounts(in window: NSWindow) -> (blue: Int, red: Int) {
    guard let frameView = window.contentView?.superview, let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return (0, 0) }
    frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return (0, 0) }
    var blue = 0, red = 0
    for y in 0..<bitmap.pixelsHigh {
        let row = data + y * bitmap.bytesPerRow
        for x in 0..<bitmap.pixelsWide {
            let r = Int(row[x * bitmap.samplesPerPixel]), g = Int(row[x * bitmap.samplesPerPixel + 1]), b = Int(row[x * bitmap.samplesPerPixel + 2])
            if b > 220, r < 140, g > 100, g < 200 { blue += 1 }
            if r > 170, g < 90, b < 110 { red += 1 }
        }
    }
    return (blue, red)
}

@MainActor
@Suite(.requiresWindowServer) struct PictureViewTests {
    @Test func aMermaidFenceAsksForAMermaidPictureInTheThemeColours() async {
        let fake = FakeRenderer()
        let theme = PreviewTheme.github
        let window = showPreview("```mermaid\nflowchart LR\n  A --> B\n```", renderer: fake, dark: true)
        defer { window.orderOut(nil) }
        await waitFor("the diagram request") { !fake.requests.isEmpty }
        let request = fake.requests.first
        #expect(request?.kind == .mermaid)
        #expect(request?.source == "flowchart LR\n  A --> B")
        #expect(request?.appearance == .dark)
        #expect(request?.foreground == theme.text.dark)
        #expect(request?.background == theme.background.dark)
        #expect(request?.fontSize == theme.bodyFontSize)
    }

    @Test func lightAppearanceAsksForLightColours() async {
        let fake = FakeRenderer()
        let window = showPreview("```mermaid\nflowchart LR\n  A --> B\n```", renderer: fake, dark: false)
        defer { window.orderOut(nil) }
        await waitFor("the diagram request") { !fake.requests.isEmpty }
        #expect(fake.requests.first?.appearance == .light)
        #expect(fake.requests.first?.foreground == PreviewTheme.github.text.light)
    }

    @Test func dotAndGraphvizFencesAskForGraphviz() async {
        let fake = FakeRenderer()
        let window = showPreview("```dot\ndigraph { a -> b }\n```\n\n```graphviz\ndigraph { c -> d }\n```", renderer: fake)
        defer { window.orderOut(nil) }
        await waitFor("two requests") { fake.requests.count >= 2 }
        #expect(fake.requests.map(\.kind) == [.graphviz, .graphviz])
    }

    @Test func aDiagramInsideAQuoteIsDrawnToo() async {
        let fake = FakeRenderer()
        let window = showPreview("> quoted\n>\n> ```mermaid\n> flowchart LR\n>   A --> B\n> ```", renderer: fake)
        defer { window.orderOut(nil) }
        await waitFor("the diagram request") { !fake.requests.isEmpty }
        #expect(fake.requests.first?.kind == .mermaid)
    }

    @Test func aLoadedPictureIsDrawn() async {
        let fake = FakeRenderer()   // answers with a solid blue picture
        let window = showPreview("```mermaid\nflowchart LR\n  A --> B\n```", renderer: fake)
        defer { window.orderOut(nil) }
        await waitFor("the diagram request") { !fake.requests.isEmpty }
        try? await Task.sleep(for: .milliseconds(500))
        #expect(inkCounts(in: window).blue > 1_000, "the 40 × 20 picture should be on screen")
    }

    @Test func aFailedDiagramDrawsNoPictureButKeepsTheSource() async {
        let fake = FakeRenderer()
        fake.answer = { _ in throw RenderError.syntax("Parse error on line 2") }
        let window = showPreview("```mermaid\nflowchart LR\n  A -->\n```", renderer: fake)
        defer { window.orderOut(nil) }
        await waitFor("the request") { !fake.requests.isEmpty }
        try? await Task.sleep(for: .milliseconds(500))
        let ink = inkCounts(in: window)
        #expect(ink.blue == 0)
        #expect(ink.red > 20, "the message is drawn in the theme's error colour")
    }

    @Test func withoutARendererThePreviewStillDrawsEverything() async {
        let window = showPreview("# Title\n\n```mermaid\nflowchart LR\n  A --> B\n```\n\n$\\operatorname{x}$\n\n<table><tr><td>t</td></tr></table>", renderer: nil)
        defer { window.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(500))
        #expect(inkCounts(in: window).red > 20, "the formula's source shows in red, as before")
    }

    @Test func aFailedSnapshotFallsBackToTheSource() async {
        let fake = FakeRenderer()
        fake.answer = { _ in throw RenderError.timeout }
        let window = showPreview("<table><tr><td>fallback text</td></tr></table>", renderer: fake)
        defer { window.orderOut(nil) }
        await waitFor("the request") { !fake.requests.isEmpty }
        try? await Task.sleep(for: .milliseconds(500))
        #expect(inkCounts(in: window).blue == 0)
        #expect(fake.requests.count == 1)
    }

    @Test func aWhitespaceOnlyDiagramIsNotSent() async {
        let fake = FakeRenderer()
        let window = showPreview("```mermaid\n\n```", renderer: fake)
        defer { window.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(500))
        #expect(fake.requests.isEmpty)
    }

    @Test func onlyFormulasSwiftMathRejectsGoToKaTeX() async {
        let fake = FakeRenderer()
        let window = showPreview("Native $x^2$ and fallback $\\operatorname{lcm}(a,b)$.\n\n$$\n\\int_0^1 x\\,dx\n$$\n\n$$\n\\operatorname{sin} x\n$$", renderer: fake)
        defer { window.orderOut(nil) }
        await waitFor("two katex requests") { fake.requests.count >= 2 }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(Set(fake.requests.map(\.source)) == ["\\operatorname{lcm}(a,b)", "\\operatorname{sin} x"])
        #expect(fake.requests.contains { $0.kind == .katex(display: false) })
        #expect(fake.requests.contains { $0.kind == .katex(display: true) })
    }

    @Test func rawHTMLBlocksAskForASnapshotAtAStableWidth() async throws {
        let fake = FakeRenderer()
        let window = showPreview("<table><tr><td>cell</td></tr></table>", renderer: fake, width: 790)
        defer { window.orderOut(nil) }
        await waitFor("the snapshot request") { !fake.requests.isEmpty }
        let request = try #require(fake.requests.first)
        #expect(request.kind == .html)
        #expect(request.source.contains("<table>"))
        #expect(request.width.truncatingRemainder(dividingBy: 40) == 0, "\(request.width): snapshots are laid out at a multiple of 40 pt")
        #expect(request.style.contains("border-collapse"))
        #expect(request.foreground == PreviewTheme.github.text.light)
    }

    @Test func imagesInAnHTMLBlockTravelAsDataURIs() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("html-img-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9]).write(to: dir.appendingPathComponent("logo.png"))
        let fake = FakeRenderer()
        let window = showPreview("<table><tr><td><img src=\"logo.png\" width=\"20\"></td></tr></table>", renderer: fake, baseURL: dir)
        defer { window.orderOut(nil) }
        await waitFor("the snapshot request") { !fake.requests.isEmpty }
        #expect(fake.requests.first?.source.contains("data:image/png;base64,") == true)
        #expect(fake.requests.first?.source.contains("logo.png") == false)
    }

    @Test func editingElsewhereDoesNotAskAgain() async {
        let fake = FakeRenderer()
        let diagram = "```mermaid\nflowchart LR\n  A --> B\n```"
        let rendered = MarkdownPipeline.render("intro\n\n" + diagram, options: .default)
        let host = NSHostingController(rootView: MarkdownPreview(rendered: rendered, baseURL: nil, webRenderer: fake))
        let window = OffscreenWindow(contentViewController: host)
        window.setFrame(NSRect(x: -20000, y: -20000, width: 700, height: 600), display: false)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        await waitFor("the first request") { !fake.requests.isEmpty }
        host.rootView = MarkdownPreview(rendered: MarkdownPipeline.render("an edited intro\n\n" + diagram, options: .default), baseURL: nil, webRenderer: fake)
        try? await Task.sleep(for: .milliseconds(500))
        #expect(fake.requests.count == 1, "the diagram's request did not change, so SwiftUI does not ask again")
    }
}
