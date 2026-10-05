import AppKit
import SwiftUI
import WebRenderKit

extension EnvironmentValues {
    /// Draws diagrams, formulas SwiftMath cannot typeset, and complex HTML. nil leaves them as source.
    @Entry public var webRenderer: (any WebRendering)? = nil
}

extension ThemeColor {
    /// The colour for one appearance as a CSS value (`#RRGGBB` or `#RRGGBBAA`).
    func hex(for scheme: ColorScheme) -> String {
        scheme == .dark ? dark : light
    }
}

extension RenderAppearance {
    init(_ scheme: ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
}

extension RenderError {
    /// A line or two for the preview. Parser messages run on for pages of "Expecting …"; the whole text
    /// stays available as a tooltip.
    var summary: String {
        switch self {
        case .syntax(let message):
            if message.hasPrefix("UnknownDiagramError") {
                return "Unknown diagram type. Start with flowchart, sequenceDiagram, classDiagram, stateDiagram, erDiagram, gantt, pie…"
            }
            let lines = message.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let first = lines.first else { return "The source could not be drawn." }
            var text = first.hasPrefix("Error: ") ? String(first.dropFirst(7)) : first
            if lines.count > 1, let last = lines.last, last != first {
                text += " " + (last.count > 120 ? String(last.prefix(120)) + "…" : last)
            }
            return text
        case .timeout:
            return "Drawing took too long and was stopped."
        case .unavailable(let reason):
            return "The renderer could not start: \(reason)"
        case .crashed:
            return "The renderer stopped unexpectedly."
        }
    }

    var fullMessage: String {
        if case .syntax(let message) = self { return message }
        return summary
    }
}

extension PreviewTheme {
    /// Typography for raw HTML drawn by the snapshot host, so a table or a styled `div` looks like the rest
    /// of the preview. Colours are CSS hex for one appearance.
    func htmlStyleSheet(for scheme: ColorScheme) -> String {
        func css(_ color: ThemeColor) -> String { color.hex(for: scheme) }
        let headings = (1...6).map { level in
            "h\(level) { font-size: \(String(format: "%.3f", headingScales[level - 1]))em; margin: 0.6em 0 0.3em; font-weight: 600; }"
        }.joined(separator: "\n")
        return """
        a { color: \(css(link)); }
        code, pre, kbd { font-family: ui-monospace, Menlo, monospace; font-size: \(String(format: "%.3f", codeFontScale))em; }
        code, kbd { background: \(css(codeBackground)); border-radius: 4px; padding: 0.15em 0.35em; }
        pre { background: \(css(codeBackground)); border-radius: 6px; padding: 12px; overflow: hidden; }
        pre code { background: none; padding: 0; }
        table { border-collapse: collapse; }
        th, td { border: 1px solid \(css(border)); padding: 6px 12px; }
        th { font-weight: 600; }
        tr:nth-child(even) td { background: \(css(tableStripe)); }
        blockquote { margin: 0; padding: 0 1em; color: \(css(secondaryText)); border-left: 4px solid \(css(blockQuoteBar)); }
        hr { border: 0; border-top: 1px solid \(css(border)); }
        p, ul, ol, table, blockquote, pre { margin: 0 0 \(Int(blockSpacing * 0.6))px; }
        \(headings)
        """
    }
}
