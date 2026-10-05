import CryptoKit
import Foundation
import Testing
@testable import WebRenderKit

/// The vendored JavaScript is byte for byte what npm shipped: `VENDORED.md` records every file's SHA-256 and
/// this recomputes them. It needs no WebKit, so it runs on CI too.
@Suite struct VendoredFilesTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let resources = packageRoot.appendingPathComponent("Sources/WebRenderKit/Resources")

    /// (relative path, sha256) from the table in VENDORED.md.
    private func recorded() throws -> [(path: String, hash: String)] {
        let text = try String(contentsOf: Self.packageRoot.appendingPathComponent("VENDORED.md"), encoding: .utf8)
        return text.split(separator: "\n").compactMap { line -> (String, String)? in
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
            guard cells.count == 2, cells[0].hasPrefix("Sources/WebRenderKit/Resources/"), cells[1].count == 64 else { return nil }
            return (String(cells[0].dropFirst("Sources/WebRenderKit/Resources/".count)), cells[1])
        }
    }

    private func sha256(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    @Test func everyRecordedFileMatchesItsChecksum() throws {
        let entries = try recorded()
        #expect(entries.count >= 24)
        for entry in entries {
            let url = Self.resources.appendingPathComponent(entry.path)
            #expect(try sha256(of: url) == entry.hash, "\(entry.path) differs from what VENDORED.md records")
        }
    }

    @Test func noVendoredFileIsMissingFromTheRecord() throws {
        let known = Set(try recorded().map(\.path)).union(["bridge.js", "shell.html"])
        let files = try FileManager.default.subpathsOfDirectory(atPath: Self.resources.path)
            .filter { !$0.hasSuffix("/") && !(URL(fileURLWithPath: Self.resources.appendingPathComponent($0).path).hasDirectoryPath) }
        for file in files {
            #expect(known.contains(file), "\(file) is in Resources but not in VENDORED.md")
        }
    }

    @Test func theOnlyScriptsAreTheThreeLibrariesAndOurBridge() throws {
        // NF-1: `find MDSyndrome.app -name '*.js'` lists only these.
        let scripts = try FileManager.default.subpathsOfDirectory(atPath: Self.resources.path).filter { $0.hasSuffix(".js") }
        #expect(Set(scripts) == ["mermaid.min.js", "viz-global.js", "katex/katex.min.js", "bridge.js"])
    }

    @Test func theBundledCopiesAreTheSourceFiles() throws {
        let bundled = try #require(ScriptHost.resourcesDirectory)
        for entry in try recorded() {
            #expect(try sha256(of: bundled.appendingPathComponent(entry.path)) == entry.hash, "\(entry.path) in the built bundle")
        }
        for name in ["bridge.js", "shell.html"] {
            #expect(try Data(contentsOf: bundled.appendingPathComponent(name)) == Data(contentsOf: Self.resources.appendingPathComponent(name)))
        }
    }

    @Test func theShellKeepsItsLockdown() throws {
        let shell = try String(contentsOf: Self.resources.appendingPathComponent("shell.html"), encoding: .utf8)
        #expect(shell.contains("default-src 'none'"))
        #expect(shell.contains("script-src file: 'wasm-unsafe-eval'"))
        #expect(!shell.contains("unsafe-inline'; font") || shell.contains("style-src file: 'unsafe-inline'"), "inline styles only, never inline scripts")
        #expect(!shell.contains("script-src 'unsafe-inline'"))
        #expect(!shell.contains("unsafe-eval'") || shell.contains("'wasm-unsafe-eval'"))
        #expect(!shell.contains("http:") && !shell.contains("https:"), "the page refers to nothing on the network")
    }

    @Test func theBridgeConfiguresTheLibrariesSafely() throws {
        let bridge = try String(contentsOf: Self.resources.appendingPathComponent("bridge.js"), encoding: .utf8)
        #expect(bridge.contains("securityLevel: 'strict'"))
        #expect(bridge.contains("trust: false"))
        #expect(!bridge.contains("eval("))
        #expect(!bridge.contains("new Function"))
    }
}
