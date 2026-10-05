import AppKit
import Foundation
import Testing
@testable import WebRenderKit

/// The real thing: hidden web views, the vendored libraries, PDFs out. They need a window server.
@MainActor
@Suite(.requiresWindowServer) struct WebKitRenderingTests {
    private let renderer = WebRenderer()

    private static let flowchart = "flowchart LR\n  A[Write Markdown] --> B{Preview}\n  B -->|looks right| C[Ship it]\n  B -->|nope| A"

    @Test func aMermaidFlowchartBecomesAVectorPicture() async throws {
        _ = NSApplication.shared
        let image = try await renderer.render(RenderRequest(kind: .mermaid, source: Self.flowchart))
        #expect(PictureProbe.isPDF(image))
        #expect(image.size.width > 150 && image.size.height > 40)
        #expect(PictureProbe.ink(image) > 0.01, "something was drawn")
        #expect(image.baseline == nil)
    }

    @Test(arguments: [
        "sequenceDiagram\n  Alice->>Bob: Hello\n  Bob-->>Alice: Hi",
        "pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85",
        "classDiagram\n  Animal <|-- Duck\n  Animal : +int age",
        "stateDiagram-v2\n  [*] --> Still\n  Still --> Moving",
        "erDiagram\n  CUSTOMER ||--o{ ORDER : places",
        "gantt\n  title A plan\n  dateFormat YYYY-MM-DD\n  section S\n  Task :a1, 2026-01-01, 3d",
        "journey\n  title Day\n  section Work\n    Code: 5: Me",
        "mindmap\n  root((MDSyndrome))\n    Editor\n    Preview",
    ])
    func otherMermaidDiagramTypesRender(source: String) async throws {
        let image = try await renderer.render(RenderRequest(kind: .mermaid, source: source))
        #expect(PictureProbe.isPDF(image))
        #expect(image.size.width > 50 && image.size.height > 30, "\(source.prefix(20))")
        #expect(PictureProbe.ink(image) > 0.005)
    }

    @Test func graphvizDrawsADigraph() async throws {
        let image = try await renderer.render(RenderRequest(kind: .graphviz, source: "digraph G { rankdir=LR; a -> b -> c; a -> c [label=\"shortcut\"]; b [shape=box, style=filled, fillcolor=lightyellow] }"))
        #expect(PictureProbe.isPDF(image))
        #expect(image.size.width > 150 && image.size.height > 50)
        #expect(PictureProbe.ink(image) > 0.02)
    }

    @Test func graphvizAcceptsUndirectedGraphsAndSubgraphs() async throws {
        let image = try await renderer.render(RenderRequest(kind: .graphviz, source: "graph { subgraph cluster_0 { label=\"group\"; a -- b } b -- c }"))
        #expect(image.size.height > 50)
    }

    @Test func katexTypesetsWhatSwiftMathCannot() async throws {
        let block = try await renderer.render(RenderRequest(kind: .katex(display: true), source: "\\begin{aligned} a &= b + c \\\\ \\operatorname{sin}^2 x + \\cos^2 x &= 1 \\end{aligned}", fontSize: 18))
        #expect(PictureProbe.isPDF(block))
        #expect(block.size.height > 40)
        #expect(PictureProbe.ink(block) > 0.01)
        // Display mode has no outer margin (the preview adds its own spacing).
        #expect(block.size.height < 120)
    }

    @Test func inlineFormulasComeWithABaseline() async throws {
        let withDescender = try await renderer.render(RenderRequest(kind: .katex(display: false), source: "\\operatorname{lcm}(a,b)=\\frac{ab}{\\gcd(a,b)}", fontSize: 16))
        let flat = try await renderer.render(RenderRequest(kind: .katex(display: false), source: "x", fontSize: 16))
        let baseline = try #require(withDescender.baseline)
        #expect(baseline > 0 && baseline < withDescender.size.height)
        #expect(try #require(flat.baseline) < baseline, "a fraction hangs lower than a letter x")
    }

    @Test func aTableInHTMLIsLaidOutAtTheRequestedWidth() async throws {
        let html = "<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table><p>after</p>"
        let narrow = try await renderer.render(RenderRequest(kind: .html, source: html, fontSize: 16, width: 240, style: "td, th { border: 1px solid #888; padding: 4px 8px }"))
        let wide = try await renderer.render(RenderRequest(kind: .html, source: "<p>" + String(repeating: "word ", count: 80) + "</p>", fontSize: 16, width: 640))
        let squeezed = try await renderer.render(RenderRequest(kind: .html, source: "<p>" + String(repeating: "word ", count: 80) + "</p>", fontSize: 16, width: 320))
        #expect(narrow.size.width >= 240 && narrow.size.width < 300)
        #expect(PictureProbe.ink(narrow) > 0.01)
        #expect(squeezed.size.height > wide.size.height * 1.5, "narrower text wraps onto more lines")
    }

