import Foundation
import Testing
@testable import WebRenderKit

// Everything here runs without WebKit: stub hosts stand in for the web views.

/// A stand-in host. `behaviour` decides what each render does.
@MainActor
final class StubHost: RenderHost {
    enum Behaviour {
        case succeed
        case hang
        case crash
        case syntax(String)
    }

    var isUsable = true
    var onTerminate: (() -> Void)?
    var behaviour: Behaviour
    private(set) var rendered: [RenderRequest] = []
    private(set) var invalidated = false
    private(set) var running = 0
    private(set) var maxRunning = 0
    /// Simulated work per request, so overlapping would show.
    var work: Duration = .milliseconds(5)

    init(_ behaviour: Behaviour = .succeed) {
        self.behaviour = behaviour
    }

    func render(_ request: RenderRequest) async throws -> RenderedImage {
        rendered.append(request)
        running += 1
        maxRunning = max(maxRunning, running)
        defer { running -= 1 }
        switch behaviour {
        case .succeed:
            try? await Task.sleep(for: work)
            return RenderedImage(pdf: Data("%PDF-\(request.source)".utf8), size: CGSize(width: 10, height: 10))
        case .hang:
            try? await Task.sleep(for: .seconds(60))
            return RenderedImage(pdf: Data(), size: .zero)
        case .crash:
            isUsable = false
            throw RenderError.crashed
        case .syntax(let message):
            throw RenderError.syntax(message)
        }
    }

    func invalidate() {
        invalidated = true
        isUsable = false
    }
}

@MainActor
final class StubFactory {
    var hosts: [StubHost] = []
    var script: [StubHost.Behaviour] = []
    var starts: [WebRenderer.HostKind] = []

    func make(_ kind: WebRenderer.HostKind) async throws -> any RenderHost {
        starts.append(kind)
        let host = StubHost(script.isEmpty ? .succeed : script.removeFirst())
        hosts.append(host)
        return host
    }

    func renderer(timeout: Duration = .seconds(5), startTimeout: Duration = .seconds(5), cacheLimit: Int = 64) -> WebRenderer {
        WebRenderer(timeout: timeout, startTimeout: startTimeout, cacheLimit: cacheLimit) { [self] kind in try await make(kind) }
    }
}

private func mermaid(_ source: String = "flowchart LR\n A --> B") -> RenderRequest {
    RenderRequest(kind: .mermaid, source: source)
}

@MainActor
@Suite struct WebRendererTests {
    @Test func rendererStaysIdleUntilAskedFor() async throws {
        let factory = StubFactory()
        let renderer = factory.renderer()
        #expect(!renderer.hasStartedWebKit)
        #expect(factory.starts.isEmpty, "creating the renderer must not create a web view (NF-1)")
        _ = try await renderer.render(mermaid())
        #expect(renderer.hasStartedWebKit)
        #expect(factory.starts == [.script])
    }

    @Test func anEmptySourceNeverStartsAHost() async {
        let factory = StubFactory()
        let renderer = factory.renderer()
        await #expect(throws: RenderError.syntax("There is nothing to draw")) { try await renderer.render(mermaid("  \n\t")) }
        #expect(factory.starts.isEmpty)
    }

    @Test func scriptAndHTMLRequestsUseSeparateHosts() async throws {
        let factory = StubFactory()
        let renderer = factory.renderer()
        _ = try await renderer.render(mermaid())
        _ = try await renderer.render(RenderRequest(kind: .graphviz, source: "digraph { a -> b }"))
        _ = try await renderer.render(RenderRequest(kind: .katex(display: false), source: "x^2"))
        #expect(factory.starts == [.script], "mermaid, graphviz and katex share the scripted host")
        _ = try await renderer.render(RenderRequest(kind: .html, source: "<p>hi</p>"))
        #expect(factory.starts == [.script, .snapshot])
    }

    @Test func identicalRequestsShareOneRender() async throws {
        let factory = StubFactory()
        let renderer = factory.renderer()
        async let first = renderer.render(mermaid())
        async let second = renderer.render(mermaid())
        async let third = renderer.render(mermaid())
        let results = try await [first, second, third]
        #expect(Set(results.map(\.pdf)).count == 1)
        #expect(factory.hosts.first?.rendered.count == 1)
    }

