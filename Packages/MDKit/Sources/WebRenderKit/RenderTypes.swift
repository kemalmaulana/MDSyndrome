import CoreGraphics
import Foundation

/// What to draw. `katex` is for formulas SwiftMath could not typeset; `html` is a raw HTML block.
public enum RenderKind: Hashable, Sendable {
    case mermaid
    case graphviz
    case katex(display: Bool)
    case html
}

public enum RenderAppearance: Hashable, Sendable {
    case light
    case dark
}

/// One thing to render. Everything that changes the picture is part of the value, so a request is also
/// the cache key: editing elsewhere in a document never re-renders a diagram.
public struct RenderRequest: Hashable, Sendable {
    public var kind: RenderKind
    public var source: String
    public var appearance: RenderAppearance
    /// CSS colour of text and lines, e.g. `#1f2328`.
    public var foreground: String
    /// The preview's background. Pictures are transparent, so this is only painted if WebKit cannot make the
    /// page background transparent.
    public var background: String
    /// Body font size in points, so formulas match the text around them.
    public var fontSize: Double
    /// Width in points that HTML blocks are laid out at.
    public var width: Double
    /// Extra CSS for HTML blocks (the preview theme's typography).
    public var style: String

    public init(kind: RenderKind, source: String, appearance: RenderAppearance = .light, foreground: String = "#1f2328",
                background: String = "#ffffff", fontSize: Double = 15, width: Double = 700, style: String = "") {
        self.kind = kind
        self.source = source
        self.appearance = appearance
        self.foreground = foreground
        self.background = background
        self.fontSize = fontSize
        self.width = width
        self.style = style
    }
}

/// A rendered picture as vector PDF data, in points.
public struct RenderedImage: Sendable, Equatable {
    public let pdf: Data
    public let size: CGSize
    /// For inline formulas: how far the text baseline sits above the bottom edge.
    public let baseline: Double?

    public init(pdf: Data, size: CGSize, baseline: Double? = nil) {
        self.pdf = pdf
        self.size = size
        self.baseline = baseline
    }
}

public enum RenderError: Error, Equatable, Sendable {
    /// The source is invalid; the message comes from the library (mermaid, Graphviz, KaTeX).
    case syntax(String)
    /// The renderer did not answer in time and was restarted.
    case timeout
    /// WebKit or a bundled library could not start.
    case unavailable(String)
    /// The web content process died while rendering.
    case crashed
}

/// What the preview needs from a renderer. The preview module stays free of WebKit: only the
/// implementation (`WebRenderer`) touches it.
@MainActor
public protocol WebRendering: AnyObject {
    func render(_ request: RenderRequest) async throws -> RenderedImage
}
