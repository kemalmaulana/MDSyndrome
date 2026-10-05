import MarkdownCore
import SwiftUI

/// The document's headings, indented by level (NAV-3). Clicking one takes both panes there; the heading the
/// document is at is highlighted and kept in view as the panes scroll.
///
/// The rows are buttons, not a selection: a selection only reports a change, so clicking the highlighted heading
/// (to go back to its start after scrolling a little) would do nothing.
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
                List {
                    ForEach(items) { item in
                        Button { select(item) } label: {
                            Text(item.title.isEmpty ? "Untitled" : item.title)
                                .font(.system(size: 13, weight: item.level <= 2 || item.id == current ? .semibold : .regular))
                                .lineLimit(1)
                                .padding(.leading, CGFloat(item.level - 1) * 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(item.id == current ? Color.accentColor : Color.primary)
                        .listRowBackground(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(item.id == current ? 0.18 : 0)).padding(.horizontal, 6))
                        .accessibilityLabel("Heading level \(item.level): \(item.title)")
                        .accessibilityAddTraits(item.id == current ? .isSelected : [])
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
}
