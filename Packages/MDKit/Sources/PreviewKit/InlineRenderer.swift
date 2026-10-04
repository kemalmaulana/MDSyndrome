import Foundation
import MarkdownCore
import SwiftUI

/// Turns inline AST nodes into text for a single `Text`.
/// Emphasis/strong/code/strikethrough use `inlinePresentationIntent`, which
/// SwiftUI combines correctly (e.g. bold + italic) with the surrounding font.
public enum InlineRenderer {
    /// Text with native math: top-level `.math` inlines become typeset images sitting on the baseline.
    /// Math nested inside emphasis or links falls back to monospaced source.
    @MainActor
    public static func text(_ inlines: [Inline], theme: PreviewTheme, fontSize: Double? = nil) -> Text {
        guard inlines.contains(where: { if case .math = $0 { true } else { false } }) else {
            return Text(attributedString(inlines, theme: theme))
        }
        var parts: [Text] = []
        var buffer: [Inline] = []
        func flush() {
            if !buffer.isEmpty { parts.append(Text(attributedString(buffer, theme: theme))) }
            buffer = []
        }
        for inline in inlines {
            if case .math(let latex, let display) = inline {
                flush()
                parts.append(mathText(latex, display: display, fontSize: fontSize ?? theme.bodyFontSize, theme: theme))
            } else {
                buffer.append(inline)
            }
        }
        flush()
        // `Text + Text` is deprecated in macOS 26; interpolation composes the same way.
        return parts.dropFirst().reduce(parts[0]) { Text("\($0)\($1)") }
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
