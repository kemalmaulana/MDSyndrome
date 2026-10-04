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
    private static let cache = NSCache<NSString, CacheBox>()

    final class CacheBox {
        let result: Result<RenderedMath, MathRenderError>
        init(_ result: Result<RenderedMath, MathRenderError>) { self.result = result }
    }

    /// Renders in black; callers draw it as a template image so it takes the surrounding text colour.
    public static func render(_ latex: String, fontSize: CGFloat, display: Bool) -> Result<RenderedMath, MathRenderError> {
        let key = "\(display ? "D" : "T")\(fontSize)|\(latex)" as NSString
        if let hit = cache.object(forKey: key) { return hit.result }
        var image = MathImage(latex: latex, fontSize: fontSize, textColor: .black, labelMode: display ? .display : .text, textAlignment: .left)
        let (error, nsImage, layout) = image.asImage()
        let result: Result<RenderedMath, MathRenderError>
        if let nsImage, let layout, error == nil {
            nsImage.isTemplate = true
            result = .success(RenderedMath(image: nsImage, descent: layout.descent))
        } else {
            result = .failure(.syntax(error?.localizedDescription ?? "Could not typeset this formula"))
        }
        cache.setObject(CacheBox(result), forKey: key)
        return result
    }
}
