import MarkdownCore
import SwiftUI

struct ListBlockView: View {
    let list: ListBlock
    @Environment(\.previewTheme) private var theme
    @Environment(\.listDepth) private var depth

    private var spacing: Double { list.tight ? 4 : theme.blockSpacing / 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(list.items.enumerated()), id: \.element.id) { offset, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    marker(for: item, number: list.start + offset)
                        .frame(minWidth: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: spacing) {
                        ForEach(item.blocks) { BlockView(block: $0) }
                    }
                }
            }
        }
        .environment(\.listDepth, depth + 1)
    }

    @ViewBuilder
    private func marker(for item: ListItem, number: Int) -> some View {
        if let task = item.task {
            Image(systemName: task == .checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(task == .checked ? theme.link.color : theme.secondaryText.color)
                .accessibilityLabel(task == .checked ? "Completed" : "Not completed")
        } else if list.ordered {
            Text("\(number).").monospacedDigit()
        } else {
            Text(["•", "◦", "▪"][depth % 3])
        }
    }
}
