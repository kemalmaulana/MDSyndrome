import AppKit
import MarkdownCore
import SwiftUI
import Testing
@testable import PreviewKit

@MainActor
@Suite struct MathRendererTests {
    @Test func rendersCommonLaTeXWithABaseline() throws {
        for latex in ["x^2", "\\frac{a}{b}", "\\int_0^1 x^2 \\, dx", "\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}", "\\sqrt{x}", "\\mathbb{R}"] {
            guard case .success(let math) = MathRenderer.render(latex, fontSize: 16, display: false) else {
                Issue.record("failed to render \(latex)")
                continue
            }
            #expect(math.image.size.width > 0 && math.image.size.height > 0, "\(latex)")
            #expect(math.descent >= 0, "\(latex)")
            #expect(math.image.isTemplate, "math takes the surrounding text colour")
        }
    }

    @Test func fractionsSitBelowTheBaseline() throws {
        guard case .success(let flat) = MathRenderer.render("x", fontSize: 16, display: false),
              case .success(let fraction) = MathRenderer.render("\\frac{a}{b}", fontSize: 16, display: false) else {
            Issue.record("render failed")
            return
        }
        #expect(fraction.descent > flat.descent + 2)
    }

    @Test func syntaxErrorsAreReportedNotCrashing() {
        #expect(MathRenderer.render("\\frac{", fontSize: 16, display: true) == .failure(.syntax("Missing closing brace")))
        guard case .failure(.syntax(let message)) = MathRenderer.render("\\nosuchcommand", fontSize: 16, display: true) else {
            Issue.record("expected a syntax error")
            return
        }
        #expect(message.contains("nosuchcommand"))
    }

    @Test func resultsAreCached() throws {
        guard case .success(let first) = MathRenderer.render("y^3", fontSize: 14, display: false),
              case .success(let second) = MathRenderer.render("y^3", fontSize: 14, display: false) else {
            Issue.record("render failed")
            return
        }
        #expect(first.image === second.image)
    }
}

extension Result<RenderedMath, MathRenderError> {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.failure(let a), .failure(let b)): a == b
        default: false
        }
    }
}

@MainActor
@Suite struct SyntaxStylerTests {
    @Test func colorsTokensAndKeepsTheText() {
        let styled = SyntaxStyler.attributed("let x = 1 // n", language: "swift", theme: .github)
        #expect(String(styled.characters) == "let x = 1 // n")
        let colored = styled.runs.filter { $0.foregroundColor != nil }.map { String(styled[$0.range].characters) }
        #expect(colored == ["let", "1", "// n"])
    }

    @Test func unknownLanguageIsUncolored() {
        let styled = SyntaxStyler.attributed("plain", language: "klingon", theme: .github)
        #expect(styled.runs.allSatisfy { $0.foregroundColor == nil })
    }
}

@Suite struct NewInlineRenderingTests {
    private func render(_ inlines: [Inline]) -> AttributedString { InlineRenderer.attributedString(inlines, theme: .github) }

    @Test func highlightUnderlineSuperSubscriptAndKeyboard() throws {
        #expect(try #require(render([.highlight([.text("m")])]).runs.first).backgroundColor != nil)
        #expect(try #require(render([.underline([.text("u")])]).runs.first).underlineStyle == .single)
        #expect((try #require(render([.superscript([.text("2")])]).runs.first).baselineOffset ?? 0) > 0)
        #expect((try #require(render([.subscript([.text("2")])]).runs.first).baselineOffset ?? 0) < 0)
        let key = render([.keyboard([.text("⌘K")])])
        #expect(String(key.characters) == "\u{2009}⌘K\u{2009}")
        #expect(key.runs.allSatisfy { $0.backgroundColor != nil })
    }

    @Test func themeRoundTripsWithSyntaxPalette() throws {
        let data = try JSONEncoder().encode(PreviewTheme.github)
        #expect(try JSONDecoder().decode(PreviewTheme.self, from: data) == .github)
    }
}

@MainActor
@Suite(.requiresWindowServer) struct Plan2SmokeTests {
    static let document = """
    ---
    title: Smoke
    ---
    # Math $x^2$ heading

    Inline $\\frac{a}{b}$, broken $\\frac{$, ==marked==, H<sub>2</sub>O, <kbd>⌘K</kbd>.

    $$
    \\int_0^1 x^2 \\, dx
    $$

    $$
    \\frac{
    $$

    ```swift
    let x = 1
    ```

    ```mermaid
    graph TD; A-->B
    ```

    <p align="center"><img src="missing.png" width="40" alt="A"> <img src="missing2.png" alt="B"></p>

    <p align="center"><img src="x.png" alt="pic"><br><sub>caption</sub></p>

    <details>
    <summary>More</summary>

    Hidden text.

    </details>
    """

    @Test func everyNewBlockKindRenders() throws {
        let rendered = MarkdownPipeline.render(Self.document, options: .default)
        let content = VStack(alignment: .leading) { ForEach(rendered.document.blocks) { BlockView(block: $0) } }
            .frame(width: 600)
            .environment(\.previewTheme, .github)
        let image = try #require(ImageRenderer(content: content).nsImage)
        #expect(image.size.height > 300)
    }
}
