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
            InlineFlowView(content: content)
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
            MathBlockView(latex: latex)
        case .footnoteDefinition(let index, _, let blocks):
            FootnoteView(index: index, blocks: blocks)
        case .frontMatter(let entries):
            FrontMatterView(entries: entries)
        case .details(let summary, let isOpen, let blocks):
            DetailsView(summary: summary, initiallyOpen: isOpen, blocks: blocks)
        case .htmlParagraph(let level, let alignment, let content):
            HTMLParagraphView(level: level, alignment: alignment, content: content)
        }
    }
}

struct HeadingView: View {
    let level: Int
    let content: [Inline]
    var alignment: BlockAlignment = .leading
    @Environment(\.previewTheme) private var theme

    var body: some View {
        VStack(alignment: alignment.horizontal, spacing: 6) {
            InlineRenderer.text(content, theme: theme, fontSize: theme.headingSize(level: level))
                .font(.system(size: theme.headingSize(level: level), weight: .semibold))
                .multilineTextAlignment(alignment.text)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            if level <= 2 {
                Rectangle().fill(theme.border.color).frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment.frame)
        .padding(.top, level <= 2 ? 8 : 4)
    }
}

/// Paragraph content: text with inline math, rows of images (README badges), or a mix where each
/// line (split at line breaks) is either an image row or text.
struct InlineFlowView: View {
    let content: [Inline]
    var alignment: BlockAlignment = .leading
    @Environment(\.previewTheme) private var theme

    var body: some View {
        if case .image(let source, _, let alt, let width)? = content.onlyNonWhitespace {
            ImageBlockView(source: source, alt: alt, width: width)
                .frame(maxWidth: .infinity, alignment: alignment.frame)
        } else if let images = content.imageRow {
            ImageRowView(images: images)
                .environment(\.blockAlignment, alignment)
        } else if content.containsImage {
            VStack(alignment: alignment.horizontal, spacing: 6) {
                ForEach(Array(content.splitAtLineBreaks().enumerated()), id: \.offset) { _, line in
                    InlineFlowView(content: line, alignment: alignment)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment.frame)
        } else {
            InlineRenderer.text(content, theme: theme)
                .lineSpacing(theme.lineSpacing)
                .multilineTextAlignment(alignment.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: alignment.frame)
        }
    }
}

struct HTMLParagraphView: View {
    let level: Int
    let alignment: BlockAlignment
    let content: [Inline]

    var body: some View {
        if level > 0 {
            HeadingView(level: level, content: content, alignment: alignment)
        } else {
            InlineFlowView(content: content, alignment: alignment)
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

/// `$$ … $$` and ```` ```math ```` blocks, typeset natively and centred.
struct MathBlockView: View {
    let latex: String
    @Environment(\.previewTheme) private var theme

    var body: some View {
        switch MathRenderer.render(latex, fontSize: theme.bodyFontSize * 1.2, display: true) {
        case .success(let math):
            let image = Image(nsImage: math.image)
                .renderingMode(.template)
                .foregroundStyle(theme.text.color)
                .accessibilityLabel(latex)
            ViewThatFits(in: .horizontal) {
                image.frame(maxWidth: .infinity)
                ScrollView(.horizontal) { image.padding(.vertical, 4) }
            }
            .padding(.vertical, 4)
        case .failure(.syntax(let message)):
            VStack(alignment: .leading, spacing: 4) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                Text(latex)
                    .font(.system(size: theme.codeFontSize, design: .monospaced))
                    .textSelection(.enabled)
            }
            .foregroundStyle(theme.error.color)
            .accessibilityLabel("LaTeX error: \(message)")
        }
    }
}

/// YAML front matter as a compact, collapsible key/value table.
struct FrontMatterView: View {
    let entries: [FrontMatterEntry]
    @Environment(\.previewTheme) private var theme
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    GridRow {
                        Text(entry.key).fontWeight(.semibold).foregroundStyle(theme.secondaryText.color)
                        Text(entry.value).textSelection(.enabled)
                    }
                }
            }
            .font(.system(size: theme.codeFontSize, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        } label: {
            Text("Front matter").font(.caption).foregroundStyle(theme.secondaryText.color)
        }
        .padding(12)
        .background(theme.codeBackground.color, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// `<details><summary>`: collapsed unless the HTML had `open`.
struct DetailsView: View {
    let summary: [Inline]
    let blocks: [Block]
    @Environment(\.previewTheme) private var theme
    @State private var isExpanded: Bool

    init(summary: [Inline], initiallyOpen: Bool, blocks: [Block]) {
        self.summary = summary
        self.blocks = blocks
        _isExpanded = State(initialValue: initiallyOpen)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: theme.blockSpacing) {
                ForEach(blocks) { BlockView(block: $0) }
            }
            .padding(.top, 8)
            .padding(.leading, 4)
        } label: {
            InlineRenderer.text(summary, theme: theme)
        }
    }
}

extension BlockAlignment {
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frame: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var text: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

extension Array where Element == Inline {
    var containsImage: Bool {
        contains {
            switch $0 {
            case .image: true
            case .link(_, _, let content): content.containsImage
            default: false
            }
        }
    }

    /// Lines of a paragraph, split at hard line breaks.
    func splitAtLineBreaks() -> [[Inline]] {
        split(whereSeparator: { $0 == .lineBreak }).map(Array.init)
    }
}
