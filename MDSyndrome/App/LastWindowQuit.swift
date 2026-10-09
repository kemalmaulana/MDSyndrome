import AppKit

/// Quits the app when its last document window is closed (Settings ▸ General). macOS otherwise keeps an app with no windows
/// running in the Dock. Quitting by hand with ⌘Q is unaffected, and so is an app that never had a window.
@MainActor
enum LastWindowQuit {
    private static var observer: NSObjectProtocol?

    /// Whether closing a window should quit: the setting is on, no document is open, and nothing else the person can see is
    /// (the Settings window, an Open panel).
    static func shouldQuit(enabled: Bool, documents: Int, otherVisibleWindows: Int) -> Bool {
        enabled && documents == 0 && otherVisibleWindows == 0
    }

    /// Windows the person can see that are not documents. The web renderer's hidden windows sit off screen and do not count.
    static func otherVisibleWindows() -> Int {
        NSApp.windows.filter { window in
            window.isVisible && !window.isMiniaturized && (window.canBecomeMain || window is NSPanel) && window.windowController?.document == nil
                && NSScreen.screens.contains { $0.frame.intersects(window.frame) }
        }.count
    }

    private static var defaults = UserDefaults.standard
    private static var wait = Duration.milliseconds(300)
    private static var quit: @MainActor () -> Void = { NSApp.terminate(nil) }

    /// Listens for closing windows. After one closes it waits a moment (opening a file replaces the empty untitled document, so
    /// the document count is briefly zero) and then asks `shouldQuit`.
    static func install(defaults: UserDefaults = .standard, wait: Duration = .milliseconds(300), quit: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }) {
        Self.defaults = defaults
        Self.wait = wait
        Self.quit = quit
        observer.map(NotificationCenter.default.removeObserver)
        observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await windowDidClose() }
        }
    }

    private static func windowDidClose() async {
        try? await Task.sleep(for: wait)
        let enabled = AppSettings(defaults: defaults).quitAfterLastWindow
        if shouldQuit(enabled: enabled, documents: NSDocumentController.shared.documents.count, otherVisibleWindows: otherVisibleWindows()) { quit() }
    }
}
