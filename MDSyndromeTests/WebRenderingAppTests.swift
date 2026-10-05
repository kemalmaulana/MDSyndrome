import AppKit
import Foundation
import Testing
@testable import MDSyndrome

@MainActor
@Suite struct AppBundleTests {
    @Test func theBuiltAppCarriesExactlyTheVendoredScriptsAndOurBridge() throws {
        // NF-1: `find MDSyndrome.app -name '*.js'` lists only the three libraries and bridge.js.
        let enumerator = try #require(FileManager.default.enumerator(at: Bundle.main.bundleURL, includingPropertiesForKeys: nil))
        var scripts: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "js" { scripts.insert(url.lastPathComponent) }
        #expect(scripts == ["mermaid.min.js", "viz-global.js", "katex.min.js", "bridge.js"], "\(scripts.sorted())")
    }
}

/// The real app: WebKit starts when a document needs it and not before (NF-1). The renderer's hidden window
/// is the visible sign of a started web view. Opens real document windows, so it runs locally only.
@MainActor
@Suite(.notOnCI) struct WebKitStartsLazilyTests {
    private func hiddenRendererWindows() -> Int {
        NSApp.windows.filter { String(reflecting: type(of: $0)).contains("OffscreenWindow") }.count
    }

    private func open(_ text: String) async throws -> NSDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lazy-\(UUID().uuidString).md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let (document, _) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
        return document
    }

    @Test func aPlainDocumentNeverStartsWebKitAndADiagramDoes() async throws {
        let plain = try await open("# Plain\n\nText, `code`, a table:\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nand math $x^2$ and $$\\int_0^1 x\\,dx$$\n")
        try await Task.sleep(for: .seconds(2))
        #expect(hiddenRendererWindows() == 0, "nothing in this document needs a web view")
        plain.close()

        let diagram = try await open("# Diagram\n\n```mermaid\nflowchart LR\n  A --> B\n```\n")
        defer { diagram.close() }
        let deadline = ContinuousClock.now + .seconds(20)
        while hiddenRendererWindows() == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        #expect(hiddenRendererWindows() == 1, "the first diagram starts the one hidden web view")
    }
}
