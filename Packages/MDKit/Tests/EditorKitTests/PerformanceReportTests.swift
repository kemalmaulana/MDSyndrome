import AppKit
import Foundation
import Testing
@testable import EditorKit

/// `make perf`: what the editor costs on a 1 MB document (PRD NF-3). Prints numbers; only runs when `PERF` is set.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PERF"] != nil))
struct EditorPerformanceReportTests {
    @Test func keystrokeInTheMiddleOfOneMegabyte() {
        var text = ""
        for i in 0..<20_000 { text += "Line \(i) with *emphasis*, `code` and a [link](https://example.com/\(i)).\n" }
        let clock = ContinuousClock()

        let storage = NSTextStorage(string: text)
        let highlighter = EditorHighlighter(theme: .tomorrowPlus, configuration: .macDownDefaults)
        let load = clock.measure {
            highlighter.attach(to: storage)
        }
        highlighter.finishPending()

        let keys = 200
        let typing = clock.measure {
            for i in 0..<keys { storage.replaceCharacters(in: NSRange(location: 400_000 + i, length: 0), with: "x") }
        }
        print("PERF NF-3 first highlight pass (\(text.utf8.count) bytes): \(load); keystroke in the middle: \(typing / keys) each")
    }
}
