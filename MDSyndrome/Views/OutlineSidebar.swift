import MarkdownCore
import SwiftUI

/// The document's headings, indented by level (NAV-3). Clicking one takes both panes there; the heading the
/// document is at is highlighted and kept in view as the panes scroll.
struct OutlineSidebar: View {
    let items: [OutlineItem]
    /// The heading the document is currently at.
    let current: BlockID?
    let select: (OutlineItem) -> Void

    var body: some View {
        if items.isEmpty {
            Text("No headings")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("outline-sidebar")
        } else {
            ScrollViewReader { proxy in
                List(selection: selection) {
                    ForEach(items) { item in
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                            .font(.system(size: 13, weight: item.level <= 2 ? .semibold : .regular))
                            .lineLimit(1)
                            .padding(.leading, CGFloat(item.level - 1) * 12)
                            .tag(item.id)
                            .accessibilityLabel("Heading level \(item.level): \(item.title)")
                    }
                }
                .listStyle(.sidebar)
                .accessibilityLabel("Outline")
                .accessibilityIdentifier("outline-sidebar")
                .onChange(of: current) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    /// The list's selection is the current heading; choosing another one navigates (the highlight then moves
    /// with the panes, which is what comes back as `current`).
    private var selection: Binding<BlockID?> {
        Binding(
            get: { current },
            set: { id in
                guard let id, id != current, let item = items.first(where: { $0.id == id }) else { return }
                select(item)
            })
    }
}
