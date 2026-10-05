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
    @State private var pictures = FormulaPictures()

    var body: some View {
        let failing = renderer == nil ? [] : InlineRenderer.failingFormulas(inlines, fontSize: fontSize ?? theme.bodyFontSize, dark: scheme == .dark)
        InlineRenderer.text(inlines, theme: theme, fontSize: fontSize,
                            highlights: search?.highlights(for: SearchRunKey(line: searchLine, slot: slot)) ?? [],
                            pictures: pictures.loaded, dark: scheme == .dark)
            .task(id: failing) {
                if let renderer, !failing.isEmpty {
                    await pictures.load(failing, using: renderer, foreground: theme.text.hex(for: scheme), background: theme.background.hex(for: scheme))
                }
            }
    }
}
