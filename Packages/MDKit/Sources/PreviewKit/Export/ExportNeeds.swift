import MarkdownCore
import SwiftUI
import WebRenderKit

/// What an export has to fetch before it can render a document: which images, which diagrams and fallback
/// formulas the web renderer must draw, which raw HTML blocks need their images inlined.
@MainActor
struct ExportNeeds {
    var imageSources: [String] = []
    var diagrams: [(kind: RenderKind, code: String)] = []
    var blockFormulas: [String] = []
    var htmlBlocks: [String] = []
    /// Lines of inline content with the font size the preview draws them at, for formulas SwiftMath rejects.
    var inlineRuns: [(inlines: [Inline], fontSize: Double)] = []

    /// - Parameter contextSizes: true for the PDF (a heading's formulas are drawn at the heading size, as in the
    ///   preview); false for HTML, whose formulas are all drawn at the body size.
    static func collect(_ blocks: [Block], theme: PreviewTheme, contextSizes: Bool) -> ExportNeeds {
        var needs = ExportNeeds()
        needs.walk(blocks, theme: theme, contextSizes: contextSizes)
        return needs
    }

    private mutating func walk(_ blocks: [Block], theme: PreviewTheme, contextSizes: Bool) {
        for block in blocks {
            switch block.kind {
            case .heading(let level, let content):
                add(content, fontSize: contextSizes ? theme.headingSize(level: level) : theme.bodyFontSize)
            case .paragraph(let content), .htmlParagraph(_, _, let content):
                add(content, fontSize: theme.bodyFontSize)
            case .blockQuote(let children), .footnoteDefinition(_, _, let children):
                walk(children, theme: theme, contextSizes: contextSizes)
            case .details(let summary, _, let children):
                add(summary, fontSize: theme.bodyFontSize)
                walk(children, theme: theme, contextSizes: contextSizes)
            case .list(let list):
                for item in list.items { walk(item.blocks, theme: theme, contextSizes: contextSizes) }
            case .table(let table):
                for cell in table.header { add(cell, fontSize: theme.bodyFontSize) }
                for row in table.rows { for cell in row { add(cell, fontSize: theme.bodyFontSize) } }
            case .codeBlock(let language, let code):
                if let kind = DiagramLanguage.kind(of: language), !code.allSatisfy(\.isWhitespace) { diagrams.append((kind, code)) }
            case .htmlBlock(let html):
                htmlBlocks.append(html)
            case .mathBlock(let latex):
                if case .failure = MathRenderer.render(latex, fontSize: theme.bodyFontSize * 1.2, display: true) { blockFormulas.append(latex) }
            case .thematicBreak, .frontMatter:
                break
            }
        }
    }

    private mutating func add(_ inlines: [Inline], fontSize: Double) {
        inlineRuns.append((inlines, fontSize))
        collectImages(in: inlines)
    }

    private mutating func collectImages(in inlines: [Inline]) {
        for inline in inlines {
            switch inline {
            case .image(let source, _, _, _):
                imageSources.append(source)
            case .emphasis(let c), .strong(let c), .strikethrough(let c), .highlight(let c), .superscript(let c),
                 .subscript(let c), .underline(let c), .keyboard(let c), .link(_, _, let c):
                collectImages(in: c)
            case .text, .code, .softBreak, .lineBreak, .html, .math, .footnoteReference:
                break
            }
        }
    }

    /// Every request the web renderer must answer for one appearance (HTML blocks are added by `prepare`, after their images are inlined).
    func requests(theme: PreviewTheme, scheme: ColorScheme) -> [RenderRequest] {
        var result = diagrams.map { PictureRequests.diagram($0.kind, code: $0.code, theme: theme, scheme: scheme) }
        result += blockFormulas.map { PictureRequests.blockFormula($0, theme: theme, scheme: scheme) }
        let foreground = theme.text.hex(for: scheme), background = theme.background.hex(for: scheme)
        for run in inlineRuns {
            for key in InlineRenderer.failingFormulas(run.inlines, fontSize: run.fontSize, dark: scheme == .dark) {
                result.append(PictureRequests.inlineFormula(key, foreground: foreground, background: background))
            }
        }
        return result
    }
}
