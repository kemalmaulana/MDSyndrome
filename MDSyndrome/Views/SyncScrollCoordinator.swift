import EditorKit
import Foundation
import MarkdownCore
import PreviewKit

@MainActor
protocol EditorScrolling: AnyObject {
    /// The 1-based line at the top of the editor; nil while it cannot be told.
    var topLine: Int? { get }
    func scroll(toLine line: Int)
    /// Called with the top line after the editor scrolled for any reason but `scroll(toLine:)`.
    var onScroll: ((Int) -> Void)? { get set }
}

@MainActor
protocol PreviewScrolling: AnyObject {
    func scroll(to id: BlockID)
    /// Called when the user (not a jump) scrolled the preview and the first visible block changed.
    var onUserScroll: ((BlockID) -> Void)? { get set }
}

extension EditorController: EditorScrolling {}
extension PreviewScroller: PreviewScrolling {}

/// Keeps the editor and the preview at the same place in the document (PRD NAV-2), block by block.
///
/// The user moves one pane and the other follows; a pane that is only following never moves the first one back.
/// Three things keep that from looping or jittering:
/// - the editor masks its own scrolls and the preview reports only the user's (a jump reports no scroll phase), so
///   a jump is not mistaken for the user;
/// - what is left, a late report that lands where we just jumped (TextKit re-estimates heights after a jump, a
///   different OS may report a jump as a scroll), is recognised by position for a short while and ignored;
/// - nothing is scrolled to where it already is.
@MainActor
final class SyncScrollCoordinator {
    /// Who moved last. The pane that was moved by the user is the one the other follows.
    enum Driver: Equatable {
        case none, editor, preview
    }

    /// A late report within this long of a jump, near where we jumped, is our own echo.
    static let echoWindow: Duration = .milliseconds(400)
    /// How far from the jumped-to line the editor may settle and still count as an echo (TextKit's re-estimation).
    static let echoLineTolerance = 3

    var isEnabled = true {
        didSet { if isEnabled, !oldValue { catchUp() } }
    }
    private(set) var driver: Driver = .none

    private weak var editor: (any EditorScrolling)?
    private weak var preview: (any PreviewScrolling)?
    private var sourceMap = SourceMap.empty
    private var editorIsVisible = true
    private var previewIsVisible = true
    /// The block the preview is on, as far as we know: where we last put it, or where the user last scrolled it to.
    /// The preview's own report is not asked: it can be stale right after a jump.
    private var previewBlock: BlockID?
    private var editorEcho: (line: Int, until: ContinuousClock.Instant)?
    private var previewEcho: (id: BlockID, until: ContinuousClock.Instant)?
    private let clock: () -> ContinuousClock.Instant
    private let afterLayout: (@escaping @MainActor () -> Void) -> Void

    /// - Parameters:
    ///   - clock: for the echo window; tests move time by hand.
    ///   - afterLayout: runs `catch-up work` once SwiftUI and AppKit have laid out a pane that just appeared.
    init(clock: @escaping () -> ContinuousClock.Instant = { .now },
         afterLayout: @escaping (@escaping @MainActor () -> Void) -> Void = { work in
             DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(50)) { MainActor.assumeIsolated { work() } }
         }) {
        self.clock = clock
        self.afterLayout = afterLayout
    }

    func attach(editor: any EditorScrolling, preview: any PreviewScrolling) {
        self.editor = editor
        self.preview = preview
        editor.onScroll = { [weak self] line in self?.editorDidScroll(line) }
        preview.onUserScroll = { [weak self] id in self?.previewDidScroll(id) }
    }

    // MARK: From the window

    /// A new parse arrived. The preview's content may have moved under its scroll position, so while the user is
    /// working in the editor it is put back on the editor's line.
    func renderDidChange(_ map: SourceMap) {
        sourceMap = map
        guard isActive, driver != .preview else { return }
        syncPreviewToEditor()
    }

    func layoutDidChange(editorVisible: Bool, previewVisible: Bool) {
        let appeared = (editorVisible && !editorIsVisible) || (previewVisible && !previewIsVisible)
        editorIsVisible = editorVisible
        previewIsVisible = previewVisible
        if appeared { afterLayout { [weak self] in self?.catchUp() } }
    }

    /// The user clicked or typed in the editor: it leads from here on.
    func editorActivity() {
        driver = .editor
    }

    /// The outline, a link or a search match took the window to a block: both panes go there, whether or not
    /// scrolling together is on.
    func navigate(to id: BlockID) {
        driver = .none
        if previewIsVisible {
            previewBlock = id
            previewEcho = (id, clock() + Self.echoWindow)
            preview?.scroll(to: id)
        }
        if editorIsVisible, let line = sourceMap.startLine(of: id) { scrollEditor(toLine: line) }
    }

    // MARK: From the panes

    private var isActive: Bool { isEnabled && editorIsVisible && previewIsVisible }

    func editorDidScroll(_ line: Int) {
        guard isActive else { return }
        if let echo = editorEcho, clock() < echo.until, abs(line - echo.line) <= Self.echoLineTolerance { return }
        driver = .editor
        scrollPreview(toLine: line)
    }

    func previewDidScroll(_ id: BlockID) {
        guard isActive else { return }
        if let echo = previewEcho, clock() < echo.until, echo.id == id { return }
        driver = .preview
        previewBlock = id
        if let line = sourceMap.startLine(of: id) { scrollEditor(toLine: line) }
    }

    // MARK: Moving

    private func scrollPreview(toLine line: Int) {
        guard let id = sourceMap.blockID(atLine: line), id != previewBlock else { return }
        previewBlock = id
        previewEcho = (id, clock() + Self.echoWindow)
        preview?.scroll(to: id)
    }

    private func scrollEditor(toLine line: Int) {
        guard let editor, editor.topLine != line else { return }
        editorEcho = (line, clock() + Self.echoWindow)
        editor.scroll(toLine: line)
    }

    /// Brings the pane that was not the leader up to date: after a pane appeared, or sync was turned on.
    private func catchUp() {
        guard isActive else { return }
        if driver == .preview {
            if let id = previewBlock, let line = sourceMap.startLine(of: id) { scrollEditor(toLine: line) }
        } else {
            syncPreviewToEditor()
        }
    }

    private func syncPreviewToEditor() {
        guard let line = editor?.topLine else { return }
        previewBlock = nil   // the blocks may be new ones
        scrollPreview(toLine: line)
    }
}
