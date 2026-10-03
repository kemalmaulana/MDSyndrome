import Foundation
import MarkdownCore
import SwiftUI
import Testing
@testable import PreviewKit

@Suite struct InlineRendererTests {
    private func render(_ inlines: [Inline]) -> AttributedString {
        InlineRenderer.attributedString(inlines, theme: .github)
    }

    @Test func plainTextHasNoIntent() {
        let result = render([.text("hi")])
        #expect(String(result.characters) == "hi")
        #expect(result.runs.first?.inlinePresentationIntent == nil)
    }

    @Test func nestedEmphasisCombinesIntents() {
        let result = render([.strong([.text("a"), .emphasis([.text("b")])])])
        let intents = result.runs.map(\.inlinePresentationIntent)
        #expect(intents == [.stronglyEmphasized, [.stronglyEmphasized, .emphasized]])
    }

    @Test func codeGetsCodeIntentAndBackground() throws {
        let run = try #require(render([.code("x")]).runs.first)
        #expect(run.inlinePresentationIntent == .code)
        #expect(run.backgroundColor != nil)
    }

    @Test func linkCarriesURLAndColor() throws {
        let run = try #require(render([.link(destination: "https://a.com", title: nil, content: [.text("go")])]).runs.first)
        #expect(run.link == URL(string: "https://a.com"))
        #expect(run.foregroundColor != nil)
    }

    @Test func invalidLinkDestinationStillRendersText() {
        let result = render([.link(destination: "http://exa mple.com/%%", title: nil, content: [.text("t")])])
        #expect(String(result.characters) == "t")
    }

    @Test func breaksBecomeSpaceAndNewline() {
        #expect(String(render([.text("a"), .softBreak, .text("b"), .lineBreak, .text("c")]).characters) == "a b\nc")
    }

    @Test func footnoteReferenceIsRaisedLink() throws {
        let run = try #require(render([.footnoteReference(index: 2)]).runs.first)
        #expect(String(render([.footnoteReference(index: 2)]).characters) == "2")
        #expect(run.link == URL(string: "#fn-2"))
        #expect((run.baselineOffset ?? 0) > 0)
    }

    @Test func imageInsideTextShowsAlt() {
        #expect(String(render([.image(source: "a.png", title: nil, alt: "logo")]).characters) == "[logo]")
        #expect(String(render([.image(source: "a.png", title: nil, alt: "")]).characters) == "[image]")
    }
}
