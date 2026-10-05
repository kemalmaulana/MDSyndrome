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
    /// True when `rendered` is the parse of the latest text: no edit is waiting for its render. A click in the
    /// preview that refers to source lines (a task checkbox) is only safe then.
    var isCurrent: Bool { renderedGeneration == generation }
    var options: MarkdownOptions

    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let renderer: Renderer
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Bumped on every render request; a finished render is published only if it is still the latest.
    /// This also covers `renderNow`, whose task is not the cancellable `pending` one.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var renderedGeneration = 0

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
        generation += 1
        let request = generation
        pending = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.render(text, request: request)
        }
    }

    /// Renders now, cancelling any pending debounced render (initial load, tests).
    func renderNow(_ text: String) async {
        pending?.cancel()
        generation += 1
        await render(text, request: generation)
    }

    private func render(_ text: String, request: Int) async {
        let renderer = renderer
        let options = options
        let result = await Task.detached(priority: .userInitiated) { renderer(text, options) }.value
        guard request == generation else { return }
        rendered = result
        renderedGeneration = request
        renderCount += 1
    }
}
