import AppKit
import SwiftUI
import WebRenderKit

/// A picture from the web renderer: a placeholder while it draws, the picture, or whatever `failure`
/// shows when the renderer rejects the source. It asks again whenever the request changes (new source,
/// light or dark), and keeps showing the old picture until the new one arrives.
///
/// While a document is drawn for export (`\.exportResources` is set) nothing is fetched: the picture was
/// prepared beforehand and is looked up by its request.
struct RenderedPicture<Failure: View>: View {
    let request: RenderRequest
    let accessibilityLabel: String
    var alignment: Alignment = .center
    var placeholderHeight: CGFloat = 80
    /// Waits this long before asking, so dragging a window edge does not queue a render per pixel.
    var debounce: Duration = .zero
    @ViewBuilder let failure: (RenderError) -> Failure

    @Environment(\.webRenderer) private var renderer
    @Environment(\.exportResources) private var export
    @State private var loader = PictureLoader()

    var body: some View {
        if let export {
            exported(export.pictures[request])
        } else {
            live
        }
    }

    private var live: some View {
        Group {
            switch loader.phase {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: placeholderHeight, alignment: alignment)
                    .accessibilityLabel("Drawing")
            case .loaded(let image):
                picture(image)
            case .failed(let error):
                failure(error)
            }
        }
        .task(id: request) { await loader.load(request, using: renderer, debounce: debounce) }
    }

    @ViewBuilder
    private func exported(_ outcome: ExportResources.Outcome?) -> some View {
        switch outcome {
        case .picture(let rendered)?:
            if let image = NSImage(data: rendered.pdf), image.size.width > 0 {
                picture(image)
            } else {
                failure(.unavailable("The picture could not be read"))
            }
        case .failed(let error)?:
            failure(error)
        case nil:
            failure(.unavailable("Not prepared for export"))
        }
    }

    private func picture(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: image.size.width)
            .frame(maxWidth: .infinity, alignment: alignment)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isImage)
    }
}
