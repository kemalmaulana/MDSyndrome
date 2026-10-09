import MarkdownCore
import SwiftUI
import WebRenderKit

/// Which fence languages are drawn as diagrams.
enum DiagramLanguage {
    static func kind(of language: String?) -> RenderKind? {
        switch language?.lowercased() {
        case "mermaid": .mermaid
        case "dot", "graphviz": .graphviz
        default: nil
        }
    }
}

/// A ```` ```mermaid ````, ```` ```dot ```` or ```` ```graphviz ```` block. With a renderer it is a picture; if
/// the source is wrong, the library's message sits above the source; without a renderer it is a code block.
struct DiagramBlockView: View {
    let kind: RenderKind
    let language: String?
    let code: String
    @Environment(\.previewTheme) private var theme
    @Environment(\.webRenderer) private var renderer
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if renderer == nil || code.allSatisfy(\.isWhitespace) {
            CodeBlockView(language: language, code: code)
        } else {
            RenderedPicture(request: request, accessibilityLabel: "Diagram: \(firstLine)", alignment: .center, placeholderHeight: 120) { error in
                VStack(alignment: .leading, spacing: 6) {
                    Label(error.summary, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(theme.error.color)
                        .help(error.fullMessage)
                        .accessibilityLabel("Diagram error: \(error.summary)")
                    CodeBlockView(language: language, code: code)
                }
            }
        }
    }

    private var request: RenderRequest {
        PictureRequests.diagram(kind, code: code, theme: theme, scheme: scheme)
    }

    private var firstLine: String {
        String(code.split(whereSeparator: \.isNewline).first ?? "")
    }
}
