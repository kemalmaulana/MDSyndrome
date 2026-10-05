import MarkdownCore
import SwiftUI

/// The rendered document. Pure SwiftUI: one view per top-level block, each
/// tagged with its BlockID so sync-scroll can target it later.
public struct MarkdownPreview: View {
    private let rendered: RenderedDocument
    private let baseURL: URL?
    private let theme: PreviewTheme
    private let reloadToken: Int
    private let search: PreviewSearch?

    /// - Parameters:
    ///   - reloadToken: change it to make images load again (the document was reloaded from disk).
    ///   - search: the window's find-in-preview state; nil turns find off.
    public init(rendered: RenderedDocument, baseURL: URL?, theme: PreviewTheme = .github, reloadToken: Int = 0, search: PreviewSearch? = nil) {
        self.rendered = rendered
        self.baseURL = baseURL
        self.theme = theme
        self.reloadToken = reloadToken
        self.search = search
    }

    public var body: some View {
        ScrollViewReader { proxy in
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
            .onChange(of: search?.revealToken) { _, _ in
                guard let target = search?.currentMatch?.topLevel else { return }
                withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(target, anchor: .center) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let search, search.isPresented { PreviewSearchBar(search: search) }
        }
        .font(.system(size: theme.bodyFontSize))
        .foregroundStyle(theme.text.color)
        .background(theme.background.color)
        .environment(\.previewTheme, theme)
        .environment(\.documentBaseURL, baseURL)
        .environment(\.previewReloadToken, reloadToken)
        .environment(\.previewSearch, search)
        .environment(\.openURL, OpenURLAction { url in
            LinkPolicy.decision(for: url) == .openExternally ? .systemAction : .discarded
        })
        .onChange(of: rendered.document.blocks, initial: true) { _, blocks in search?.update(blocks: blocks) }
        .accessibilityIdentifier("markdown-preview")
    }
}
