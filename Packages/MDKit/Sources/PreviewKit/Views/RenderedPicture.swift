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
    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case loaded(NSImage)
        case failed(RenderError)
    }

    var body: some View {
        Group {
            switch phase {
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
        .task(id: request) { await load() }
    }

    private func load() async {
        guard let renderer else { return phase = .failed(.unavailable("No renderer")) }
        if debounce > .zero {
            try? await Task.sleep(for: debounce)
            if Task.isCancelled { return }
        }
        do {
            let rendered = try await renderer.render(request)
            if Task.isCancelled { return }
            if let image = NSImage(data: rendered.pdf), image.size.width > 0 {
                phase = .loaded(image)
            } else {
                phase = .failed(.unavailable("The picture could not be read"))
            }
        } catch let error as RenderError {
            if !Task.isCancelled { phase = .failed(error) }
        } catch {
            // Cancelled with the view; nothing to show.
        }
    }
}
