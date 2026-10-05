import AppKit
import Observation
import WebRenderKit

/// The state of one picture on its way from the web renderer to the screen. The view shows `phase`; the
/// logic lives here so it can be tested without a window.
@MainActor
@Observable
final class PictureLoader {
    enum Phase {
        case loading
        case loaded(NSImage)
        case failed(RenderError)
    }

    private(set) var phase: Phase = .loading

    /// Asks `renderer` for `request`. The previous picture stays up until the new one arrives or fails, so
    /// switching between light and dark does not flash a spinner. A cancelled load changes nothing.
    func load(_ request: RenderRequest, using renderer: (any WebRendering)?, debounce: Duration = .zero) async {
        guard let renderer else { return phase = .failed(.unavailable("No renderer")) }
        if debounce > .zero {
            try? await Task.sleep(for: debounce)
            if Task.isCancelled { return }
        }
        do {
            let rendered = try await renderer.render(request)
            if Task.isCancelled { return }
            if let image = NSImage(data: rendered.pdf), image.size.width > 0, image.size.height > 0 {
                phase = .loaded(image)
            } else {
                phase = .failed(.unavailable("The picture could not be read"))
            }
        } catch let error as RenderError {
            if !Task.isCancelled { phase = .failed(error) }
        } catch {
            // Cancelled together with the view: nothing to show.
        }
    }
}
