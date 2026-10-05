import AppKit
import Observation
import SwiftUI
import WebRenderKit

/// A formula SwiftMath could not typeset, identified by everything that changes how KaTeX draws it.
struct FormulaKey: Hashable, Sendable {
    let latex: String
    let display: Bool
    let fontSize: Double
    let dark: Bool
}

struct FormulaPicture {
    let image: NSImage
    /// How far the picture hangs below the text baseline.
    let baseline: Double
}

/// The KaTeX pictures of the formulas in one piece of text, as they arrive. Until a picture is there (and if
/// KaTeX fails too) the text shows the formula's source in red.
@MainActor
@Observable
final class FormulaPictures {
    private(set) var loaded: [FormulaKey: FormulaPicture] = [:]
    @ObservationIgnored private var requested: Set<FormulaKey> = []

    func load(_ formulas: [FormulaKey], using renderer: any WebRendering, foreground: String, background: String) async {
        for key in formulas where requested.insert(key).inserted {
            let request = RenderRequest(kind: .katex(display: key.display), source: key.latex, appearance: key.dark ? .dark : .light,
                                        foreground: foreground, background: background, fontSize: key.fontSize)
            guard let rendered = try? await renderer.render(request), let image = NSImage(data: rendered.pdf) else { continue }
            loaded[key] = FormulaPicture(image: image, baseline: rendered.baseline ?? 0)
        }
    }
}
