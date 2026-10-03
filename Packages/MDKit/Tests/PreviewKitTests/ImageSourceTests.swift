import Foundation
import Testing
@testable import PreviewKit

@Suite struct ImageSourceTests {
    private let base = URL(fileURLWithPath: "/Users/me/notes", isDirectory: true)

    @Test func relativePathResolvesAgainstDocumentFolder() {
        #expect(ImageSource.resolve("img/a.png", baseURL: base) == .local(URL(fileURLWithPath: "/Users/me/notes/img/a.png")))
        #expect(ImageSource.resolve("../a.png", baseURL: base) == .local(URL(fileURLWithPath: "/Users/me/a.png")))
    }

    @Test func percentEncodedSpacesAreDecoded() {
        #expect(ImageSource.resolve("my%20pic.png", baseURL: base) == .local(URL(fileURLWithPath: "/Users/me/notes/my pic.png")))
    }

    @Test func absoluteAndFileURLs() {
        #expect(ImageSource.resolve("/tmp/a.png", baseURL: nil) == .local(URL(fileURLWithPath: "/tmp/a.png")))
        #expect(ImageSource.resolve("file:///tmp/a.png", baseURL: nil) == .local(URL(string: "file:///tmp/a.png")!))
    }

    @Test func httpIsRemote() {
        #expect(ImageSource.resolve("https://img.shields.io/badge/x.svg", baseURL: base) == .remote(URL(string: "https://img.shields.io/badge/x.svg")!))
    }

    @Test func unsavedDocumentCannotResolveRelativePaths() {
        guard case .unresolved = ImageSource.resolve("a.png", baseURL: nil) else { Issue.record("expected unresolved"); return }
    }

    @Test(arguments: ["", "   ", "javascript:alert(1)", "data:image/png;base64,AAAA"])
    func unsupportedSourcesAreUnresolved(_ source: String) {
        guard case .unresolved = ImageSource.resolve(source, baseURL: base) else { Issue.record("expected unresolved for \(source)"); return }
    }

    @Test func loaderReadsLocalFileAndFailsForMissing() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mdsyndrome-\(UUID()).bin")
        try Data([1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try await ImageLoader.data(for: .local(url)) == Data([1, 2, 3]))
        await #expect(throws: (any Error).self) {
            try await ImageLoader.data(for: .local(url.appendingPathExtension("missing")))
        }
        await #expect(throws: ImageLoadError.unresolved("nope")) {
            try await ImageLoader.data(for: .unresolved(reason: "nope"))
        }
    }
}
