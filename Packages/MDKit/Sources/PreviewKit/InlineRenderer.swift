import Foundation
import MarkdownCore
import SwiftUI

/// Turns inline AST nodes into text for a single `Text`.
/// Emphasis/strong/code/strikethrough use `inlinePresentationIntent`, which
/// SwiftUI combines correctly (e.g. bold + italic) with the surrounding font.
public enum InlineRenderer {
    /// What a run of inlines is drawn as: text, or a formula typeset as an image.
    enum Piece {
        case text(AttributedString)
        case math(latex: String, display: Bool)
    }

    /// Splits `inlines` into text and top-level formulas. Math nested inside emphasis or links stays
    /// monospaced source inside the text.
    static func pieces(_ inlines: [Inline], theme: PreviewTheme) -> [Piece] {
        let mathCount = inlines.reduce(0) { if case .math = $1 { $0 + 1 } else { $0 } }
        // Hundreds of formulas in one paragraph: typesetting each and composing the Text costs more than
        // it gives, so show them as source (still readable, never a crash).
        guard mathCount > 0, mathCount <= maxTypesetFormulas else {
            return [.text(attributedString(inlines, theme: theme))]
        }
        var pieces: [Piece] = []
        var buffer: [Inline] = []
        func flush() {
            if !buffer.isEmpty { pieces.append(.text(attributedString(buffer, theme: theme))) }
            buffer = []
        }
        for inline in inlines {
            if case .math(let latex, let display) = inline {
                flush()
                pieces.append(.math(latex: latex, display: display))
            } else {
                buffer.append(inline)
            }
        }
        flush()
        return pieces
    }

    /// The characters of `inlines` that the preview draws as text, which is what find searches.
    static func searchText(_ inlines: [Inline]) -> String {
        pieces(inlines, theme: .github).reduce(into: "") { result, piece in
            if case .text(let text) = piece { result += String(text.characters) }
        }
    }

    /// `pieces` with find matches coloured. Offsets count the text characters of the whole run, so a
    /// formula (which has none) sits between two text pieces without shifting the second one.
    static func highlightedPieces(_ inlines: [Inline], theme: PreviewTheme, highlights: [SearchHighlight]) -> [Piece] {
        var offset = 0
        return pieces(inlines, theme: theme).map { piece in
            guard case .text(var attributed) = piece, !highlights.isEmpty else { return piece }
            attributed.applySearchHighlights(highlights, offset: offset, theme: theme)
            offset += attributed.characters.count
            return .text(attributed)
        }
    }

    /// Text with native math: top-level `.math` inlines become typeset images sitting on the baseline.
    /// `highlights` colour find matches; their offsets count the text characters only (formulas have none).
    @MainActor
    static func text(_ inlines: [Inline], theme: PreviewTheme, fontSize: Double? = nil, highlights: [SearchHighlight]) -> Text {
        let parts: [Text] = highlightedPieces(inlines, theme: theme, highlights: highlights).map { piece in
            switch piece {
            case .text(let attributed): Text(attributed)
            case .math(let latex, let display): mathText(latex, display: display, fontSize: fontSize ?? theme.bodyFontSize, theme: theme)
            }
        }
        return concatenate(parts[...])
    }

    @MainActor
    public static func text(_ inlines: [Inline], theme: PreviewTheme, fontSize: Double? = nil) -> Text {
        text(inlines, theme: theme, fontSize: fontSize, highlights: [])
    }

    /// Formulas per paragraph above which inline math is shown as source instead of typeset.
    static let maxTypesetFormulas = 200

    /// `Text + Text` is deprecated in macOS 26; interpolation composes the same way. Split in halves so
    /// nesting depth is log2(n): a left fold nests once per part and overflows the stack for long runs.
    private static func concatenate(_ parts: ArraySlice<Text>) -> Text {
        if parts.count == 1 { return parts[parts.startIndex] }
        let middle = parts.startIndex + parts.count / 2
        return Text("\(concatenate(parts[..<middle]))\(concatenate(parts[middle...]))")
    }

    @MainActor
    private static func mathText(_ latex: String, display: Bool, fontSize: Double, theme: PreviewTheme) -> Text {
        switch MathRenderer.render(latex, fontSize: fontSize, display: display) {
        case .success(let math):
            return Text(Image(nsImage: math.image).renderingMode(.template)).baselineOffset(-math.descent)
        case .failure:
            var source = AttributedString(latex)
            source.inlinePresentationIntent = .code
            source.foregroundColor = theme.error.color
            return Text(source)
        }
    }