    @Test func requestsAreServedOneAtATime() async throws {
        let factory = StubFactory()
        let renderer = factory.renderer()
        let requests = (0..<8).map { mermaid("flowchart LR\n A\($0) --> B") }
        let tasks = requests.map { request in Task { @MainActor in try await renderer.render(request) } }
        for task in tasks { _ = try await task.value }
        let host = try #require(factory.hosts.first)
        #expect(host.rendered.count == 8)
        #expect(host.maxRunning == 1)
    }

    @Test func requestsAreServedInTheOrderTheyArrive() async throws {
        let factory = StubFactory()
        let renderer = factory.renderer()
        let requests = (0..<5).map { mermaid("flowchart LR\n N\($0) --> M") }
        let tasks = requests.map { request in Task { @MainActor in try await renderer.render(request) } }
        for task in tasks { _ = try await task.value }
        #expect(factory.hosts.first?.rendered.map(\.source) == requests.map(\.source))
    }

    @Test func repeatsComeFromTheCacheUntilItIsCleared() async throws {
        let factory = StubFactory()
        let renderer = factory.renderer()
        let first = try await renderer.render(mermaid())
        let second = try await renderer.render(mermaid())
        #expect(first == second)
        #expect(factory.hosts.first?.rendered.count == 1, "editing elsewhere must not redraw a diagram")
        renderer.clearCache()
        _ = try await renderer.render(mermaid())
        #expect(factory.hosts.first?.rendered.count == 2)
    }

    @Test func anythingThatChangesThePictureIsADifferentRequest() async throws {
        let factory = StubFactory()
        let renderer = factory.renderer()
        let base = mermaid()
        var dark = base
        dark.appearance = .dark
        var otherColour = base
        otherColour.foreground = "#ffffff"
        var otherSize = base
        otherSize.fontSize = 22
        for request in [base, dark, otherColour, otherSize] { _ = try await renderer.render(request) }
        #expect(factory.hosts.first?.rendered.count == 4)
    }

    @Test func syntaxErrorsAreCachedAndRethrown() async throws {
        let factory = StubFactory()
        factory.script = [.syntax("Parse error on line 2")]
        let renderer = factory.renderer()
        for _ in 0..<3 {
            await #expect(throws: RenderError.syntax("Parse error on line 2")) { try await renderer.render(mermaid("broken")) }
        }
        #expect(factory.hosts.first?.rendered.count == 1, "a broken diagram is not sent to the web view on every SwiftUI update")
    }

    @Test func aHangingHostTimesOutAndIsReplaced() async throws {
        let factory = StubFactory()
        factory.script = [.hang, .succeed]
        let renderer = factory.renderer(timeout: .milliseconds(150), startTimeout: .milliseconds(150))
        await #expect(throws: RenderError.timeout) { try await renderer.render(mermaid("never ends")) }
        #expect(factory.hosts[0].invalidated, "the stuck web view is thrown away")
        let image = try await renderer.render(mermaid("works"))
        #expect(!image.pdf.isEmpty)
        #expect(factory.hosts.count == 2)
    }

    @Test func aTimeoutIsNotCached() async throws {
        let factory = StubFactory()
        factory.script = [.hang, .succeed]
        let renderer = factory.renderer(timeout: .milliseconds(100), startTimeout: .milliseconds(100))
        await #expect(throws: RenderError.timeout) { try await renderer.render(mermaid("slow")) }
        _ = try await renderer.render(mermaid("slow"))
        #expect(factory.hosts[1].rendered.count == 1, "the same source is tried again with a fresh web view")
    }

    @Test func aCrashedHostIsReplacedAndTheRequestRetriedOnce() async throws {
        let factory = StubFactory()
        factory.script = [.crash, .succeed]
        let renderer = factory.renderer()
        let image = try await renderer.render(mermaid())
        #expect(!image.pdf.isEmpty)
        #expect(factory.hosts.count == 2)
        #expect(factory.hosts[0].invalidated)
    }

    @Test func aSecondCrashIsReported() async {
        let factory = StubFactory()
        factory.script = [.crash, .crash]
        let renderer = factory.renderer()
        await #expect(throws: RenderError.crashed) { try await renderer.render(mermaid()) }
        #expect(factory.hosts.count == 2, "one retry, not a loop")
    }

    @Test func aHostThatDiesBetweenRequestsIsReplacedOnTheNext() async throws {
        let factory = StubFactory()
        let renderer = factory.renderer()
        _ = try await renderer.render(mermaid("one"))
        let first = try #require(factory.hosts.first)
        first.onTerminate?()   // the web content process was killed
        #expect(first.invalidated)
        _ = try await renderer.render(mermaid("two"))
        #expect(factory.hosts.count == 2)
    }

