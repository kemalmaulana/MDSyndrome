import EditorKit
import PreviewKit
import SwiftUI

/// The pane the user last worked in. Find goes there.
enum Pane {
    case editor
    case preview
}

/// Sends a Find command to the editor's find bar or to the preview's, depending on the layout and on
/// where the user is. Replace only exists in the editor.
struct FindRouter {
    enum Target { case editor, preview }

    let editor: EditorController?
    let preview: PreviewSearch?
    let layout: LayoutMode
    let pane: Pane

    func target(for action: FindAction) -> Target? {
        if action == .showReplace { return editor == nil ? nil : .editor }
        switch layout {
        case .editor:
            return editor == nil ? nil : .editor
        case .preview:
            return preview == nil ? nil : .preview
        case .split:
            if pane == .preview, preview != nil { return .preview }
            if editor != nil { return .editor }
            return preview == nil ? nil : .preview
        }
    }

    @MainActor
    func run(_ action: FindAction) {
        switch target(for: action) {
        case .editor?:
            editor?.find(action)
        case .preview?:
            switch action {
            case .show, .showReplace: preview?.show()
            case .next: preview?.next()
            case .previous: preview?.previous()
            }
        case nil:
            break
        }
    }
}

extension FocusedValues {
    @Entry var findRouter: FindRouter?
}
