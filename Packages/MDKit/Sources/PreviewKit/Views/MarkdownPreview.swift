import MarkdownCore
import SwiftUI

/// The rendered document. Pure SwiftUI: one view per top-level block, each
/// tagged with its BlockID so sync-scroll can target it later.
public struct MarkdownPreview: View {
    private let rendered: RenderedDocument
    private let baseURL: URL?
    private let theme: PreviewTheme

    public init(rendered: RenderedDocument, baseURL: URL?, theme: PreviewTheme = .github) {
        self.rendered = rendered
        self.baseURL = baseURL
        self.theme = theme
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
                ForEach(rendered.document.blocks) { block in
                    BlockView(block: block).id(block.id)
                }
            }
            .frame(maxWidth: theme.maxContentWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .font(.system(size: theme.bodyFontSize))
        .foregroundStyle(theme.text.color)
        .background(theme.background.color)
        .environment(\.previewTheme, theme)
        .environment(\.documentBaseURL, baseURL)
        .environment(\.openURL, OpenURLAction { url in
            LinkPolicy.decision(for: url) == .openExternally ? .systemAction : .discarded
        })
        .accessibilityIdentifier("markdown-preview")
    }
}
