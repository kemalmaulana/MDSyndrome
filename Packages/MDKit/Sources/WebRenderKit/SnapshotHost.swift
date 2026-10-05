import AppKit
import WebKit

/// Draws a raw HTML block as a picture. JavaScript is off for the page itself, so nothing in the block can
/// run; the page's CSP and the blocked network leave it nothing to load either.
@MainActor
final class SnapshotHost: RenderHost {
    private let window = OffscreenWindow()
    private let webView: WKWebView
    private let lock = NavigationLock()
    private var isInvalid = false
    private var hasTransparentBackground = true

    var isUsable: Bool { !isInvalid }
    var onTerminate: (() -> Void)? {
        get { lock.onTerminate }
        set { lock.onTerminate = newValue }
    }

    static func start(transparent: Bool = true) async throws -> SnapshotHost {
        let rules = try await NetworkBlocker.ruleList()
        let host = SnapshotHost(rules: rules, transparent: transparent)
        host.window.orderFrontRegardless()
        return host
    }

    private init(rules: WKContentRuleList, transparent: Bool) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.userContentController.add(rules)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = lock
        webView.uiDelegate = lock
        webView.autoresizingMask = [.width, .height]
        hasTransparentBackground = transparent && webView.makeBackgroundTransparent()
        window.contentView = webView
    }

    func invalidate() {
        guard !isInvalid else { return }
        isInvalid = true
        lock.cancelPendingLoad(RenderError.crashed)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }

    /// The page around the block. The CSP allows only inline styles and `data:` images and fonts.
    static func document(body: String, style: String, foreground: String, background: String, fontSize: Double, width: Double) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:">
        <style>
        html, body { margin: 0; padding: 0; background: \(background); }
        body { width: \(Int(width))px; color: \(foreground); font: \(fontSize)px/1.5 -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif; overflow-wrap: anywhere; }
        img { max-width: 100%; }
        \(style)
        </style></head>
        <body>\(body)</body></html>
        """
    }

    func render(_ request: RenderRequest) async throws -> RenderedImage {
        guard isUsable else { throw RenderError.crashed }
        guard case .html = request.kind else { throw RenderError.unavailable("The snapshot host draws HTML only") }
        let width = min(max(request.width, 120), 4_000)
        window.resizeContent(to: CGSize(width: width, height: 600))
        let html = Self.document(body: request.source, style: request.style, foreground: request.foreground,
                                 background: hasTransparentBackground ? "transparent" : request.background, fontSize: request.fontSize, width: width)
        lock.allowNextLoad(of: URL(string: "about:blank")!)
        try await lock.waitForLoad {
            webView.loadHTMLString(html, baseURL: nil)
        }
        let measured: Any?
        do {
            measured = try await webView.evaluateJavaScript("[Math.ceil(document.body.scrollWidth), Math.ceil(document.body.getBoundingClientRect().height)]")
        } catch let error as WKError where error.code == .webContentProcessTerminated {
            throw RenderError.crashed
        }
        guard let numbers = measured as? [NSNumber], numbers.count == 2, numbers[1].doubleValue > 0 else {
            throw RenderError.unavailable("The HTML block has no size")
        }
        let size = CGSize(width: min(max(width, numbers[0].doubleValue), 8_000), height: min(numbers[1].doubleValue, 8_000))
        window.resizeContent(to: size)
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(origin: .zero, size: size)
        let pdf = try await webView.pdf(configuration: configuration)
        return RenderedImage(pdf: pdf, size: size)
    }
}
