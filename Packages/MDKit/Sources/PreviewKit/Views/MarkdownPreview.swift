import MarkdownCore
import SwiftUI
import WebRenderKit

/// The rendered document. Pure SwiftUI: one view per top-level block, each
/// tagged with its BlockID so sync-scroll can target it later.
public struct MarkdownPreview: View {
    private let rendered: RenderedDocument
    private let baseURL: URL?
    private let theme: PreviewTheme
    private let reloadToken: Int
    private let search: PreviewSearch?
    private let webRenderer: (any WebRendering)?
    private let scroller: PreviewScroller?
    @State private var ownScroller = PreviewScroller()

    private var activeScroller: PreviewScroller { scroller ?? ownScroller }

    /// - Parameters:
    ///   - reloadToken: change it to make images load again (the document was reloaded from disk).
    ///   - search: the window's find-in-preview state; nil turns find off.
    ///   - webRenderer: draws diagrams, KaTeX fallback formulas and complex HTML; nil shows their source.
    ///   - scroller: lets the window scroll the preview by block and ask which block is at the top; the preview
    ///     makes its own when there is none.
    public init(rendered: RenderedDocument, baseURL: URL?, theme: PreviewTheme = .github, reloadToken: Int = 0, search: PreviewSearch? = nil,
                webRenderer: (any WebRendering)? = nil, scroller: PreviewScroller? = nil) {
        self.rendered = rendered
        self.baseURL = baseURL
        self.theme = theme
        self.reloadToken = reloadToken
        self.search = search
        self.webRenderer = webRenderer
        self.scroller = scroller
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
                    ForEach(rendered.document.blocks) { block in
                        BlockView(block: block).id(block.id)
                    }
                }
                .scrollTargetLayout()
                .frame(maxWidth: theme.maxContentWidth, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .onScrollTargetVisibilityChange(idType: BlockID.self, threshold: 0.01) { activeScroller.visibleBlocksChanged($0) }
            .onScrollPhaseChange { _, phase in activeScroller.phaseChanged(phase) }
            .onAppear { activeScroller.jump = { id, anchor in proxy.scrollTo(id, anchor: anchor) } }
            .onChange(of: search?.revealToken) { _, _ in
                guard let target = search?.currentMatch?.topLevel else { return }
                activeScroller.scroll(to: target, anchor: .center)
                activeScroller.onNavigate?(target)
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
        .environment(\.webRenderer, webRenderer)
        .environment(\.openURL, OpenURLAction { url in
            LinkPolicy.decision(for: url) == .openExternally ? .systemAction : .discarded
        })
        .onChange(of: rendered.document.blocks, initial: true) { _, blocks in
            activeScroller.blocksChanged(blocks)
            search?.update(blocks: blocks)
        }
        .accessibilityIdentifier("markdown-preview")
    }
}
