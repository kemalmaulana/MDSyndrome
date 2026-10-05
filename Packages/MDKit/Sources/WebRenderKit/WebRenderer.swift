import Foundation

/// Turns diagram, formula and HTML requests into vector pictures through hidden web views.
///
/// Nothing starts until the first request: a document that needs no web rendering never launches WebKit.
/// Requests are served one at a time, identical ones share one render, results are cached, a request that
/// takes too long replaces its web view, and a web view that dies is replaced and the request retried once.
@MainActor
public final class WebRenderer: WebRendering {
    enum HostKind: Hashable {
        case script
        case snapshot
    }

    typealias HostFactory = @MainActor (HostKind) async throws -> any RenderHost

    private let timeout: Duration
    private let startTimeout: Duration
    private let makeHost: HostFactory
    private var hosts: [HostKind: any RenderHost] = [:]
    private var servedByHost: [ObjectIdentifier: Int] = [:]
    private var cache: RenderCache
    private var inFlight: [RenderRequest: Task<RenderedImage, Error>] = [:]
    private var tail: Task<Void, Never>?
    private(set) var hostsStarted = 0

    /// True once any web view was created. Documents without diagrams, fallback math or complex HTML keep it false.
    public var hasStartedWebKit: Bool { hostsStarted > 0 }

    /// - Parameters:
    ///   - timeout: how long one render may take before its web view is thrown away. The first render in a
    ///     fresh web view gets `startTimeout` instead: it loads the libraries.
    public init(timeout: Duration = .seconds(8), startTimeout: Duration = .seconds(20), cacheLimit: Int = 64) {
        self.timeout = timeout
        self.startTimeout = startTimeout
        cache = RenderCache(countLimit: cacheLimit)
        makeHost = { kind in
            switch kind {
            case .script: try await ScriptHost.start()
            case .snapshot: try await SnapshotHost.start()
            }
        }
    }

    init(timeout: Duration, startTimeout: Duration, cacheLimit: Int = 64, makeHost: @escaping HostFactory) {
        self.timeout = timeout
        self.startTimeout = startTimeout
        cache = RenderCache(countLimit: cacheLimit)
        self.makeHost = makeHost
    }

    public func clearCache() {
        cache.removeAll()
    }

    public func render(_ request: RenderRequest) async throws -> RenderedImage {
        guard !request.source.allSatisfy(\.isWhitespace) else { throw RenderError.syntax("There is nothing to draw") }
        switch cache.entry(for: request) {
        case .image(let image)?: return image
        case .syntaxError(let message)?: throw RenderError.syntax(message)
        case nil: break
        }
        if let running = inFlight[request] { return try await running.value }

        let previous = tail
        let task = Task { @MainActor [self] () throws -> RenderedImage in
            _ = await previous?.value
            defer { inFlight[request] = nil }
            do {
                let image = try await perform(request, attempt: 0)
                cache.insert(.image(image), for: request)
                return image
            } catch RenderError.syntax(let message) {
                cache.insert(.syntaxError(message), for: request)
                throw RenderError.syntax(message)
            }
        }
        inFlight[request] = task
        tail = Task { _ = await task.result }
        return try await task.value
    }

    // MARK: - Hosts

    private func kind(for request: RenderRequest) -> HostKind {
        request.kind == .html ? .snapshot : .script
    }

    private func perform(_ request: RenderRequest, attempt: Int) async throws -> RenderedImage {
        let host = try await host(for: kind(for: request))
        let id = ObjectIdentifier(host)
        let limit = servedByHost[id, default: 0] == 0 ? startTimeout : timeout
        servedByHost[id, default: 0] += 1
        do {
            return try await withDeadline(limit) { try await host.render(request) }
        } catch RenderError.timeout {
            discard(host)
            throw RenderError.timeout
        } catch RenderError.crashed {
            discard(host)
            if attempt == 0 { return try await perform(request, attempt: 1) }
            throw RenderError.crashed
        }
    }

    private func host(for kind: HostKind) async throws -> any RenderHost {
        if let host = hosts[kind], host.isUsable { return host }
        hosts[kind] = nil
        let host = try await withDeadline(startTimeout, late: { (late: any RenderHost) in late.invalidate() }) { try await self.makeHost(kind) }
        host.onTerminate = { [weak self, weak host] in
            guard let self, let host else { return }
            discard(host)
        }
        hosts[kind] = host
        hostsStarted += 1
        return host
    }

    private func discard(_ host: any RenderHost) {
        host.invalidate()
        servedByHost[ObjectIdentifier(host)] = nil
        for (kind, candidate) in hosts where candidate === host { hosts[kind] = nil }
    }
}
