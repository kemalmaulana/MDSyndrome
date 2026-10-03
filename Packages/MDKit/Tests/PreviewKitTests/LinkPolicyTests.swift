import Foundation
import Testing
@testable import PreviewKit

@Suite struct LinkPolicyTests {
    @Test(arguments: ["https://example.com", "http://example.com/a?b=1", "mailto:me@example.com", "HTTPS://EXAMPLE.COM"])
    func webAndMailOpen(_ link: String) throws {
        #expect(LinkPolicy.decision(for: try #require(URL(string: link))) == .openExternally)
    }

    @Test(arguments: ["file:///Applications/Calculator.app", "javascript:alert(1)", "x-apple-systempreferences:", "#fn-1", "other.md", "ssh://host"])
    func everythingElseIsIgnored(_ link: String) throws {
        #expect(LinkPolicy.decision(for: try #require(URL(string: link))) == .ignore)
    }
}
