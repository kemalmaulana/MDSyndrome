import AppKit
import SwiftUI
import SyntaxHighlighting

struct CodeBlockView: View {
    let language: String?
    let code: String
    @Environment(\.previewTheme) private var theme
    @Environment(\.previewSearch) private var search
    @Environment(\.searchLine) private var searchLine

    private var styledCode: AttributedString {
        var styled = SyntaxStyler.attributed(code, language: language, theme: theme)
        let highlights = search?.highlights(for: SearchRunKey(line: searchLine, slot: 0)) ?? []
        if !highlights.isEmpty { styled.applySearchHighlights(highlights, offset: 0, theme: theme) }
        return styled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language {
                    Text(language).font(.caption).foregroundStyle(theme.secondaryText.color)
                }
                Spacer()
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
            .padding(.horizontal, 12)
            .padding(.top, 8)
            ScrollView(.horizontal) {
                Text(styledCode)
                    .font(.system(size: theme.codeFontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(12)
            }
        }
        .background(theme.codeBackground.color, in: RoundedRectangle(cornerRadius: 6))
    }
}