    public static func attributedString(_ inlines: [Inline], theme: PreviewTheme) -> AttributedString {
        var result = AttributedString()
        append(inlines, to: &result, intent: [], theme: theme)
        return result
    }

    private static func append(_ inlines: [Inline], to result: inout AttributedString, intent: InlinePresentationIntent, theme: PreviewTheme) {
        for inline in inlines {
            switch inline {
            case .text(let string):
                result += run(string, intent)
            case .emphasis(let children):
                append(children, to: &result, intent: intent.union(.emphasized), theme: theme)
            case .strong(let children):
                append(children, to: &result, intent: intent.union(.stronglyEmphasized), theme: theme)
            case .strikethrough(let children):
                append(children, to: &result, intent: intent.union(.strikethrough), theme: theme)
            case .code(let string):
                var code = run(string, intent.union(.code))
                code.backgroundColor = theme.codeBackground.color
                result += code
            case .link(let destination, _, let content):
                var link = AttributedString()
                append(content, to: &link, intent: intent, theme: theme)
                link.foregroundColor = theme.link.color
                if let url = URL(string: destination) { link.link = url }
                result += link
            case .image(_, _, let alt, _):
                var image = run(alt.isEmpty ? "[image]" : "[\(alt)]", intent)
                image.foregroundColor = theme.secondaryText.color
                result += image
            case .softBreak:
                result += run(" ", intent)
            case .lineBreak:
                result += run("\n", intent)
            case .html(let html):
                var raw = run(html, intent)
                raw.foregroundColor = theme.secondaryText.color
                result += raw
            case .math(let latex, _):
                // Only reached for math nested in other inlines; top-level math goes through `text(_:)`.
                var math = run(latex, intent.union(.code))
                math.foregroundColor = theme.secondaryText.color
                result += math
            case .footnoteReference(let index):
                var reference = AttributedString("\(index)")
                reference.baselineOffset = theme.bodyFontSize * 0.35
                reference.font = .system(size: theme.bodyFontSize * 0.7)
                reference.foregroundColor = theme.link.color
                reference.link = URL(string: "#fn-\(index)")
                result += reference
            case .highlight(let children):
                var marked = AttributedString()
                append(children, to: &marked, intent: intent, theme: theme)
                marked.backgroundColor = theme.highlightBackground.color
                result += marked
            case .superscript(let children), .subscript(let children):
                var shifted = AttributedString()
                append(children, to: &shifted, intent: intent, theme: theme)
                let isSuper = if case .superscript = inline { true } else { false }
                shifted.baselineOffset = theme.bodyFontSize * (isSuper ? 0.35 : -0.2)
                shifted.font = .system(size: theme.bodyFontSize * 0.75)
                result += shifted
            case .underline(let children):
                var underlined = AttributedString()
                append(children, to: &underlined, intent: intent, theme: theme)
                underlined.underlineStyle = .single
                result += underlined
            case .keyboard(let children):
                var key = AttributedString("\u{2009}")   // thin spaces pad the key cap
                append(children, to: &key, intent: intent.union(.code), theme: theme)
                key += AttributedString("\u{2009}")
                key.backgroundColor = theme.codeBackground.color
                key.font = .system(size: theme.codeFontSize, design: .monospaced)
                result += key
            }
        }
    }

    private static func run(_ string: String, _ intent: InlinePresentationIntent) -> AttributedString {
        var run = AttributedString(string)
        if !intent.isEmpty { run.inlinePresentationIntent = intent }
        return run
    }
}

extension AttributedString {
    /// Gives find matches a background. `offset` is where this text starts within the run it belongs to.
    mutating func applySearchHighlights(_ highlights: [SearchHighlight], offset: Int, theme: PreviewTheme) {
        let length = characters.count
        var index = characters.startIndex
        var position = 0
        for highlight in highlights.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            let start = Swift.max(0, highlight.range.lowerBound - offset)
            let end = Swift.min(length, highlight.range.upperBound - offset)
            guard start < end, start >= position else { continue }
            index = characters.index(index, offsetBy: start - position)
            let stop = characters.index(index, offsetBy: end - start)
            self[index..<stop].backgroundColor = (highlight.isCurrent ? theme.searchCurrentBackground : theme.searchMatchBackground).color
            index = stop
            position = end
        }
    }
}
