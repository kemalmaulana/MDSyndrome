import Foundation
import MarkdownCore
import SwiftUI

/// Turns inline AST nodes into one AttributedString for a single `Text`.
/// Emphasis/strong/code/strikethrough use `inlinePresentationIntent`, which
/// SwiftUI combines correctly (e.g. bold + italic) with the surrounding font.
public enum InlineRenderer {
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
            case .image(_, _, let alt):
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
                // Placeholder until native math rendering lands (plan 2).
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
            }
        }
    }

    private static func run(_ string: String, _ intent: InlinePresentationIntent) -> AttributedString {
        var run = AttributedString(string)
        if !intent.isEmpty { run.inlinePresentationIntent = intent }
        return run
    }
}
