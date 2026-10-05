import Foundation

/// A hidden web view that turns requests into pictures. Two kinds exist (scripted and snapshot);
/// the renderer talks to them through this, which also lets tests stand in stubs.
@MainActor
protocol RenderHost: AnyObject {
    /// False once the host was invalidated or its web content process died.
    var isUsable: Bool { get }
    /// Called when the web content process dies.
    var onTerminate: (() -> Void)? { get set }
    func render(_ request: RenderRequest) async throws -> RenderedImage
    /// Tears the web view down. Safe to call twice.
    func invalidate()
}

@MainActor
private final class Gate {
    var done = false
}

/// Runs `operation`, giving up with `.timeout` after `duration` even if it never returns (a web view cannot
/// be told to stop a script, only thrown away). If the operation does finish after the deadline, `late`
/// gets its result, so a host that started too slowly can still be torn down instead of leaking.
@MainActor
func withDeadline<T>(_ duration: Duration, late: @escaping @MainActor (T) -> Void = { _ in },
                     _ operation: @escaping @MainActor () async throws -> T) async throws -> T {
    let gate = Gate()
    return try await withCheckedThrowingContinuation { continuation in
        let work = Task { @MainActor in
            do {
                let value = try await operation()
                if gate.done { late(value) } else { gate.done = true; continuation.resume(returning: value) }
            } catch {
                if !gate.done { gate.done = true; continuation.resume(throwing: error) }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: duration)
            if !gate.done {
                gate.done = true
                work.cancel()
                continuation.resume(throwing: RenderError.timeout)
            }
        }
    }
}
