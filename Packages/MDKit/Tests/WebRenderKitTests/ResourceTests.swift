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
        let host = try await ScriptHost.start()
        let pid = try #require(host.processIdentifier, "WebKit did not say which process runs the page")
        do {
            _ = try await withDeadline(.milliseconds(400)) { try await host.evaluate("while (true) {}") }
            Issue.record("an endless script cannot have returned")
        } catch RenderError.timeout {}
        #expect(kill(pid, 0) == 0, "control: the process is alive and stuck in its loop")
        let spinning = await webContentProcesses().first { $0.pid == Int(pid) }
        #expect((spinning?.cpu ?? 0) > 30, "control: the runaway script really is burning a core")
        host.invalidate()   // what WebRenderer does after a timeout
        var gone = false
        for _ in 0..<40 where !gone {
            try await Task.sleep(for: .milliseconds(50))
            gone = kill(pid, 0) == -1 && errno == ESRCH
        }
        #expect(gone, "the runaway process \(pid) is still running")
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
