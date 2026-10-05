import AppKit
import Foundation
import Network
@testable import WebRenderKit

/// A TCP listener on the loopback interface that only counts connections. If a web view ever tries to reach
/// it, `connections` goes up: that is all the sandbox tests need to know.
final class LocalServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "mdsyndrome.test-server")
    private let lock = NSLock()
    private var count = 0

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            lock.withLock { count += 1 }
            connection.start(queue: queue)
            connection.cancel()
        }
    }

    var connections: Int { lock.withLock { count } }

    /// Starts listening and returns the port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            listener.stateUpdateHandler = { [listener] state in
                guard !once.done else { return }
                switch state {
                case .ready:
                    once.done = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    once.done = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    /// `http://127.0.0.1:<port>/<path>`
    static func url(port: UInt16, _ path: String = "") -> String { "http://127.0.0.1:\(port)/\(path)" }
}

/// What a rendered PDF looks like when drawn: used to tell "something was drawn" and "the corner is clear".
@MainActor
enum PictureProbe {
    static func bitmap(_ image: RenderedImage, scale: CGFloat = 1) -> NSBitmapImageRep? {
        guard let rep = NSPDFImageRep(data: image.pdf) else { return nil }
        let width = max(1, Int(rep.size.width * scale)), height = max(1, Int(rep.size.height * scale))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill(using: .copy)
        rep.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    /// RGBA of a pixel, 0…1.
    static func pixel(_ image: RenderedImage, x: Int = 1, y: Int = 1) -> (r: Double, g: Double, b: Double, a: Double)? {
        guard let color = bitmap(image)?.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return nil }
        return (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent), Double(color.alphaComponent))
    }

    /// The share of pixels that are not fully transparent.
    static func ink(_ image: RenderedImage) -> Double {
        guard let bitmap = bitmap(image) else { return 0 }
        var inked = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { inked += 1 }
        }
        return Double(inked) / Double(max(1, bitmap.pixelsWide * bitmap.pixelsHigh))
    }

    static func isPDF(_ image: RenderedImage) -> Bool {
        image.pdf.starts(with: Array("%PDF-".utf8))
    }
}
