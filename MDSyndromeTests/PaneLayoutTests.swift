import SwiftUI
import Testing
@testable import MDSyndrome

@Suite struct PaneLayoutTests {
    @Test func splitWidthIsClampedToMinimumPaneWidths() {
        typealias Layout = PaneLayout<EmptyView, EmptyView>
        #expect(Layout.clampedEditorWidth(total: 1000, ratio: 0.5, minimum: 200) == 500)
        #expect(Layout.clampedEditorWidth(total: 1000, ratio: 0.05, minimum: 200) == 200)
        #expect(Layout.clampedEditorWidth(total: 1000, ratio: 0.95, minimum: 200) == 800)
        #expect(Layout.clampedEditorWidth(total: 300, ratio: 0.9, minimum: 200) == 150, "window too narrow: split evenly")
    }
}
