import Foundation

/// Least-recently-used results, bounded by count and by bytes. Syntax errors are kept too, so a broken
/// diagram is not sent to the web view again on every SwiftUI update.
struct RenderCache {
    enum Entry {
        case image(RenderedImage)
        case syntaxError(String)

        var cost: Int {
            switch self {
            case .image(let image): image.pdf.count
            case .syntaxError(let message): message.utf8.count
            }
        }
    }

    private let countLimit: Int
    private let byteLimit: Int
    private var entries: [RenderRequest: Entry] = [:]
    /// Least recently used first.
    private var order: [RenderRequest] = []
    private var bytes = 0

    init(countLimit: Int = 64, byteLimit: Int = 32 * 1_024 * 1_024) {
        self.countLimit = countLimit
        self.byteLimit = byteLimit
    }

    var count: Int { entries.count }

    mutating func entry(for request: RenderRequest) -> Entry? {
        guard let entry = entries[request] else { return nil }
        touch(request)
        return entry
    }

    mutating func insert(_ entry: Entry, for request: RenderRequest) {
        if let old = entries[request] { bytes -= old.cost }
        entries[request] = entry
        bytes += entry.cost
        touch(request)
        while (entries.count > countLimit || bytes > byteLimit), let oldest = order.first, oldest != request {
            order.removeFirst()
            if let removed = entries.removeValue(forKey: oldest) { bytes -= removed.cost }
        }
    }

    mutating func removeAll() {
        entries = [:]
        order = []
        bytes = 0
    }

    private mutating func touch(_ request: RenderRequest) {
        if let index = order.firstIndex(of: request) { order.remove(at: index) }
        order.append(request)
    }
}
