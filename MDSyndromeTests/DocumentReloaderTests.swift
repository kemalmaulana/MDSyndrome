import AppKit
import Foundation
import Testing
@testable import MDSyndrome

/// These open real document windows in the hosted app (briefly, on the screen), so they run locally only.
@MainActor
@Suite(.notOnCI) struct DocumentReloaderTests {
    private func temporaryFile(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reload-\(UUID().uuidString).md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func editor(in document: NSDocument) -> NSTextView? {
        func search(_ view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView, textView.accessibilityIdentifier() == "markdown-editor" { return textView }
            return view.subviews.lazy.compactMap(search).first
        }
        return document.windowControllers.first?.window?.contentView.flatMap(search)
    }

    private func waitUntil(_ what: String, seconds: Double = 5, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !condition() {
            guard ContinuousClock.now < deadline else { Issue.record("timed out waiting for \(what)"); return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func open(_ url: URL) async throws -> (NSDocument, NSTextView) {
        let (document, _) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
        var found: NSTextView?
        try await waitUntil("the editor to appear") { found = editor(in: document); return found != nil }
        let textView = try #require(found)
        try await waitUntil("the file text to show") { !textView.string.isEmpty }
        // SwiftUI finishes reading a freshly opened file a moment later; a revert before that fails with
        // "isn't in the correct format". Nobody presses ⌘R within a second of opening a file.
        try await Task.sleep(for: .seconds(1))
        return (document, textView)
    }

    @Test func reloadingPullsTheLatestFileContents() async throws {
        let url = try temporaryFile("# One\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let (document, textView) = try await open(url)
        defer { document.close() }
        #expect(textView.string == "# One\n")
        #expect(NSDocumentController.shared.document(for: url) === document, "the window finds its document by the URL SwiftUI gives it")

        try "# Two\n\nEdited by another program.\n".write(to: url, atomically: true, encoding: .utf8)
        var reloaded: Bool?
        DocumentReloader.reload(document, completion: { reloaded = $0 })
        #expect(reloaded == true)
        try await waitUntil("the editor to show the new text") { textView.string == "# Two\n\nEdited by another program.\n" }
        #expect(!document.isDocumentEdited, "a reload leaves the document clean")
    }

    @Test func aCleanDocumentReloadsWithoutAsking() async throws {
        let url = try temporaryFile("clean\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let (document, _) = try await open(url)
        defer { document.close() }
        var asked = false
        DocumentReloader.reload(document, confirm: { _, answer in asked = true; answer(true) })
        #expect(!asked)
    }

    @Test func unsavedEditsAreOnlyDiscardedAfterConfirmation() async throws {
        let url = try temporaryFile("original\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let (document, textView) = try await open(url)
        defer { document.close() }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("my edit ", replacementRange: NSRange(location: NSNotFound, length: 0))
        document.updateChangeCount(.changeDone)   // typing marks it too; the hosted app does not run the event loop that does
        #expect(document.isDocumentEdited)
        try "from disk\n".write(to: url, atomically: true, encoding: .utf8)

        var kept: Bool?
        DocumentReloader.reload(document, confirm: { _, answer in answer(false) }, completion: { kept = $0 })
        #expect(kept == false)
        #expect(textView.string == "my edit original\n", "Cancel keeps the edits")
        #expect(document.isDocumentEdited)

        var reloaded: Bool?
        DocumentReloader.reload(document, confirm: { _, answer in answer(true) }, completion: { reloaded = $0 })
        #expect(reloaded == true)
        try await waitUntil("the file text") { textView.string == "from disk\n" }
        #expect(!document.isDocumentEdited)
    }

    @Test func comingBackToTheAppPicksUpAChangeMadeElsewhere() async throws {
        let url = try temporaryFile("before\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let (document, textView) = try await open(url)
        defer { document.close() }
        #expect(!DocumentReloader.isStale(document))

        // Another program saves the file a little later than the document read it.
        try await Task.sleep(for: .milliseconds(1100))
        try "after\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(DocumentReloader.isStale(document))
        var reloaded: Bool?
        DocumentReloader.reloadIfChangedOnDisk(document, completion: { reloaded = $0 })
        #expect(reloaded == true)
        try await waitUntil("the editor to show the new text") { textView.string == "after\n" }
        #expect(!DocumentReloader.isStale(document), "the document now knows the new modification date")
    }

    @Test func aDocumentWithUnsavedEditsIsNotReloadedBehindTheUsersBack() async throws {
        let url = try temporaryFile("mine\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let (document, textView) = try await open(url)
        defer { document.close() }
        document.updateChangeCount(.changeDone)
        try await Task.sleep(for: .milliseconds(1100))
        try "theirs\n".write(to: url, atomically: true, encoding: .utf8)
        var reloaded: Bool?
        DocumentReloader.reloadIfChangedOnDisk(document, completion: { reloaded = $0 })
        #expect(reloaded == false)
        #expect(textView.string == "mine\n")
    }

    @Test func aMissingFileReportsFailureInsteadOfCrashing() async throws {
        let url = try temporaryFile("soon gone\n")
        let (document, textView) = try await open(url)
        defer { document.close() }
        try FileManager.default.removeItem(at: url)
        #expect(!DocumentReloader.isStale(document), "no file, nothing newer")
        DocumentReloader.reloadIfChangedOnDisk(document)   // must not alert or crash
        #expect(textView.string == "soon gone\n")
    }

    @Test func anUntitledDocumentHasNothingToReload() throws {
        let document = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
        defer { document.close() }
        var result: Bool?
        DocumentReloader.reload(document, completion: { result = $0 })
        #expect(result == false)
    }
}
