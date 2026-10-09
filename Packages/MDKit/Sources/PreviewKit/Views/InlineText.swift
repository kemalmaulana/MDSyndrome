import AppKit
import MarkdownCore
import SwiftUI
import WebRenderKit

/// Inline content drawn as one `Text`: styled runs, typeset formulas (SwiftMath first, a KaTeX picture
/// when SwiftMath cannot), and find highlights. Every place that shows inlines uses it, so they all
/// search and fall back the same way.
struct InlineText: View {
    let inlines: [Inline]
    var fontSize: Double? = nil
    /// Which piece of the block this is, for find (table cells and `<details>` summaries have several).
    var slot = 0

    @Environment(\.previewTheme) private var theme
    @Environment(\.previewSearch) private var search
    @Environment(\.searchLine) private var searchLine
    @Environment(\.webRenderer) private var renderer
    @Environment(\.colorScheme) private var scheme
    @Environment(\.exportResources) private var export
    @State private var pictures = FormulaPictures()

    var body: some View {
        let failing = (renderer == nil && export == nil) ? [] : InlineRenderer.failingFormulas(inlines, fontSize: fontSize ?? theme.bodyFontSize, dark: scheme == .dark)
        InlineRenderer.text(inlines, theme: theme, fontSize: fontSize,
                            highlights: search?.highlights(for: SearchRunKey(line: searchLine, slot: slot)) ?? [],
                            pictures: export.map { exportedPictures(failing, $0) } ?? pictures.loaded, dark: scheme == .dark)
            .task(id: failing) {
                if export == nil, let renderer, !failing.isEmpty {
                    await pictures.load(failing, using: renderer, foreground: theme.text.hex(for: scheme), background: theme.background.hex(for: scheme))
                }
            }
    }

    /// The KaTeX pictures an export prepared for the formulas SwiftMath could not typeset.
    private func exportedPictures(_ keys: [FormulaKey], _ export: ExportResources) -> [FormulaKey: FormulaPicture] {
        var result: [FormulaKey: FormulaPicture] = [:]
        for key in keys {
            let request = PictureRequests.inlineFormula(key, foreground: theme.text.hex(for: scheme), background: theme.background.hex(for: scheme))
            if case .picture(let rendered)? = export.pictures[request], let image = NSImage(data: rendered.pdf) {
                result[key] = FormulaPicture(image: image, baseline: rendered.baseline ?? 0)
            }
        }
        return result
    }
}
