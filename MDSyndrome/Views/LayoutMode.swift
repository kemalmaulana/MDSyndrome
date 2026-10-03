import SwiftUI

enum LayoutMode: String, CaseIterable, Identifiable {
    case editor, split, preview

    var id: Self { self }

    var title: String {
        switch self {
        case .editor: "Editor"
        case .split: "Editor & Preview"
        case .preview: "Preview"
        }
    }

    var symbol: String {
        switch self {
        case .editor: "doc.plaintext"
        case .split: "rectangle.split.2x1"
        case .preview: "eye"
        }
    }

    /// ⌥⌘1 / ⌥⌘2 / ⌥⌘3
    var shortcut: KeyEquivalent {
        switch self {
        case .editor: "1"
        case .split: "2"
        case .preview: "3"
        }
    }
}

extension FocusedValues {
    @Entry var layoutMode: Binding<LayoutMode>?
}
