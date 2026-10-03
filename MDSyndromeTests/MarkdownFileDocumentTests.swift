import Foundation
import Testing
@testable import MDSyndrome

@Suite struct MarkdownFileDocumentTests {
    @Test func decodesUTF8() throws {
        #expect(try MarkdownFileDocument.decode(Data("# Héllo".utf8)) == "# Héllo")
    }

    @Test func stripsUTF8ByteOrderMark() throws {
        #expect(try MarkdownFileDocument.decode(Data([0xEF, 0xBB, 0xBF]) + Data("hi".utf8)) == "hi")
    }

    @Test func fallsBackToLegacyEncoding() throws {
        let latin1 = try #require("café".data(using: .isoLatin1))
        #expect(try MarkdownFileDocument.decode(latin1) == "café")
    }

    @Test func keepsWindowsLineEndings() throws {
        #expect(try MarkdownFileDocument.decode(Data("a\r\nb".utf8)) == "a\r\nb")
    }

    @Test func emptyFileIsEmptyDocument() throws {
        #expect(try MarkdownFileDocument.decode(Data()) == "")
    }
}
