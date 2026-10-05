import Foundation
import Testing
@testable import PreviewKit

@Suite struct LinkPolicyTests {
    @Test(arguments: ["https://example.com", "http://example.com/a?b=1", "mailto:me@example.com", "HTTPS://EXAMPLE.COM"])
    func webAndMailOpen(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(LinkPolicy.action(for: url, baseURL: nil) == .open(url))
    }

    @Test(arguments: ["javascript:alert(1)", "data:text/html,hi"])
    func scriptsAreIgnored(_ link: String) throws {
        #expect(LinkPolicy.action(for: try #require(URL(string: link)), baseURL: nil) == .ignore)
    }
}
