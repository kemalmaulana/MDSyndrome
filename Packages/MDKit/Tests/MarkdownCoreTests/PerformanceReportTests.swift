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

    @Test func parseTimes() throws {
        for bytes in [200_000, 1_000_000] {
            let text = try Self.largeDocument(bytes: bytes)
            let clock = ContinuousClock()
            var best = Duration.seconds(1_000)
            for _ in 0..<3 { best = min(best, clock.measure { _ = MarkdownPipeline.render(text, options: .default) }) }
            print("PERF NF-4 parse \(text.utf8.count / 1_000) KB (\(MarkdownPipeline.render(text, options: .default).document.blocks.count) blocks): \(best)")
        }
    }

    /// A changelog-like document: headings, bullets and short paragraphs, the shape of most long Markdown files.
    @Test func parseProse() {
        var text = ""
        var n = 0
        while text.utf8.count < 1_000_000 {
            n += 1
            text += "## Release 1.\(n)\n\n- Fixed a crash when *opening* a file with `long` names (#\(n))\n- Added [a link](https://example.com/\(n)) and **bold** text\n- Changed the default for option \(n)\n\nA short paragraph that explains the release in a sentence or two, with a [reference](https://example.com).\n\n"
        }
        let clock = ContinuousClock()
        var best = Duration.seconds(1_000)
        for _ in 0..<3 { best = min(best, clock.measure { _ = MarkdownPipeline.render(text, options: .default) }) }
        print("PERF NF-4 parse prose \(text.utf8.count / 1_000) KB (\(n) releases): \(best)")
    }
}
