import AppKit
import SwiftUI

/// The editing pane: an AppKit NSTextView (TextKit 2) in a scroll view.
public struct MarkdownEditorView: NSViewRepresentable {
    @Binding private var text: String
    private let configuration: EditorConfiguration

    public init(text: Binding<String>, configuration: EditorConfiguration = .macDownDefaults) {
        _text = text
        self.configuration = configuration
    }

    public func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(text: $text)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        context.coordinator.attach(to: textView, configuration: configuration)
        context.coordinator.setText(text)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.apply(configuration)
        context.coordinator.setText(text)
    }
}
