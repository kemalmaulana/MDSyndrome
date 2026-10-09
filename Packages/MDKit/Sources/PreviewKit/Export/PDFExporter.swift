import AppKit
import MarkdownCore
import SwiftUI

/// Paginated PDF of a document (PRD EX-3). Each top-level block is drawn by SwiftUI's `ImageRenderer` straight into
/// a PDF context, so text stays vector. Blocks are packed onto pages; one taller than a page is sliced across pages.
/// Always the light appearance, on white paper.
@MainActor
public enum PDFExporter {
    public static func export(_ document: MarkdownDocument, theme: PreviewTheme, baseURL: URL?, paperSize: CGSize, margins: NSEdgeInsets,
                              resources: ExportResources = ExportResources()) -> Data? {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: paperSize)
        guard let consumer = CGDataConsumer(data: data), let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        let contentWidth = paperSize.width - margins.left - margins.right
        let pageHeight = paperSize.height - margins.top - margins.bottom
        guard contentWidth > 50, pageHeight > 50 else { return nil }
        let spacing = theme.blockSpacing
        // Page 1 is opened lazily, so an empty document still gets one blank page.
        var used = pageHeight + 1
        var open = false

        func newPage() {
            if open { pdf.endPDFPage() }
            pdf.beginPDFPage(nil)
            open = true
            used = 0
        }

        for block in document.blocks {
            let view = BlockView(block: block)
                .environment(\.previewTheme, theme)
                .environment(\.documentBaseURL, baseURL)
                .environment(\.exportResources, resources)
                .environment(\.colorScheme, .light)
                .foregroundStyle(theme.text.color)
                .frame(width: contentWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)
            renderer.render { size, draw in
                guard size.height > 0 else { return }
                let gap = used == 0 ? 0 : spacing
                if size.height <= pageHeight {
                    if used + gap + size.height > pageHeight { newPage() }
                    let top = used + (used == 0 ? 0 : gap)
                    place(draw, size: size, topOffset: top, sliceFrom: 0, sliceHeight: size.height)
                    used = top + size.height
                } else {
                    // Taller than a page: start on a fresh page and cut it into page-high slices.
                    newPage()
                    var done: CGFloat = 0
                    while done < size.height {
                        let slice = min(pageHeight, size.height - done)
                        if done > 0 { newPage() }
                        place(draw, size: size, topOffset: 0, sliceFrom: done, sliceHeight: slice)
                        used = slice
                        done += slice
                    }
                }
            }
        }
        if open { pdf.endPDFPage() } else { pdf.beginPDFPage(nil); pdf.endPDFPage() }
        pdf.closePDF()
        return data as Data

        /// Draws the part of the block between `sliceFrom` and `sliceFrom + sliceHeight` at `topOffset` below the top margin.
        func place(_ draw: (CGContext) -> Void, size: CGSize, topOffset: CGFloat, sliceFrom: CGFloat, sliceHeight: CGFloat) {
            pdf.saveGState()
            let originY = paperSize.height - margins.top - topOffset   // top edge of the slice, PDF y goes up
            pdf.clip(to: CGRect(x: margins.left, y: originY - sliceHeight, width: contentWidth, height: sliceHeight))
            // The block's own origin is its lower-left corner; put its top edge at `originY + sliceFrom`.
            pdf.translateBy(x: margins.left, y: originY + sliceFrom - size.height)
            draw(pdf)
            pdf.restoreGState()
        }
    }
}
