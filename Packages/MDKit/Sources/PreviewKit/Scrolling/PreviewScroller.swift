import MarkdownCore
import Observation
import SwiftUI

/// Scrolls the preview by block and tells which block is at the top.
///
/// The preview is a `LazyVStack` of top-level blocks, each with its `BlockID` as view id. Jumping to an id is exact
/// at any distance, as long as it is not animated (an animated long jump lands a few blocks off). Reading is done
/// with `onScrollTargetVisibilityChange`; the `scrollPosition` binding only ever holds what was last written, so it
/// is never read. `onScrollPhaseChange` tells the user's scrolling from our own jumps, which report no phase.
/// The visibility callback is reliable while the user scrolls but not right after a jump, which is why `topBlock`
/// takes the target of a jump to the top as it is.
@MainActor
@Observable
public final class PreviewScroller {
    /// The first visible block, whatever moved it. nil until the preview has laid out.
    public private(set) var topBlock: BlockID?
    /// True while the user scrolls (wheel, trackpad, scroller, keys), until the scroll comes to rest.
    public private(set) var isUserScrolling = false

    /// The user scrolled and the first visible block changed; also when the scroll comes to rest on another one.
    @ObservationIgnored public var onUserScroll: ((BlockID) -> Void)?
    /// The preview moved itself to a block (a link, a search match): the window scrolls the editor to match.
    @ObservationIgnored public var onNavigate: ((BlockID) -> Void)?

    /// Installed by the preview view: scrolls its `ScrollView` to a block.
    @ObservationIgnored var jump: ((BlockID, UnitPoint) -> Void)?
    @ObservationIgnored private var order: [BlockID: Int] = [:]
    @ObservationIgnored private var firstBlock: BlockID?
    @ObservationIgnored private var lastReported: BlockID?

    public init() {}

    /// Puts `id` at the top of the preview. Does not report a user scroll.
    public func scroll(to id: BlockID) {
        scroll(to: id, anchor: .top)
    }

    /// The id of an empty view at the very top of the scrolled content. Jumping to it shows the preview's own top margin;
    /// jumping to the first block would hide it.
    static let topMarker = BlockID(UInt64.max)

    /// Scrolls to the very top, margin included.
    public func scrollToTop() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { jump?(Self.topMarker, .top) }
        if let firstBlock, topBlock != firstBlock { topBlock = firstBlock }
    }

    public func scroll(to id: BlockID, anchor: UnitPoint) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { jump?(id, anchor) }
        // The visibility callback is not reliable right after a jump (it can report nothing, or an in-between
        // state), so a jump to the top says where the top is.
        if anchor == .top, topBlock != id { topBlock = id }
    }

    // MARK: From the view

    func blocksChanged(_ blocks: [Block]) {
        firstBlock = blocks.first?.id
        order = Dictionary(blocks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func visibleBlocksChanged(_ ids: [BlockID]) {
        guard let first = ids.min(by: { (order[$0] ?? .max) < (order[$1] ?? .max) }) else { return }
        if topBlock != first { topBlock = first }
        if isUserScrolling { report(first) }
    }

    func phaseChanged(_ phase: ScrollPhase) {
        let scrolling = phase.isScrolling
        guard scrolling != isUserScrolling else { return }
        isUserScrolling = scrolling
        if scrolling {
            lastReported = nil
        } else if let topBlock {
            report(topBlock)   // the callback for the last step may have come before the scroll came to rest
        }
    }

    private func report(_ id: BlockID) {
        guard id != lastReported else { return }
        lastReported = id
        onUserScroll?(id)
    }
}
