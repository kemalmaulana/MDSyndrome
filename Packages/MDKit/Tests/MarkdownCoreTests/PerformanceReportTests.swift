import Foundation
import Testing
@testable import MarkdownCore

/// `make perf`: parse time for a 1 MB document built from the kitchen sink (PRD NF-4). Not a regression gate; it prints
/// the numbers that go in the README, and only runs when `PERF` is set.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PERF"] != nil))
struct PerformanceReportTests {
    /// The kitchen sink repeated until it is `bytes` long.
    static func largeDocument(bytes: Int = 1_000_000) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }   // Tests/MarkdownCoreTests/File.swift → Packages/MDKit/Tests → … → repo root
        let unit = try String(contentsOf: url.appendingPathComponent("Fixtures/kitchen-sink.md"), encoding: .utf8) + "\n\n"
        var text = ""
        while text.utf8.count < bytes { text += unit }
        return text
    }

    @Test func parseOneMegabyte() throws {
        let text = try Self.largeDocument()
        let clock = ContinuousClock()
        var best = Duration.seconds(1_000)
        for _ in 0..<3 { best = min(best, clock.measure { _ = MarkdownPipeline.render(text, options: .default) }) }
        print("PERF parse 1 MB (\(text.utf8.count) bytes, \(MarkdownPipeline.render(text, options: .default).document.blocks.count) blocks): \(best)")
    }
}
