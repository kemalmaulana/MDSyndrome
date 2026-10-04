import Foundation
import MarkdownCore
import Testing
@testable import MDSyndrome

@MainActor
@Suite struct DocumentSessionTests {
    @Test func renderNowPublishesImmediately() async {
        let session = DocumentSession()
        await session.renderNow("# Title")
        #expect(session.rendered.outline.map(\.title) == ["Title"])
        #expect(session.renderCount == 1)
    }

    @Test func rapidEditsAreCoalescedIntoOneRender() async throws {
        let session = DocumentSession(debounce: .milliseconds(50))
        session.textDidChange("a")
        session.textDidChange("ab")
        session.textDidChange("abc")
        try await Task.sleep(for: .milliseconds(400))
        #expect(session.renderCount == 1)
        #expect(session.rendered.stats.characters == 3)
    }

    @Test func renderNowCancelsPendingDebouncedRender() async throws {
        let session = DocumentSession(debounce: .milliseconds(100))
        session.textDidChange("stale")
        await session.renderNow("fresh")
        try await Task.sleep(for: .milliseconds(300))
        #expect(session.renderCount == 1)
        #expect(session.rendered.stats.characters == 5)
        #expect(session.rendered.document.blocks.first?.kind == .paragraph([.text("fresh")]))
    }

    @Test func slowStaleRenderNeverOverwritesNewerText() async throws {
        let session = DocumentSession(debounce: .milliseconds(20)) { text, options in
            if text == "slow" { Thread.sleep(forTimeInterval: 0.3) }
            return MarkdownPipeline.render(text, options: options)
        }
        session.textDidChange("slow")
        try await Task.sleep(for: .milliseconds(100))   // the slow render is now in flight
        session.textDidChange("fast")
        try await Task.sleep(for: .milliseconds(700))
        #expect(session.rendered.document.blocks.first?.kind == .paragraph([.text("fast")]))
        #expect(session.renderCount == 1)
    }

    @Test func slowInitialRenderNeverOverwritesALaterEdit() async throws {
        let session = DocumentSession(debounce: .milliseconds(20)) { text, options in
            if text == "initial" { Thread.sleep(forTimeInterval: 0.3) }
            return MarkdownPipeline.render(text, options: options)
        }
        async let initial: Void = session.renderNow("initial")
        try await Task.sleep(for: .milliseconds(50))   // the slow first render is in flight
        session.textDidChange("typed")
        try await Task.sleep(for: .milliseconds(200))
        await initial
        #expect(session.rendered.document.blocks.first?.kind == .paragraph([.text("typed")]))
        #expect(session.renderCount == 1)
    }

    @Test func optionsArePassedToRenderer() async {
        var options = MarkdownOptions()
        options.math = false
        let session = DocumentSession(options: options)
        await session.renderNow("$x$")
        #expect(session.rendered.document.blocks.first?.kind == .paragraph([.text("$x$")]))
    }
}
