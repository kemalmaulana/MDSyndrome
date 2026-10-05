import AppKit
import Foundation
import Testing
@testable import WebRenderKit

/// A script that never returns must not outlive its host: WebKit cannot interrupt it, and a busy web content
/// process does not notice that its app has quit, so it would burn a CPU core until the next restart.
@MainActor
@Suite(.requiresWindowServer) struct ResourceTests {
    private struct Sample {
        let pid: Int
        let cpu: Double
    }

    /// Web content processes and their CPU use, read with `ps` off the main thread.
    private nonisolated func webContentProcesses() async -> [Sample] {
        await Task.detached {
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-axo", "pcpu,pid,command"]
            process.standardOutput = pipe
            try? process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line -> Sample? in
                guard line.contains("WebKit.WebContent") else { return nil }
                let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard fields.count >= 2, let cpu = Double(fields[0]), let pid = Int(fields[1]) else { return nil }
                return Sample(pid: pid, cpu: cpu)
            }
        }.value
    }

    @Test func aRunawayScriptIsKilledWithItsHost() async throws {
        _ = NSApplication.shared
        let before = Set(await webContentProcesses().map(\.pid))
        let host = try await ScriptHost.start()
        do {
            _ = try await withDeadline(.milliseconds(400)) { try await host.evaluate("while (true) {}") }
            Issue.record("an endless script cannot have returned")
        } catch RenderError.timeout {}
        let spinning = await webContentProcesses().filter { !before.contains($0.pid) && $0.cpu > 30 }
        host.invalidate()   // what WebRenderer does after a timeout
        try await Task.sleep(for: .seconds(2))
        let after = await webContentProcesses().filter { !before.contains($0.pid) }
        #expect(!spinning.isEmpty, "control: the runaway script really was burning a core")
        #expect(after.allSatisfy { $0.cpu < 30 }, "the runaway process is still running: \(after.map { "\($0.pid) \($0.cpu)%" })")
        #expect(!after.contains { spinning.map(\.pid).contains($0.pid) }, "the process that spun is gone")
    }

    @Test func rendererRecoversAfterARunawayHost() async throws {
        let renderer = WebRenderer(timeout: .milliseconds(500), startTimeout: .seconds(20))
        _ = try await renderer.render(RenderRequest(kind: .mermaid, source: "flowchart LR\n  A --> B"))
        #expect(renderer.hostsStarted == 1)
        // Make the live host busy for good, from outside the renderer, then ask for a picture.
        let busy = try #require(renderer.scriptHostForTesting)
        Task { _ = try? await busy.evaluate("while (true) {}") }
        try await Task.sleep(for: .milliseconds(200))
        await #expect(throws: RenderError.timeout) {
            try await renderer.render(RenderRequest(kind: .mermaid, source: "flowchart LR\n  C --> D"))
        }
        let image = try await renderer.render(RenderRequest(kind: .mermaid, source: "flowchart LR\n  C --> D"))
        #expect(PictureProbe.isPDF(image), "the next request gets a fresh host")
        #expect(renderer.hostsStarted == 2)
    }
}
