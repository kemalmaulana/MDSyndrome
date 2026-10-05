import MarkdownCore
import Observation
import SwiftUI

/// Find-in-preview state for one window: the query, where it matches, and which match is current.
/// The preview reads it to colour matches and to scroll; the search bar and the Find menu drive it.
@MainActor
@Observable
public final class PreviewSearch {
    /// Matches kept per search. A 1 MB document searched for "e" would otherwise hold hundreds of thousands.
    nonisolated public static let maxMatches = 5_000

    public private(set) var isPresented = false
    public var query = ""
    public var caseSensitive = false

    public private(set) var matches: [SearchMatch] = []
    public private(set) var currentIndex: Int?
    public private(set) var isTruncated = false
    /// Bumped when the preview should scroll to the current match.
    public private(set) var revealToken = 0
    /// Bumped when the search field should take keyboard focus (⌘F again while the bar is open).
    public private(set) var focusToken = 0

    /// The matches of each run, for the views.
    private(set) var rangesByRun: [SearchRunKey: [Range<Int>]] = [:]

    @ObservationIgnored private var blocks: [Block] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let debounce: Duration

    public init(debounce: Duration = .milliseconds(80)) {
        self.debounce = debounce
    }

    public var currentMatch: SearchMatch? {
        currentIndex.map { matches[$0] }
    }

    /// "3 of 12", "No results", or nothing while the query is empty.
    public var status: String {
        if query.isEmpty { return "" }
        guard let currentIndex else { return "No results" }
        return "\(currentIndex + 1) of \(matches.count)\(isTruncated ? "+" : "")"
    }

    // MARK: Driving

    public func show() {
        isPresented = true
        focusToken += 1
        if !query.isEmpty { refresh(resetCurrent: false) }
    }

    public func close() {
        isPresented = false
        pending?.cancel()
        generation += 1
        apply(matches: [], truncated: false, resetCurrent: true, reveal: false)
    }

    public func next() { step(+1) }
    public func previous() { step(-1) }

    private func step(_ direction: Int) {
        guard isPresented else { return show() }
        guard let currentIndex, !matches.isEmpty else { return }
        self.currentIndex = (currentIndex + direction + matches.count) % matches.count
        revealToken += 1
    }

    /// The document changed (or the preview just appeared).
    public func update(blocks: [Block]) {
        self.blocks = blocks
        if isPresented, !query.isEmpty { refresh(resetCurrent: false) }
    }

    /// Search again after the query or the case option changed.
    public func queryChanged() {
        refresh(resetCurrent: true)
    }

    /// Waits for the search in flight. For tests.
    func settle() async {
        await pending?.value
    }

    private func refresh(resetCurrent: Bool) {
        pending?.cancel()
        generation += 1
        let mine = generation
        let query = self.query
        let caseSensitive = self.caseSensitive
        let blocks = self.blocks
        let limit = Self.maxMatches
        guard isPresented, !query.isEmpty else {
            return apply(matches: [], truncated: false, resetCurrent: true, reveal: false)
        }
        pending = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                SearchIndex.search(query: query, caseSensitive: caseSensitive, in: blocks, limit: limit)
            }.value
            guard !Task.isCancelled, mine == generation else { return }
            apply(matches: found.matches, truncated: found.truncated, resetCurrent: resetCurrent, reveal: resetCurrent)
        }
    }

    private func apply(matches: [SearchMatch], truncated: Bool, resetCurrent: Bool, reveal: Bool) {
        self.matches = matches
        isTruncated = truncated
        var grouped: [SearchRunKey: [Range<Int>]] = [:]
        for match in matches { grouped[match.key, default: []].append(match.range) }
        rangesByRun = grouped
        if matches.isEmpty {
            currentIndex = nil
        } else if resetCurrent {
            currentIndex = 0
        } else {
            currentIndex = min(currentIndex ?? 0, matches.count - 1)
        }
        if reveal, currentIndex != nil { revealToken += 1 }
    }

    // MARK: For the views

    func highlights(for key: SearchRunKey) -> [SearchHighlight] {
        guard let ranges = rangesByRun[key] else { return [] }
        let current = currentMatch
        return ranges.enumerated().map { index, range in
            SearchHighlight(range: range, isCurrent: current?.key == key && current?.indexInRun == index)
        }
    }
}

extension EnvironmentValues {
    /// The window's find-in-preview state; nil where search is not offered.
    @Entry var previewSearch: PreviewSearch? = nil
    /// First source line of the block being drawn: with a slot it names a run of text for search.
    @Entry var searchLine: Int = 0
}
