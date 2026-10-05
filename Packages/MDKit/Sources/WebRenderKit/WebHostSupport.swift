import AppKit
import WebKit

/// A window that is on no screen. A web view without a window is treated as hidden: WebKit throttles
/// its timers and animation frames, and mermaid/KaTeX measure text through the layout. In a window
/// (even one at x = -30000) it lays out and paints like any other, and nobody ever sees it.
final class OffscreenWindow: NSWindow {
    init() {
        super.init(contentRect: NSRect(x: -30_000, y: -30_000, width: 1_200, height: 800),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        hasShadow = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.stationary, .ignoresCycle, .transient, .fullScreenNone]
        backgroundColor = .clear
        isOpaque = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit drags titled and borderless windows back onto a screen; this one stays where it is.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func resizeContent(to size: CGSize) {
        setFrame(NSRect(x: -30_000, y: -30_000, width: max(1, size.width), height: max(1, size.height)), display: false)
    }
}

/// Blocks every load that is not a local file or a data: URL. The web views never need the network,
/// so a diagram or HTML block that tries to fetch something simply gets nothing.
enum NetworkBlocker {
    private static let rules = """
    [
      {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^file://"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}}
    ]
    """

    @MainActor private static var compiled: WKContentRuleList?

    @MainActor static func ruleList() async throws -> WKContentRuleList {
        if let compiled { return compiled }
        guard let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "com.kemalmaulana.mdsyndrome.block-network", encodedContentRuleList: rules) else {
            throw RenderError.unavailable("The network blocking rules did not compile")
        }
        compiled = list
        return list
    }
}

/// Navigation, popup and dialog lockdown for a hidden web view, plus the load and crash callbacks the
/// host waits on.
@MainActor
final class NavigationLock: NSObject, WKNavigationDelegate, WKUIDelegate {
    /// The one URL the web view may load (the shell page, or `about:blank` for HTML snapshots).
    var allowedURL: URL?
    var onTerminate: (() -> Void)?
    private var pendingLoad: CheckedContinuation<Void, Error>?
    private var allowedOnce = true

    /// Suspends until the page that was just requested has finished loading.
    func waitForLoad(_ start: () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingLoad = continuation
            start()
        }
    }

    func cancelPendingLoad(_ error: Error) {
        pendingLoad?.resume(throwing: error)
        pendingLoad = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Only our own load; never a link, a redirect, a form or a script-initiated navigation.
        if allowedOnce, navigationAction.targetFrame?.isMainFrame == true, navigationAction.navigationType == .other,
           let url = navigationAction.request.url, let allowedURL, Self.sameLocation(url, allowedURL) {
            allowedOnce = false
            return .allow
        }
        // A cancelled navigation reports nothing back, so a load that is waiting must be told.
        cancelPendingLoad(RenderError.unavailable("Navigation to \(navigationAction.request.url?.absoluteString ?? "?") was blocked"))
        return .cancel
    }

    private static func sameLocation(_ a: URL, _ b: URL) -> Bool {
        if a.scheme == "about", b.scheme == "about" { return a.absoluteString == b.absoluteString }
        return a.isFileURL && b.isFileURL && a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pendingLoad?.resume()
        pendingLoad = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pendingLoad?.resume(throwing: RenderError.unavailable(error.localizedDescription))
        pendingLoad = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        pendingLoad?.resume(throwing: RenderError.unavailable(error.localizedDescription))
        pendingLoad = nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        cancelPendingLoad(RenderError.crashed)
        onTerminate?()
    }

    // The page never gets to open windows or show dialogs.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {}

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool { false }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? { nil }
}