    @Test func syntaxErrorsCarryTheLibrariesMessage() async {
        await #expect {
            try await renderer.render(RenderRequest(kind: .mermaid, source: "flowchart LR\n  A -->"))
        } throws: { error in
            guard case RenderError.syntax(let message) = error else { return false }
            return message.contains("Parse error")
        }
        await #expect {
            try await renderer.render(RenderRequest(kind: .mermaid, source: "this is not a diagram"))
        } throws: { error in
            guard case RenderError.syntax(let message) = error else { return false }
            return message.contains("UnknownDiagramError")
        }
        await #expect {
            try await renderer.render(RenderRequest(kind: .graphviz, source: "digraph { a -> }"))
        } throws: { error in
            guard case RenderError.syntax(let message) = error else { return false }
            return message.lowercased().contains("syntax error")
        }
        await #expect {
            try await renderer.render(RenderRequest(kind: .katex(display: false), source: "\\frac{1}{"))
        } throws: { error in
            guard case RenderError.syntax(let message) = error else { return false }
            return message.contains("KaTeX parse error")
        }
    }

    @Test func anErrorDoesNotSpoilTheNextRender() async throws {
        await #expect(throws: RenderError.self) { try await renderer.render(RenderRequest(kind: .mermaid, source: "flowchart LR\n  A -->")) }
        let image = try await renderer.render(RenderRequest(kind: .mermaid, source: Self.flowchart))
        #expect(PictureProbe.isPDF(image))
    }

    @Test func darkAppearanceDrawsADifferentPicture() async throws {
        let light = try await renderer.render(RenderRequest(kind: .mermaid, source: Self.flowchart, appearance: .light))
        let dark = try await renderer.render(RenderRequest(kind: .mermaid, source: Self.flowchart, appearance: .dark, foreground: "#e6edf3"))
        #expect(light.pdf != dark.pdf)
        #expect(light.size == dark.size)
    }

    @Test func graphvizFollowsTheForegroundColourInDarkMode() async throws {
        let source = "digraph { a -> b }"
        let light = try await renderer.render(RenderRequest(kind: .graphviz, source: source, appearance: .light))
        let dark = try await renderer.render(RenderRequest(kind: .graphviz, source: source, appearance: .dark, foreground: "#e6edf3"))
        #expect(light.pdf != dark.pdf)
    }

    @Test(arguments: [
        RenderKind.mermaid, .graphviz, .katex(display: true), .katex(display: false), .html,
    ])
    func picturesAreTransparentSoTheyShowWhateverIsBehindThem(kind: RenderKind) async throws {
        let source: String
        switch kind {
        case .mermaid: source = "flowchart LR\n  A --> B"
        case .graphviz: source = "digraph { a -> b }"
        case .katex: source = "x^2"
        case .html: source = "<p>hello</p>"
        }
        let image = try await renderer.render(RenderRequest(kind: kind, source: source, appearance: .dark, foreground: "#e6edf3", background: "#0d1117"))
        let corner = try #require(PictureProbe.pixel(image))
        #expect(corner.a == 0, "WebKit paints white into a PDF unless its page background is switched off")
    }

    @Test func withoutTheTransparencySwitchTheRequestedBackgroundIsPainted() async throws {
        let host = try await ScriptHost.start(transparent: false)
        defer { host.invalidate() }
        let image = try await host.render(RenderRequest(kind: .mermaid, source: "flowchart LR\n  A --> B", appearance: .dark, foreground: "#e6edf3", background: "#0d1117"))
        let corner = try #require(PictureProbe.pixel(image))
        #expect(corner.a > 0.99)
        #expect(abs(corner.r - 0x0d / 255.0) < 0.03 && abs(corner.g - 0x11 / 255.0) < 0.03 && abs(corner.b - 0x17 / 255.0) < 0.03, "\(corner)")

        let snapshot = try await SnapshotHost.start(transparent: false)
        defer { snapshot.invalidate() }
        let html = try await snapshot.render(RenderRequest(kind: .html, source: "<p>hi</p>", appearance: .dark, foreground: "#e6edf3", background: "#0d1117"))
        let htmlCorner = try #require(PictureProbe.pixel(html))
        #expect(htmlCorner.a > 0.99 && htmlCorner.r < 0.1)
    }

    @Test func hugeDiagramsAreClamped() async throws {
        let chain = (0..<500).map { "n\($0) -> n\($0 + 1)" }.joined(separator: "; ")
        let image = try await renderer.render(RenderRequest(kind: .graphviz, source: "digraph { rankdir=LR; \(chain) }"))
        #expect(image.size.width <= 8_000 && image.size.height <= 8_000)
        #expect(PictureProbe.isPDF(image))
    }

    @Test func oddCharactersInTheSourceAreJustText() async throws {
        // Mermaid's own grammar rejects a raw < in a label, so the closing tag is written as its entity codes.
        let tricky = "A[\"backtick ` dollar ${x} 'single' #lt;/script#gt; 日本語 😀\"] --> B"
        let image = try await renderer.render(RenderRequest(kind: .mermaid, source: "flowchart LR\n  \(tricky)"))
        #expect(PictureProbe.ink(image) > 0.005)
        let formula = try await renderer.render(RenderRequest(kind: .katex(display: false), source: "\\text{日本語 😀 `y` 'z' </script>}"))
        #expect(formula.size.width > 20)
    }

    @Test func manyDifferentDiagramsInARowStayQuick() async throws {
        _ = try await renderer.render(RenderRequest(kind: .mermaid, source: "flowchart LR\n  warm --> up"))   // loads the library
        let start = ContinuousClock.now
        for index in 0..<20 {
            _ = try await renderer.render(RenderRequest(kind: .mermaid, source: "flowchart LR\n  N\(index) --> M\(index)"))
        }
        #expect(ContinuousClock.now - start < .budget(10), "20 small diagrams took \(ContinuousClock.now - start)")
    }

    @Test func oneHostServesEveryScriptedKind() async throws {
        _ = try await renderer.render(RenderRequest(kind: .mermaid, source: "flowchart LR\n  A --> B"))
        _ = try await renderer.render(RenderRequest(kind: .graphviz, source: "digraph { a -> b }"))
        _ = try await renderer.render(RenderRequest(kind: .katex(display: false), source: "x"))
        #expect(renderer.hostsStarted == 1)
        _ = try await renderer.render(RenderRequest(kind: .html, source: "<p>x</p>"))
        #expect(renderer.hostsStarted == 2)
    }
}
