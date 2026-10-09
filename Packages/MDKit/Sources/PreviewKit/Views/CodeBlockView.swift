import AppKit
import SwiftUI
import SyntaxHighlighting

struct CodeBlockView: View {
    let language: String?
    let code: String
    @Environment(\.previewTheme) private var theme
    @Environment(\.previewSearch) private var search
    @Environment(\.searchLine) private var searchLine
    @Environment(\.exportResources) private var export

    private var styledCode: AttributedString {
        var styled = SyntaxStyler.attributed(code, language: language, theme: theme)
        let highlights = search?.highlights(for: SearchRunKey(line: searchLine, slot: 0)) ?? []
        if !highlights.isEmpty { styled.applySearchHighlights(highlights, offset: 0, theme: theme) }
        return styled
    }

    /// An export draws the block for paper: `ImageRenderer` cannot draw a scroll view or a button (it shows a "no entry"
    /// symbol), so long lines wrap and there is no copy button.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if export != nil { printedCode } else { scrollingCode }
        }
        .background(theme.codeBackground.color, in: RoundedRectangle(cornerRadius: 6))
    }

    private var header: some View {
        HStack {
            if let language {
                Text(language).font(.caption).foregroundStyle(theme.secondaryText.color)
            }
            Spacer()
            if export == nil { copyButton }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy code")
        .accessibilityLabel("Copy code")
    }

    private var scrollingCode: some View {
        ScrollView(.horizontal) {
            Text(styledCode)
                .font(.system(size: theme.codeFontSize, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize()
                .padding(12)
        }
    }

    private var printedCode: some View {
        Text(styledCode)
            .font(.system(size: theme.codeFontSize, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
    }
}
