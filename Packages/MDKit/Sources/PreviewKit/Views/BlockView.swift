import MarkdownCore
import SwiftUI

struct BlockView: View {
    let block: Block
    @Environment(\.previewTheme) private var theme

    var body: some View {
        switch block.kind {
        case .heading(let level, let content):
            HeadingView(level: level, content: content)
        case .paragraph(let content):
            ParagraphView(content: content)
        case .blockQuote(let children):
            BlockQuoteView(blocks: children)
        case .list(let list):
            ListBlockView(list: list)
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)
        case .thematicBreak:
            Rectangle().fill(theme.border.color).frame(height: 2).padding(.vertical, 8)
        case .htmlBlock(let html):
            Text(html)
                .font(.system(size: theme.codeFontSize, design: .monospaced))
                .foregroundStyle(theme.secondaryText.color)
                .textSelection(.enabled)
        case .table(let table):
            TableBlockView(table: table)
        case .mathBlock(let latex):
            // Placeholder until native math rendering lands (plan 2).
            CodeBlockView(language: "math", code: latex)
        case .footnoteDefinition(let index, _, let blocks):
            FootnoteView(index: index, blocks: blocks)
        }
    }
}

struct HeadingView: View {
    let level: Int
    let content: [Inline]
    @Environment(\.previewTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(InlineRenderer.attributedString(content, theme: theme))
                .font(.system(size: theme.headingSize(level: level), weight: .semibold))
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            if level <= 2 {
                Rectangle().fill(theme.border.color).frame(height: 1)
            }
        }
        .padding(.top, level <= 2 ? 8 : 4)
    }
}

struct ParagraphView: View {
    let content: [Inline]
    @Environment(\.previewTheme) private var theme

    var body: some View {
        if case .image(let source, _, let alt)? = content.onlyNonWhitespace {
            ImageBlockView(source: source, alt: alt)
        } else {
            Text(InlineRenderer.attributedString(content, theme: theme))
                .lineSpacing(theme.lineSpacing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BlockQuoteView: View {
    let blocks: [Block]
    @Environment(\.previewTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(theme.blockQuoteBar.color).frame(width: 4)
            VStack(alignment: .leading, spacing: theme.blockSpacing) {
                ForEach(blocks) { BlockView(block: $0) }
            }
            .foregroundStyle(theme.secondaryText.color)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct FootnoteView: View {
    let index: Int
    let blocks: [Block]
    @Environment(\.previewTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if index == 1 {
                Rectangle().fill(theme.border.color).frame(height: 1).padding(.top, 16)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index).").monospacedDigit().foregroundStyle(theme.secondaryText.color)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(blocks) { BlockView(block: $0) }
                }
            }
            .font(.system(size: theme.bodyFontSize * 0.875))
        }
        .id("fn-\(index)")
    }
}
