import MarkdownCore
import SwiftUI

struct TableBlockView: View {
    let table: TableBlock
    @Environment(\.previewTheme) private var theme
    @Environment(\.exportResources) private var export

    /// An export has no scroll view (`ImageRenderer` cannot draw one): the grid takes the page's width and cells wrap.
    var body: some View {
        if export != nil { grid } else { ScrollView(.horizontal) { grid } }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(table.header.indices, id: \.self) { column in
                    cell(table.header[column], column: column, row: nil)
                }
            }
            ForEach(table.rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(table.rows[row].indices, id: \.self) { column in
                        cell(table.rows[row][column], column: column, row: row)
                    }
                }
            }
        }
        .overlay(Rectangle().stroke(theme.border.color, lineWidth: 1))
    }

    /// `row == nil` is the header row.
    private func cell(_ content: [Inline], column: Int, row: Int?) -> some View {
        InlineText(inlines: content, slot: SearchRunKey.cell(line: 0, row: (row ?? -1) + 1, column: column).slot)
            .fontWeight(row == nil ? .semibold : .regular)
            .multilineTextAlignment(textAlignment(column))
            .frame(maxWidth: .infinity, alignment: frameAlignment(column))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(row.map { $0 % 2 == 1 } == true ? theme.tableStripe.color : .clear)
            .border(theme.border.color, width: 0.5)
    }

    private func alignment(_ column: Int) -> TableBlock.Alignment {
        table.alignments.indices.contains(column) ? table.alignments[column] : .none
    }

    private func frameAlignment(_ column: Int) -> Alignment {
        switch alignment(column) {
        case .center: .center
        case .right: .trailing
        case .left, .none: .leading
        }
    }

    private func textAlignment(_ column: Int) -> TextAlignment {
        switch alignment(column) {
        case .center: .center
        case .right: .trailing
        case .left, .none: .leading
        }
    }
}
