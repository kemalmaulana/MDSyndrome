import AppKit
import Foundation
import MarkdownCore
import SyntaxHighlighting

/// Turns a rendered document into HTML for export and Copy HTML (PRD EX-1, EX-2). The file is self-contained and
/// never holds a script: raw HTML is stripped of scripts, event handlers and `javascript:` addresses.
@MainActor
public struct HTMLExporter {
    public let theme: PreviewTheme
    public let title: String
    private let slugs: [BlockID: String]
    private var footnoteIndexes: [Int] = []

    public init(theme: PreviewTheme = .github, title: String = "Document", blocks: [Block] = []) {
        self.theme = theme
        self.title = title
        slugs = DocumentAnchors.headingSlugs(in: blocks)
    }

    /// A complete page with the theme's CSS (light and dark).
    public static func standalone(_ document: MarkdownDocument, theme: PreviewTheme, title: String) -> String {
        var exporter = HTMLExporter(theme: theme, title: title, blocks: document.blocks)
        let body = exporter.body(document)
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(escape(title))</title>
        <style>
        \(HTMLExportStyle.css(for: theme))
        </style></head>
        <body><article class="markdown-body">
        \(body)
        </article></body></html>
        """
    }

    /// Only the body, for Copy HTML.
    public static func fragment(_ document: MarkdownDocument, theme: PreviewTheme = .github) -> String {
        var exporter = HTMLExporter(theme: theme, blocks: document.blocks)
        return exporter.body(document)
    }

    mutating func body(_ document: MarkdownDocument) -> String {
        let main = document.blocks.filter { if case .footnoteDefinition = $0.kind { false } else { true } }
        let notes = document.blocks.filter { if case .footnoteDefinition = $0.kind { true } else { false } }
        var html = main.map { render($0) }.joined(separator: "\n")
        if !notes.isEmpty {
            html += "\n<section class=\"footnotes\"><hr><ol>\n"
            for note in notes {
                guard case .footnoteDefinition(let index, _, let children) = note.kind else { continue }
                let inner = children.map { render($0) }.joined(separator: "\n")
                html += "<li id=\"fn-\(index)\">\(inner) <a href=\"#fnref-\(index)\" class=\"back\">\u{21A9}\u{FE0E}</a></li>\n"
            }
            html += "</ol></section>"
        }
        return html
    }

    // MARK: Blocks

    private func render(_ block: Block) -> String {
        switch block.kind {
        case .heading(let level, let content):
            let id = slugs[block.id].map { " id=\"\(Self.escape($0))\"" } ?? ""
            return "<h\(level)\(id)>\(inlines(content))</h\(level)>"
        case .paragraph(let content):
            return "<p>\(inlines(content))</p>"
        case .blockQuote(let children):
            return "<blockquote>\n\(children.map { render($0) }.joined(separator: "\n"))\n</blockquote>"
        case .list(let list):
            return renderList(list)
        case .codeBlock(let language, let code):
            return renderCode(language: language, code: code)
        case .thematicBreak:
            return "<hr>"
        case .htmlBlock(let html):
            return HTMLSanitizer.clean(html)
        case .table(let table):
            return renderTable(table)
        case .mathBlock(let latex):
            return "<p class=\"math-display\">\(mathImage(latex, display: true))</p>"
        case .footnoteDefinition:
            return ""
        case .frontMatter(let entries):
            let rows = entries.map { "<tr><th>\(Self.escape($0.key))</th><td>\(Self.escape($0.value))</td></tr>" }.joined()
            return "<table class=\"front-matter\">\(rows)</table>"
        case .details(let summary, let isOpen, let children):
            return "<details\(isOpen ? " open" : "")><summary>\(inlines(summary))</summary>\n\(children.map { render($0) }.joined(separator: "\n"))\n</details>"
        case .htmlParagraph(let level, let alignment, let content):
            let style = alignment == .center ? " style=\"text-align:center\"" : alignment == .trailing ? " style=\"text-align:right\"" : ""
            let tag = level > 0 ? "h\(level)" : "p"
            return "<\(tag)\(style)>\(inlines(content))</\(tag)>"
        }
    }

    private func renderList(_ list: ListBlock) -> String {
        let tag = list.ordered ? "ol" : "ul"
        let start = list.ordered && list.start != 1 ? " start=\"\(list.start)\"" : ""
        let items = list.items.map { item -> String in
            let children = item.blocks.map { block -> String in
                if list.tight, case .paragraph(let content) = block.kind { return inlines(content) }
                return render(block)
            }.joined(separator: "\n")
            switch item.task {
            case .checked?: return "<li class=\"task\"><input type=\"checkbox\" checked disabled> \(children)</li>"
            case .unchecked?: return "<li class=\"task\"><input type=\"checkbox\" disabled> \(children)</li>"
            case nil: return "<li>\(children)</li>"
            }
        }.joined(separator: "\n")
        return "<\(tag)\(start)>\n\(items)\n</\(tag)>"
    }

    private func renderCode(language: String?, code: String) -> String {
        let spans = Highlighter.highlight(code, language: language).map { segment -> String in
            let text = Self.escape(segment.text)
            return segment.kind.map { "<span class=\"tk-\($0.rawValue)\">\(text)</span>" } ?? text
        }.joined()
        let cls = language.map { " class=\"language-\(Self.escape($0))\"" } ?? ""
        return "<pre><code\(cls)>\(spans)</code></pre>"
    }

    private func renderTable(_ table: TableBlock) -> String {
        func align(_ column: Int) -> String {
            switch table.alignments[column] {
            case .left: " style=\"text-align:left\""
            case .center: " style=\"text-align:center\""
            case .right: " style=\"text-align:right\""
            case .none: ""
            }
        }
        let head = table.header.enumerated().map { "<th\(align($0.offset))>\(inlines($0.element))</th>" }.joined()
        let rows = table.rows.map { row in
            "<tr>" + row.enumerated().map { "<td\(align($0.offset))>\(inlines($0.element))</td>" }.joined() + "</tr>"
        }.joined(separator: "\n")
        return "<table>\n<thead><tr>\(head)</tr></thead>\n<tbody>\n\(rows)\n</tbody>\n</table>"
    }

    // MARK: Inlines

    private func inlines(_ items: [Inline]) -> String {
        items.map(inline).joined()
    }

    private func inline(_ item: Inline) -> String {
        switch item {
        case .text(let text): Self.escape(text)
        case .emphasis(let c): "<em>\(inlines(c))</em>"
        case .strong(let c): "<strong>\(inlines(c))</strong>"
        case .strikethrough(let c): "<del>\(inlines(c))</del>"
        case .code(let code): "<code>\(Self.escape(code))</code>"
        case .link(let destination, let title, let content):
            "<a href=\"\(Self.escape(HTMLSanitizer.safeURL(destination)))\"\(title.map { " title=\"\(Self.escape($0))\"" } ?? "")>\(inlines(content))</a>"
        case .image(let source, let title, let alt, let width):
            "<img src=\"\(Self.escape(HTMLSanitizer.safeURL(source)))\" alt=\"\(Self.escape(alt))\"\(title.map { " title=\"\(Self.escape($0))\"" } ?? "")\(width.map { " width=\"\(Int($0))\"" } ?? "")>"
        case .softBreak: "\n"
        case .lineBreak: "<br>\n"
        case .html(let html): HTMLSanitizer.clean(html)
        case .math(let latex, let display): mathImage(latex, display: display)
        case .footnoteReference(let index): "<sup><a href=\"#fn-\(index)\" id=\"fnref-\(index)\">\(index)</a></sup>"
        case .highlight(let c): "<mark>\(inlines(c))</mark>"
        case .superscript(let c): "<sup>\(inlines(c))</sup>"
        case .subscript(let c): "<sub>\(inlines(c))</sub>"
        case .underline(let c): "<u>\(inlines(c))</u>"
        case .keyboard(let c): "<kbd>\(inlines(c))</kbd>"
        }
    }

    /// A formula as a `@2x` PNG data-URI image; its source stays in `alt`. A formula SwiftMath cannot typeset is its source in code.
    private func mathImage(_ latex: String, display: Bool) -> String {
        let size = theme.bodyFontSize * (display ? 1.2 : 1)
        guard case .success(let math) = MathRenderer.render(latex, fontSize: size, display: display),
              let png = Self.png(math.image, scale: 2) else { return "<code>\(Self.escape(latex))</code>" }
        let height = Int(math.image.size.height.rounded())
        let shift = display ? "" : "vertical-align:-\(Int(math.descent.rounded()))px;"
        return "<img class=\"math\" alt=\"\(Self.escape(latex))\" height=\"\(height)\" style=\"\(shift)\" src=\"data:image/png;base64,\(png.base64EncodedString())\">"
    }

    private static func png(_ image: NSImage, scale: CGFloat) -> Data? {
        let width = Int((image.size.width * scale).rounded(.up)), height = Int((image.size.height * scale).rounded(.up))
        guard width > 0, height > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                                 bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Keeps a script from reaching an exported file through raw HTML or a link.
enum HTMLSanitizer {
    private static let blocks = try! NSRegularExpression(pattern: #"<\s*(script|style|iframe|object|embed)\b[^>]*>.*?<\s*/\s*\1\s*>|<\s*(script|style|iframe|object|embed)\b[^>]*/?>"#,
                                                          options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let handlers = try! NSRegularExpression(pattern: #"\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#, options: [.caseInsensitive])
    private static let scriptURLs = try! NSRegularExpression(pattern: #"(href|src|xlink:href|action|formaction)\s*=\s*("|')?\s*(javascript|vbscript|data:text/html)[^"'>\s]*("|')?"#, options: [.caseInsensitive])

    static func clean(_ html: String) -> String {
        var result = html
        for expression in [blocks, handlers, scriptURLs] {
            result = expression.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: "")
        }
        return result
    }

    /// A link or image address, or "#" when it would run code.
    static func safeURL(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["javascript:", "vbscript:", "data:text/html"].contains { trimmed.hasPrefix($0) } ? "#" : address
    }
}

enum HTMLExportStyle {
    static func css(for theme: PreviewTheme) -> String {
        func rules(_ dark: Bool) -> String {
            func c(_ color: ThemeColor) -> String { dark ? color.dark : color.light }
            var css = """
            body { background: \(c(theme.background)); color: \(c(theme.text)); margin: 0; }
            .markdown-body { max-width: \(Int(theme.maxContentWidth))px; margin: 0 auto; padding: 32px; font: \(theme.bodyFontSize)px/1.6 -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif; }
            a { color: \(c(theme.link)); }
            hr { border: 0; border-top: 1px solid \(c(theme.border)); }
            code, pre, kbd { font-family: ui-monospace, Menlo, monospace; font-size: \(theme.codeFontScale)em; }
            code, kbd { background: \(c(theme.codeBackground)); border-radius: 4px; padding: .15em .35em; }
            pre { background: \(c(theme.codeBackground)); border-radius: 6px; padding: 12px; overflow: auto; }
            pre code { background: none; padding: 0; }
            blockquote { margin: 0; padding: 0 1em; color: \(c(theme.secondaryText)); border-left: 4px solid \(c(theme.blockQuoteBar)); }
            table { border-collapse: collapse; } th, td { border: 1px solid \(c(theme.border)); padding: 6px 12px; }
            tr:nth-child(even) td { background: \(c(theme.tableStripe)); }
            mark { background: \(c(theme.highlightBackground)); color: inherit; }
            li.task { list-style: none; margin-left: -1.4em; }
            .footnotes { color: \(c(theme.secondaryText)); font-size: .875em; } .footnotes .back { text-decoration: none; }
            img { max-width: 100%; } .math-display { text-align: center; }
            """
            for (n, scale) in theme.headingScales.enumerated() {
                css += "\nh\(n + 1) { font-size: \(String(format: "%.3f", scale))em; margin: 1.2em 0 .5em; font-weight: 600; }"
            }
            let palette = theme.syntax
            for kind in TokenKind.allCases { css += "\n.tk-\(kind.rawValue) { color: \(c(palette.color(for: kind))); }" }
            if dark { css += "\nimg.math { filter: invert(1); }" }
            return css
        }
        return rules(false) + "\n@media (prefers-color-scheme: dark) {\n" + rules(true) + "\n}"
    }
}
