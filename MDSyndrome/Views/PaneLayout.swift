import SwiftUI

/// Editor | preview split with a draggable divider. Both panes always stay in
/// the view tree (hidden panes get zero width), so the editor keeps its undo
/// stack, selection and scroll position across mode switches.
struct PaneLayout<Editor: View, Preview: View>: View {
    let mode: LayoutMode
    /// Editor width as a fraction of the window, used in split mode.
    @Binding var ratio: Double
    @ViewBuilder var editor: Editor
    @ViewBuilder var preview: Preview

    private let minimumPaneWidth: Double = 200

    var body: some View {
        GeometryReader { geometry in
            let total = geometry.size.width
            HStack(spacing: 0) {
                editor
                    .frame(width: editorWidth(total: total))
                    .opacity(mode == .preview ? 0 : 1)
                    .accessibilityHidden(mode == .preview)
                if mode == .split {
                    divider(total: total)
                }
                preview
                    .frame(maxWidth: .infinity)
                    .opacity(mode == .editor ? 0 : 1)
                    .accessibilityHidden(mode == .editor)
            }
        }
    }

    func editorWidth(total: Double) -> Double {
        switch mode {
        case .editor: total
        case .preview: 0
        case .split: Self.clampedEditorWidth(total: total, ratio: ratio, minimum: minimumPaneWidth)
        }
    }

    static func clampedEditorWidth(total: Double, ratio: Double, minimum: Double) -> Double {
        guard total > minimum * 2 else { return total / 2 }
        return min(max(total * ratio, minimum), total - minimum)
    }

    private func divider(total: Double) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        guard total > 0 else { return }
                        ratio = min(max(value.location.x / total, 0.1), 0.9)
                    }
            )
            .accessibilityHidden(true)
    }
}
