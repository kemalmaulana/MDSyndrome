import AppKit
import SwiftUI

/// The editing pane: an AppKit text view (TextKit 2) in a scroll view.
public struct MarkdownEditorView: NSViewRepresentable {
    @Binding private var text: String
    private let theme: EditorTheme
    private let configuration: EditorConfiguration
    private let isHidden: Bool
    private let controller: EditorController?

    /// - Parameters:
    ///   - isHidden: set when the layout hides the editor (Preview-only mode). The view stays
    ///     alive so undo, selection and scroll survive, but it must give up keyboard focus.
    ///   - controller: lets menus and the toolbar run Format commands on this editor.
    public init(text: Binding<String>, theme: EditorTheme = .tomorrowPlus, configuration: EditorConfiguration = .macDownDefaults,
                isHidden: Bool = false, controller: EditorController? = nil) {
        _text = text
        self.theme = theme
        self.configuration = configuration
        self.isHidden = isHidden
        self.controller = controller
    }

    public func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(text: $text)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = Self.makeViews()
        context.coordinator.attach(to: textView, scrollView: scrollView, theme: theme, configuration: configuration, controller: controller)
        context.coordinator.setText(text)
        scrollView.isHidden = isHidden
        return scrollView
    }

    /// A scroll view holding a TextKit 2 `MarkdownTextView`, set up the way `NSTextView.scrollableTextView()` does.
    static func makeViews() -> (NSScrollView, MarkdownTextView) {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = MarkdownTextView(usingTextLayoutManager: true)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.apply(theme: theme, configuration: configuration)
        context.coordinator.setText(text)
        context.coordinator.setHidden(isHidden, scrollView: scrollView)
    }
}
