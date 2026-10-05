import AppKit
import WebKit

/// The hidden web view that runs mermaid, viz.js and KaTeX. It loads one fixed bundled page; document
/// text reaches it only as arguments of `callAsyncJavaScript`, and what comes back is a PDF.
@MainActor
final class ScriptHost: RenderHost {
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

    nonisolated static var resourcesDirectory: URL? {
        Bundle.module.resourceURL?.absoluteURL.appendingPathComponent("Resources", isDirectory: true)
    }

    /// Creates the web view and loads the shell page.
    /// - Parameter transparent: false keeps WebKit's own white page background, as on a macOS without the switch
    ///   `makeBackgroundTransparent` uses. For tests of that fallback.
    static func start(transparent: Bool = true) async throws -> ScriptHost {
        guard let directory = resourcesDirectory else { throw RenderError.unavailable("The renderer resources are missing") }
        let shell = directory.appendingPathComponent("shell.html")
        guard FileManager.default.fileExists(atPath: shell.path) else { throw RenderError.unavailable("shell.html is missing") }
        let rules = try await NetworkBlocker.ruleList()
        let host = ScriptHost(rules: rules, transparent: transparent)
        host.lock.allowNextLoad(of: shell)
        do {
            try await host.lock.waitForLoad {
                host.webView.loadFileURL(shell, allowingReadAccessTo: directory)
            }
        } catch {
            host.invalidate()   // no half-started web view left behind
            throw error
        }
        host.window.orderFrontRegardless()
        return host
    }

    private init(rules: WKContentRuleList, transparent: Bool) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(rules)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1_200, height: 800), configuration: configuration)
        webView.navigationDelegate = lock
        webView.uiDelegate = lock
        webView.autoresizingMask = [.width, .height]
        hasTransparentBackground = transparent && webView.makeBackgroundTransparent()
        window.contentView = webView
    }

    /// Runs `body` in the page and returns its result. For tests, which probe the sandbox from inside.
    func evaluate(_ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
    }

    func invalidate() {
        guard !isInvalid else { return }
        isInvalid = true
        lock.cancelPendingLoad(RenderError.crashed)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.killWebContentProcess()
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }

    func render(_ request: RenderRequest) async throws -> RenderedImage {
        guard isUsable else { throw RenderError.crashed }
        let kind: String
        var options: [String: Any] = [
            "dark": request.appearance == .dark,
            "foreground": request.foreground,
            "background": hasTransparentBackground ? "transparent" : request.background,
            "fontSize": request.fontSize,
            "fontFamily": "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif",
        ]
        switch request.kind {
        case .mermaid: kind = "mermaid"
        case .graphviz: kind = "graphviz"
        case .katex(let display):
            kind = "katex"
            options["display"] = display
        case .html: throw RenderError.unavailable("HTML blocks are rendered by the snapshot host")
        }

        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript("return await MDS.render(kind, source, options)",
                                                           arguments: ["kind": kind, "source": request.source, "options": options],
                                                           in: nil, contentWorld: .page)
        } catch let error as WKError where error.code == .javaScriptExceptionOccurred {
            let message = (error.userInfo["WKJavaScriptExceptionMessage"] as? String) ?? error.localizedDescription
            throw RenderError.syntax(message)
        } catch let error as WKError where error.code == .webContentProcessTerminated {
            throw RenderError.crashed
        } catch {
            if !isUsable { throw RenderError.crashed }
            throw error
        }
        guard let values = result as? [String: Any],
              let width = (values["width"] as? NSNumber)?.doubleValue, let height = (values["height"] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else {
            throw RenderError.unavailable("The renderer returned no size")
        }
        let size = CGSize(width: min(width, 8_000), height: min(height, 8_000))
        window.resizeContent(to: size)
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(origin: .zero, size: size)
        let pdf = try await webView.pdf(configuration: configuration)
        return RenderedImage(pdf: pdf, size: size, baseline: (values["baseline"] as? NSNumber)?.doubleValue)
    }
}
