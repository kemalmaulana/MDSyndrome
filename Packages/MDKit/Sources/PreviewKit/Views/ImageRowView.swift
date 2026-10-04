import MarkdownCore
import SwiftUI

/// One image in a paragraph made only of images, e.g. a README badge row:
/// `[![CI](ci.svg)](https://…) ![License](mit.svg)`.
struct RowImage: Hashable {
    let source: String
    let alt: String
    /// Destination when the image is wrapped in a link.
    let link: String?
}

extension Array where Element == Inline {
    /// The images of a paragraph that holds nothing but images or linked images (whitespace and
    /// line breaks between them are fine). nil when anything else, such as text, is present.
    var imageRow: [RowImage]? {
        var images: [RowImage] = []
        for inline in self {
            switch inline {
            case .text(let s) where s.allSatisfy(\.isWhitespace):
                continue
            case .softBreak, .lineBreak:
                continue
            case .image(let source, _, let alt):
                images.append(RowImage(source: source, alt: alt, link: nil))
            case .link(let destination, _, let content):
                guard case .image(let source, _, let alt)? = content.onlyNonWhitespace else { return nil }
                images.append(RowImage(source: source, alt: alt, link: destination))
            default:
                return nil
            }
        }
        return images.isEmpty ? nil : images
    }
}

struct ImageRowView: View {
    let images: [RowImage]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                if let link = image.link, let url = URL(string: link) {
                    // Link goes through the environment's OpenURLAction, i.e. LinkPolicy.
                    Link(destination: url) {
                        ImageBlockView(source: image.source, alt: image.alt)
                    }
                    .help(link)
                } else {
                    ImageBlockView(source: image.source, alt: image.alt)
                }
            }
        }
    }
}

/// Left-to-right layout that wraps to a new row when the next item doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width, subviews: subviews)
        let width: CGFloat = rows.map { (row: Row) in row.width }.max() ?? 0
        let rowHeights: CGFloat = rows.reduce(0) { (sum: CGFloat, row: Row) in sum + row.height }
        let gaps: CGFloat = spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: rowHeights + gaps)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> [Row] {
        let maxWidth: CGFloat = width ?? .infinity
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil))
            if !row.items.isEmpty, row.width + spacing + size.width > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
