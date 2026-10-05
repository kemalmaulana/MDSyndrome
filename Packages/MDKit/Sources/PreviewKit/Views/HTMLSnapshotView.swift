import SwiftUI
import WebRenderKit

/// A raw HTML block the native subset cannot show, drawn as a picture by the snapshot web view (JavaScript
/// off, no network). Local and remote images are read here first and handed over as `data:` URIs. If it
/// cannot be drawn, the source is shown as before.
struct HTMLSnapshotView: View {
    let html: String
    @Environment(\.previewTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.documentBaseURL) private var baseURL
    @Environment(\.previewReloadToken) private var reloadToken
    @State private var width: Double = 0
    @State private var prepared: String?

    private struct PrepareKey: Hashable {
        let html: String
        let baseURL: URL?
        let reloadToken: Int
    }

    var body: some View {
        Group {
            if let prepared, width > 0 {
                RenderedPicture(request: request(for: prepared), accessibilityLabel: spokenText, alignment: .leading,
                                placeholderHeight: 40, debounce: .milliseconds(150)) { _ in
                    source
                }
            } else {
                Color.clear.frame(height: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Laid out at a multiple of 40 pt, so resizing the window does not draw a picture per pixel.
        .onGeometryChange(for: Double.self) { max(120, floor($0.size.width / 40) * 40) } action: { width = $0 }
        .task(id: PrepareKey(html: html, baseURL: baseURL, reloadToken: reloadToken)) {
            prepared = await HTMLImageInliner.inline(html, baseURL: baseURL, reload: reloadToken > 0)
        }
    }

    private func request(for body: String) -> RenderRequest {
        RenderRequest(kind: .html, source: body, appearance: RenderAppearance(scheme), foreground: theme.text.hex(for: scheme),
                      background: theme.background.hex(for: scheme), fontSize: theme.bodyFontSize, width: width, style: theme.htmlStyleSheet(for: scheme))
    }

    private var source: some View {
        Text(html)
            .font(.system(size: theme.codeFontSize, design: .monospaced))
            .foregroundStyle(theme.secondaryText.color)
            .textSelection(.enabled)
    }

    /// The block's text without its tags, for VoiceOver.
    private var spokenText: String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
