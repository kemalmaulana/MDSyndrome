import AppKit
import SwiftMath

/// LaTeX → vector NSImage via SwiftMath, plus the descent needed to sit inline math on the text baseline.
public struct RenderedMath {
    public let image: NSImage
    /// Distance from the image's bottom edge up to the math baseline.
    public let descent: CGFloat
}

public enum MathRenderError: Error, Equatable {
    case syntax(String)
}

@MainActor
public enum MathRenderer {
    /// Typeset formulas, newest last. A plain bounded dictionary rather than an NSCache, which may drop an
    /// entry at any moment: this one is only ever touched on the main actor, so it is predictable.
    private static var cache: [String: Result<RenderedMath, MathRenderError>] = [:]
    private static var cacheOrder: [String] = []
    private static let cacheLimit = 512

    /// Renders in black; callers draw it as a template image so it takes the surrounding text colour.
    public static func render(_ latex: String, fontSize: CGFloat, display: Bool) -> Result<RenderedMath, MathRenderError> {
        let key = "\(display ? "D" : "T")\(fontSize)|\(latex)"
        if let hit = cache[key] { return hit }
        var image = MathImage(latex: latex, fontSize: fontSize, textColor: .black, labelMode: display ? .display : .text, textAlignment: .left)
        let (error, nsImage, layout) = image.asImage()
        let result: Result<RenderedMath, MathRenderError>
        if let nsImage, let layout, error == nil {
            nsImage.isTemplate = true
            result = .success(RenderedMath(image: nsImage, descent: layout.descent))
        } else {
            result = .failure(.syntax(error?.localizedDescription ?? "Could not typeset this formula"))
        }
        if cache.count >= cacheLimit {
            // Forget the oldest quarter at once, so this is not a per-call cost.
            for old in cacheOrder.prefix(cacheLimit / 4) { cache[old] = nil }
            cacheOrder.removeFirst(cacheLimit / 4)
        }
        cache[key] = result
        cacheOrder.append(key)
        return result
    }
}