    @Test func aHostThatStartsTooLateIsTornDownNotLeaked() async {
        let factory = StubFactory()
        let renderer = WebRenderer(timeout: .seconds(1), startTimeout: .milliseconds(100)) { kind in
            try? await Task.sleep(for: .milliseconds(400))
            return try await factory.make(kind)
        }
        await #expect(throws: RenderError.timeout) { try await renderer.render(mermaid()) }
        try? await Task.sleep(for: .milliseconds(600))
        #expect(factory.hosts.first?.invalidated == true)
    }

    @Test func theFirstRequestInAFreshHostGetsTheLongerDeadline() async throws {
        // Loading the libraries makes a first render slow; with the short per-request limit it would time out.
        let slow = StubHost(.succeed)
        slow.work = .milliseconds(120)
        let renderer = WebRenderer(timeout: .milliseconds(10), startTimeout: .seconds(2)) { _ in slow }
        _ = try await renderer.render(mermaid("first"))
        await #expect(throws: RenderError.timeout) { try await renderer.render(mermaid("second")) }
    }

    @Test func theCacheIsBoundedByCount() async throws {
        let factory = StubFactory()
        let renderer = factory.renderer(cacheLimit: 3)
        for index in 0..<5 { _ = try await renderer.render(mermaid("flowchart LR\n X\(index) --> Y")) }
        let host = try #require(factory.hosts.first)
        #expect(host.rendered.count == 5)
        _ = try await renderer.render(mermaid("flowchart LR\n X4 --> Y"))   // newest: still cached
        #expect(host.rendered.count == 5)
        _ = try await renderer.render(mermaid("flowchart LR\n X0 --> Y"))   // oldest: evicted
        #expect(host.rendered.count == 6)
    }
}

@Suite struct RenderCacheTests {
    private func image(_ bytes: Int) -> RenderedImage {
        RenderedImage(pdf: Data(count: bytes), size: CGSize(width: 1, height: 1))
    }

    private func request(_ source: String) -> RenderRequest {
        RenderRequest(kind: .mermaid, source: source)
    }

    @Test func evictsTheLeastRecentlyUsed() {
        var cache = RenderCache(countLimit: 2, byteLimit: .max)
        cache.insert(.image(image(1)), for: request("a"))
        cache.insert(.image(image(1)), for: request("b"))
        _ = cache.entry(for: request("a"))   // a is now newer than b
        cache.insert(.image(image(1)), for: request("c"))
        #expect(cache.entry(for: request("b")) == nil)
        #expect(cache.entry(for: request("a")) != nil)
        #expect(cache.entry(for: request("c")) != nil)
    }

    @Test func evictsByBytesToo() {
        var cache = RenderCache(countLimit: 100, byteLimit: 100)
        cache.insert(.image(image(60)), for: request("a"))
        cache.insert(.image(image(60)), for: request("b"))
        #expect(cache.count == 1, "120 bytes do not fit in 100")
        #expect(cache.entry(for: request("b")) != nil)
    }

    @Test func aSingleHugeEntryIsStillKept() {
        var cache = RenderCache(countLimit: 10, byteLimit: 10)
        cache.insert(.image(image(1_000)), for: request("big"))
        #expect(cache.entry(for: request("big")) != nil, "the entry just stored is never the one thrown out")
    }

    @Test func replacingAnEntryAdjustsTheByteCount() {
        var cache = RenderCache(countLimit: 10, byteLimit: 100)
        cache.insert(.image(image(80)), for: request("a"))
        cache.insert(.image(image(10)), for: request("a"))
        cache.insert(.image(image(80)), for: request("b"))
        #expect(cache.count == 2)
    }

    @Test func keepsSyntaxErrors() {
        var cache = RenderCache()
        cache.insert(.syntaxError("nope"), for: request("x"))
        if case .syntaxError(let message)? = cache.entry(for: request("x")) { #expect(message == "nope") } else { Issue.record("missing") }
    }

    @Test func removeAllEmptiesIt() {
        var cache = RenderCache()
        cache.insert(.image(image(5)), for: request("a"))
        cache.removeAll()
        #expect(cache.count == 0)
        #expect(cache.entry(for: request("a")) == nil)
    }
}

extension RenderCache.Entry: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.image(let a), .image(let b)): a == b
        case (.syntaxError(let a), .syntaxError(let b)): a == b
        default: false
        }
    }
}
