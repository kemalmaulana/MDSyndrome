import AppKit
import SwiftUI

enum OutlineWidth {
    static let range: ClosedRange<Double> = 160...420
    static let standard: Double = 220
    static func clamped(_ width: Double) -> Double { min(max(width, range.lowerBound), range.upperBound) }
}

/// The divider between the outline and the document: drag it to change the outline's width.
struct OutlineResizeHandle: View {
    @Binding var width: Double
    @State private var startWidth: Double?

    var body: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(drag)
            }
            .accessibilityLabel("Outline width")
            .accessibilityAdjustableAction { direction in
                width = OutlineWidth.clamped(width + (direction == .increment ? 20 : -20))
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { drag in
                let start = startWidth ?? width
                startWidth = start
                width = OutlineWidth.clamped(start + drag.translation.width)
            }
            .onEnded { _ in startWidth = nil }
    }
}
