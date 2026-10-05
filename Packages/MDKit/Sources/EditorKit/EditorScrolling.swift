import AppKit

/// Reads and sets the editor's scroll position by line.
///
/// TextKit 2 lays text out lazily, so a far line that was never laid out has a zero frame and the obvious
/// "ask for its y" jump lands at the top. What works (measured on a 1 MB document, exact in 60 of 60 jumps):
/// `scrollRangeToVisible` lays the region out, the viewport is laid out, the fragment's y is read, and the
/// clip view is moved there, a few times until it stops moving. The document height is re-estimated while
/// scrolling, which is why positions are lines, never offsets.
@MainActor
final class EditorScrollSupport {
    private weak var textView: NSTextView?
    private weak var scrollView: NSScrollView?
    /// UTF-16 location → 0-based line, and 0-based line → UTF-16 location, from the highlighter's line index.
    private let lineAt: (Int) -> Int
    private let locationOfLine: (Int) -> Int
    private let rangeOfLine: (Int) -> NSRange?
    private let report: (Int) -> Void

    nonisolated(unsafe) private var observer: NSObjectProtocol?
    private var isScrollingOurselves = false
    private var reportScheduled = false
    private var lastReported: Int?

    init(textView: NSTextView, scrollView: NSScrollView, lineAt: @escaping (Int) -> Int, locationOfLine: @escaping (Int) -> Int,
         rangeOfLine: @escaping (Int) -> NSRange?, report: @escaping (Int) -> Void) {
        self.textView = textView
        self.scrollView = scrollView
        self.lineAt = lineAt
        self.locationOfLine = locationOfLine
        self.rangeOfLine = rangeOfLine
        self.report = report
        scrollView.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.boundsDidChange() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// A 0-based line's range without its "\n".
    func contentRange(ofLine line: Int) -> NSRange? {
        rangeOfLine(line)
    }

    // MARK: Reading

    /// The 1-based line at the top of the visible area; nil while it cannot be told (the editor is hidden, or the
    /// viewport has not been laid out since the last scroll).
    var topLine: Int? {
        guard let textView, let scrollView, !scrollView.isHidden, scrollView.contentView.bounds.width > 1,
              let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager else { return nil }
        layoutManager.textViewportLayoutController.layoutViewport()
        guard let viewport = layoutManager.textViewportLayoutController.viewportRange else { return nil }
        let top = scrollView.contentView.bounds.minY - textView.textContainerOrigin.y
        var found: NSTextLocation?
        var visited = 0
        // Capped: if frames are not known, walking on would lay out the whole document.
        layoutManager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            visited += 1
            if fragment.layoutFragmentFrame.maxY > top + 0.5 {
                found = fragment.rangeInElement.location
                return false
            }
            return visited < 300
        }
        guard let found else { return nil }
        return lineAt(contentManager.offset(from: contentManager.documentRange.location, to: found)) + 1
    }

    // MARK: Moving

    /// Puts a 1-based line at the top of the visible area, at once, without telling `report`.
    func scroll(toLine line: Int) {
        guard let textView, let scrollView, !scrollView.isHidden,
              let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager else { return }
        let index = Swift.max(0, line - 1)
        let character = locationOfLine(index)
        guard let location = contentManager.location(contentManager.documentRange.location, offsetBy: character) else { return }
        isScrollingOurselves = true
        defer {
            isScrollingOurselves = false
            lastReported = topLine
        }
        func move(to y: CGFloat) {
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            layoutManager.textViewportLayoutController.layoutViewport()
        }
        if index == 0 {
            move(to: 0)
            return
        }
        textView.scrollRangeToVisible(NSRange(location: character, length: 0))
        layoutManager.textViewportLayoutController.layoutViewport()
        for _ in 0..<3 {
            guard let fragment = layoutManager.textLayoutFragment(for: location), fragment.layoutFragmentFrame.height > 0 else { break }
            let y = fragment.layoutFragmentFrame.minY + textView.textContainerOrigin.y
            if abs(scrollView.contentView.bounds.minY - y) < 0.5 { break }
            move(to: y)
        }
    }

    // MARK: Telling

    /// Any move of the clip view that was not ours (wheel, scroller, keys, the caret following typing).
    /// Reported once per run-loop turn, after AppKit has finished its own layout for it.
    private func boundsDidChange() {
        guard !isScrollingOurselves, !reportScheduled else { return }
        reportScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.reportTopLine() }
        }
    }

    private func reportTopLine() {
        reportScheduled = false
        guard let line = topLine, line != lastReported else { return }
        lastReported = line
        report(line)
    }
}
