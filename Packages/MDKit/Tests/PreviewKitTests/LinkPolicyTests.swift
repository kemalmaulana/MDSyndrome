import Foundation
import MarkdownCore
import SwiftUI
import Testing
@testable import PreviewKit

private let base = URL(fileURLWithPath: "/Users/me/notes", isDirectory: true)

/// Files that "exist" for these tests.
private let existing: Set<String> = [
    "/Users/me/notes/other.md", "/Users/me/notes/Other.MD", "/Users/me/notes/docs/guide.markdown", "/Users/me/notes/My File.md",
    "/Users/me/up.md", "/Users/me/notes/notes.txt", "/Users/me/notes/folder", "/Applications/Calculator.app", "/Users/me/notes/run.sh",
    "/Users/me/notes/a.mdown", "/Users/me/notes/b.mkd", "/Users/me/notes/c.mkdn",
]

private func action(_ link: String, base: URL? = base) throws -> LinkAction {
    LinkPolicy.action(for: try #require(URL(string: link)), baseURL: base, fileExists: { existing.contains($0.path) })
}

private func file(_ path: String) -> URL { URL(fileURLWithPath: path) }

@Suite struct LinkPolicyTests {
    @Test(arguments: ["https://example.com", "http://example.com/a?b=1", "mailto:me@example.com", "HTTPS://EXAMPLE.COM"])
    func webAndMailOpen(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(LinkPolicy.action(for: url, baseURL: nil) == .open(url))
        #expect(LinkPolicy.action(for: url, baseURL: base) == .open(url))
    }

    @Test(arguments: ["javascript:alert(1)", "JavaScript:void(0)", "data:text/html,hi", "vbscript:x"])
    func scriptsAndDataAreIgnored(_ link: String) throws {
        #expect(try action(link) == .ignore)
    }

    @Test(arguments: ["tel:+123", "x-apple.systempreferences:com.apple.preference.security", "ssh://host", "custom-scheme://x/y", "facetime:me@example.com", "ftp://host/file"])
    func otherSchemesAskFirst(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(LinkPolicy.action(for: url, baseURL: base) == .confirm(url))
    }

    @Test func aFragmentOnlyLinkScrollsThisDocument() throws {
        #expect(try action("#section") == .scroll(fragment: "section"))
        #expect(try action("#fn-1") == .scroll(fragment: "fn-1"))
        #expect(try action("#caf%C3%A9") == .scroll(fragment: "caf%C3%A9"), "the fragment is passed on as written; the anchors decode it")
        #expect(try action("#section", base: nil) == .scroll(fragment: "section"), "an unsaved document still has its own headings")
    }

    @Test func anEmptyFragmentIsIgnored() throws {
        #expect(try action("#") == .ignore)
    }

    @Test func aRelativeMarkdownFileOpensInTheApp() throws {
        #expect(try action("other.md") == .openDocument(file("/Users/me/notes/other.md"), fragment: nil))
        #expect(try action("./other.md") == .openDocument(file("/Users/me/notes/other.md"), fragment: nil))
        #expect(try action("docs/guide.markdown#install") == .openDocument(file("/Users/me/notes/docs/guide.markdown"), fragment: "install"))
        #expect(try action("../up.md") == .openDocument(file("/Users/me/up.md"), fragment: nil))
        #expect(try action("My%20File.md") == .openDocument(file("/Users/me/notes/My File.md"), fragment: nil))
        #expect(try action("other.md?version=2") == .openDocument(file("/Users/me/notes/other.md"), fragment: nil), "a query is not part of the file name")
    }

    @Test(arguments: ["a.mdown", "b.mkd", "c.mkdn", "Other.MD"])
    func everyMarkdownExtensionCountsInAnyCase(_ name: String) throws {
        let result = try action(name)
        if case .openDocument(let url, _) = result { #expect(url.lastPathComponent == name) } else { Issue.record("\(name) → \(result)") }
    }

    @Test func aMissingFileIsReportedNotOpened() throws {
        #expect(try action("nope.md") == .missing(file("/Users/me/notes/nope.md")))
        #expect(try action("../../../../../../etc/passwd.md") == .missing(file("/etc/passwd.md")))
    }

    @Test func aFileThatIsNotMarkdownAsksFirst() throws {
        #expect(try action("notes.txt") == .confirm(file("/Users/me/notes/notes.txt")))
        #expect(try action("folder") == .confirm(file("/Users/me/notes/folder")))
        #expect(try action("run.sh") == .confirm(file("/Users/me/notes/run.sh")))
    }

    @Test func aRelativePathInAnUnsavedDocumentIsIgnored() throws {
        #expect(try action("other.md", base: nil) == .ignore)
        #expect(try action("docs/guide.markdown#x", base: nil) == .ignore)
    }

    @Test func aFileURLIsTreatedLikeAPath() throws {
        #expect(try action("file:///Users/me/notes/other.md#top") == .openDocument(file("/Users/me/notes/other.md"), fragment: "top"))
        #expect(try action("file:///Applications/Calculator.app") == .confirm(file("/Applications/Calculator.app")), "a program asks, it never opens")
        #expect(try action("file:///Users/me/notes/missing.md") == .missing(file("/Users/me/notes/missing.md")))
    }

    @Test func aFileURLOnAnotherHostIsIgnored() throws {
        #expect(try action("file://server/share/x.md") == .ignore)
        #expect(try action("file://localhost/Users/me/notes/other.md") == .openDocument(file("/Users/me/notes/other.md"), fragment: nil))
    }

    @Test func aHugeOrOddLinkNeverCrashes() throws {
        let long = "a" + String(repeating: "/..", count: 5_000) + "/b.md"
        let odd = ["%", "%%%", " ", "..", ".", "/", "//", "\\", "?", "?x", "a b", "👍.md", "x:\u{0}"]
        for link in odd + [long, "https://" + String(repeating: "a", count: 100_000)] {
            guard let url = URL(string: link) else { continue }
            _ = LinkPolicy.action(for: url, baseURL: base, fileExists: { _ in false })
            _ = LinkPolicy.action(for: url, baseURL: nil, fileExists: { _ in true })
        }
    }
}

@MainActor
@Suite struct PreviewLinkRouterTests {
    private let document = MarkdownParser.parse("# Intro\n\ntext\n\n## Details\n\nmore\n")

    private func router(base: URL? = base, handler: ((LinkAction) -> Void)? = nil) -> (PreviewLinkRouter, PreviewScroller, Recorder) {
        let scroller = PreviewScroller()
        let recorder = Recorder()
        scroller.jump = { id, anchor in recorder.jumps.append((id, anchor)) }
        scroller.onNavigate = { recorder.navigated.append($0) }
        return (PreviewLinkRouter(baseURL: base, anchors: DocumentAnchors(blocks: document.blocks), scroller: scroller, handler: handler), scroller, recorder)
    }

    final class Recorder {
        var jumps: [(BlockID, UnitPoint)] = []
        var navigated: [BlockID] = []
    }

    @Test func webLinksGoToTheSystem() throws {
        #expect(router().0.route(try #require(URL(string: "https://example.com"))) == .system)
        #expect(router().0.route(try #require(URL(string: "mailto:me@example.com"))) == .system)
    }

    @Test func anAnchorScrollsThePreviewAndTellsTheWindow() throws {
        let (router, _, recorder) = router()
        #expect(router.route(try #require(URL(string: "#details"))) == .handled)
        #expect(recorder.jumps.count == 1)
        #expect(recorder.jumps.first?.0 == document.blocks[2].id)
        #expect(recorder.jumps.first?.1 == .top)
        #expect(recorder.navigated == [document.blocks[2].id])
    }

    @Test func anAnchorThatMatchesNothingDoesNothing() throws {
        let (router, _, recorder) = router()
        #expect(router.route(try #require(URL(string: "#nowhere"))) == .handled)
        #expect(recorder.jumps.isEmpty)
        #expect(recorder.navigated.isEmpty)
    }

    @Test func linksThatLeaveThePreviewGoToTheHandler() throws {
        var received: [LinkAction] = []
        let (router, _, _) = router(handler: { received.append($0) })
        #expect(router.route(try #require(URL(string: "tel:123"))) == .handled)
        #expect(router.route(try #require(URL(string: "other.md#x"))) == .handled)
        #expect(received.count == 2)
        #expect(received.first == .confirm(URL(string: "tel:123")!))
    }

    @Test func scriptsAreDiscardedWithoutReachingTheHandler() throws {
        var received: [LinkAction] = []
        let (router, _, recorder) = router(handler: { received.append($0) })
        #expect(router.route(try #require(URL(string: "javascript:alert(1)"))) == .discarded)
        #expect(received.isEmpty && recorder.jumps.isEmpty)
    }

    @Test func withoutAHandlerOtherLinksAreHandledAndIgnored() throws {
        let (router, _, _) = router(handler: nil)
        #expect(router.route(try #require(URL(string: "tel:123"))) == .handled)
    }
}
