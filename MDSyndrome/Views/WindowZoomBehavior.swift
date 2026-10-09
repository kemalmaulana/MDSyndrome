import AppKit
import SwiftUI

/// Makes the window zoom instead of entering full screen. A window that can enter full screen turns a titlebar
/// double-click and the green button into full screen in a new Space; one that cannot makes both fill the screen
/// (below the menu bar, above the Dock) and a second double-click restores the old size.
struct WindowZoomBehavior: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ZoomBehaviorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ZoomBehaviorView: NSView {
        private var observation: NSKeyValueObservation?
        private var didPrepare = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = nil
            guard let window else { return }
            Self.disableFullScreen(window)
            // SwiftUI sets the behaviour again while it configures the window, so keep correcting it.
            observation = window.observe(\.collectionBehavior) { window, _ in Self.disableFullScreen(window) }
            if !didPrepare {
                didPrepare = true
                Self.rememberNormalSize(window)
            }
        }

        private static func disableFullScreen(_ window: NSWindow) {
            var behavior = window.collectionBehavior
            behavior.subtract([.fullScreenPrimary, .fullScreenAuxiliary])
            behavior.insert(.fullScreenNone)
            if behavior != window.collectionBehavior { window.collectionBehavior = behavior }
        }

        /// A window that opens already filling the screen has no earlier size to go back to, so a second double-click
        /// would only shrink it by a few points. Give it a normal size and zoom it, so AppKit remembers that size.
        private static func rememberNormalSize(_ window: NSWindow) {
            guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame,
                  abs(window.frame.width - visible.width) < 8, abs(window.frame.height - visible.height) < 8 else { return }
            let size = CGSize(width: min(1100, visible.width * 0.8), height: min(760, visible.height * 0.8))
            let normal = CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
            window.setFrame(normal, display: false)
            window.zoom(nil)
        }
    }
}
