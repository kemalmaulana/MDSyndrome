import AppKit
import SwiftUI
import SyntaxHighlighting

struct CodeBlockView: View {
    let language: String?
    let code: String
    @Environment(\.previewTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language {
                    Text(language).font(.caption).foregroundStyle(theme.secondaryText.color)
                }
                if isDiagram {
                    Text("Diagram preview arrives in a later version")
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryText.color)
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
                Text(SyntaxStyler.attributed(code, language: language, theme: theme))
                    .font(.system(size: theme.codeFontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(12)
            }
        }
        .background(theme.codeBackground.color, in: RoundedRectangle(cornerRadius: 6))
    }

    /// Mermaid / Graphviz fences render as diagrams once WebRenderKit lands (Plan 3).
    private var isDiagram: Bool {
        ["mermaid", "dot", "graphviz"].contains(language?.lowercased() ?? "")
    }
}
