import AppKit
import SwiftUI
import WebRenderKit

/// A picture from the web renderer: a placeholder while it draws, the picture, or whatever `failure`
/// shows when the renderer rejects the source. It asks again whenever the request changes (new source,
/// light or dark), and keeps showing the old picture until the new one arrives.
struct RenderedPicture<Failure: View>: View {
    let request: RenderRequest
    let accessibilityLabel: String
    var alignment: Alignment = .center
    var placeholderHeight: CGFloat = 80
    /// Waits this long before asking, so dragging a window edge does not queue a render per pixel.
    var debounce: Duration = .zero
    @ViewBuilder let failure: (RenderError) -> Failure

    @Environment(\.webRenderer) private var renderer
    @State private var loader = PictureLoader()

    var body: some View {
        Group {
            switch loader.phase {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: placeholderHeight, alignment: alignment)
                    .accessibilityLabel("Drawing")
            case .loaded(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: image.size.width)
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityAddTraits(.isImage)
            case .failed(let error):
                failure(error)
            }
        }
        .task(id: request) { await loader.load(request, using: renderer, debounce: debounce) }
    }
}
