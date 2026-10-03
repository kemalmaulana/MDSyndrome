import MarkdownCore
import Observation

/// Per-window state: turns editor text into a RenderedDocument.
/// Parsing runs off the main actor; rapid edits are coalesced by a debounce.
@MainActor
@Observable
final class DocumentSession {
    typealias Renderer = @Sendable (String, MarkdownOptions) -> RenderedDocument

    private(set) var rendered: RenderedDocument = .empty
    /// How many renders have been published. Used by tests.
    private(set) var renderCount = 0
    var options: MarkdownOptions

    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let renderer: Renderer
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(
        options: MarkdownOptions = .default,
        debounce: Duration = .milliseconds(120),
        renderer: @escaping Renderer = { MarkdownPipeline.render($0, options: $1) }
    ) {
        self.options = options
        self.debounce = debounce
        self.renderer = renderer
    }

    /// Call on every edit. Only the last edit inside the debounce window is rendered.
    func textDidChange(_ text: String) {
        pending?.cancel()
        pending = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.render(text)
        }
    }

    /// Renders now, cancelling any pending debounced render (initial load, tests).
    func renderNow(_ text: String) async {
        pending?.cancel()
        await render(text)
    }

    private func render(_ text: String) async {
        let renderer = renderer
        let options = options
        let result = await Task.detached(priority: .userInitiated) { renderer(text, options) }.value
        guard !Task.isCancelled else { return }
        rendered = result
        renderCount += 1
    }
}
