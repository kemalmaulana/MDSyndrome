import AppKit
import Foundation
import Testing
import WebKit
@testable import WebRenderKit

/// NF-8: nothing in a document runs, and nothing leaves the machine. The page is attacked from outside
/// (its scripts as a hostile library would) and from inside (hostile document text), and a local server
/// counts any connection a web view makes.
@MainActor
@Suite(.requiresWindowServer) struct SandboxTests {
    private func settle(_ milliseconds: Int = 400) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    /// Runs `body` in the page as a function body and returns its result.
    private func page(_ host: ScriptHost, _ body: String) async throws -> Any? {
        try await host.evaluate(body)
    }

    // MARK: The page itself

    @Test func inlineScriptsAreBlockedByTheCSP() async throws {
        _ = NSApplication.shared
        let host = try await ScriptHost.start()
        defer { host.invalidate() }
        let blocked = try await page(host, """
            const script = document.createElement('script');
            script.textContent = 'window.__ran = true';
            document.body.appendChild(script);
            await new Promise(resolve => setTimeout(resolve, 50));
            return window.__ran === undefined;
        """)
        #expect(blocked as? Bool == true)
    }

    @Test func evalAndFunctionAreBlocked() async throws {
        let host = try await ScriptHost.start()
        defer { host.invalidate() }
        let outcome = try await page(host, """
            const results = [];
            try { eval('1 + 1'); results.push('eval'); } catch (error) { results.push('blocked'); }
            try { new Function('return 1')(); results.push('function'); } catch (error) { results.push('blocked'); }
            return results.join(',');
        """)
        #expect(outcome as? String == "blocked,blocked")
    }

    @Test func eventHandlerAttributesDoNotRun() async throws {
        let host = try await ScriptHost.start()
        defer { host.invalidate() }
        let blocked = try await page(host, """
            const image = document.createElement('img');
            image.setAttribute('onerror', 'window.__ran = true');
            image.src = 'data:image/png;base64,AAAA';
            document.body.appendChild(image);
            await new Promise(resolve => setTimeout(resolve, 100));
            return window.__ran === undefined;
        """)
        #expect(blocked as? Bool == true)
    }

    @Test func nothingReachesTheNetwork() async throws {
        let server = try LocalServer()
        let port = try await server.start()
        defer { server.stop() }
        let host = try await ScriptHost.start()
        defer { host.invalidate() }
        let base = LocalServer.url(port: port)
        _ = try await page(host, """
            const base = base_;
            const attempts = [];
            const script = document.createElement('script'); script.src = base + 'a.js'; document.head.appendChild(script);
            const image = new Image(); image.src = base + 'b.png';
            const link = document.createElement('link'); link.rel = 'stylesheet'; link.href = base + 'c.css'; document.head.appendChild(link);
            attempts.push(fetch(base + 'd').catch(() => 'refused'));
            attempts.push(new Promise(resolve => { const x = new XMLHttpRequest(); x.open('GET', base + 'e'); x.onerror = () => resolve('refused'); x.onload = () => resolve('loaded'); x.send(); }));
            try { new WebSocket(base.replace('http', 'ws') + 'f'); } catch (error) {}
            const frame = document.createElement('iframe'); frame.src = base + 'g'; document.body.appendChild(frame);
            await Promise.all(attempts);
            return 'tried';
        """.replacingOccurrences(of: "base_", with: "'\(base)'"))
        await settle(600)
        #expect(server.connections == 0, "the page managed to open \(server.connections) connection(s)")
    }

    @Test func navigatingAwayIsRefused() async throws {
        let server = try LocalServer()
        let port = try await server.start()
        defer { server.stop() }
        let host = try await ScriptHost.start()
        defer { host.invalidate() }
        _ = try await page(host, "setTimeout(() => { location.href = '\(LocalServer.url(port: port))' }, 0); return 1")
        await settle()
        let stillTheShell = try await page(host, "return location.protocol")
        #expect(stillTheShell as? String == "file:")
        #expect(server.connections == 0)
        // And the page still works afterwards.
        let image = try await host.render(RenderRequest(kind: .mermaid, source: "flowchart LR\n  A --> B"))
        #expect(PictureProbe.isPDF(image))
    }

    @Test func theNavigationLockKeepsThePageOnTheShell() async throws {
        // A file: URL inside the app bundle passes the rule list and the read-access limit, so only the
        // navigation delegate stands between the page and navigating to it.
        let host = try await ScriptHost.start()
        defer { host.invalidate() }
        _ = try await page(host, "setTimeout(() => { location.href = 'katex/katex.min.css' }, 0); return 1")
        await settle()
        let location = try await page(host, "return location.href")
        #expect((location as? String)?.hasSuffix("shell.html") == true, "\(String(describing: location))")
        let image = try await host.render(RenderRequest(kind: .mermaid, source: "flowchart LR\n  A --> B"))
        #expect(PictureProbe.isPDF(image))
    }

    @Test func theRuleListBlocksWhatThePageSecurityPolicyDoesNotCover() async throws {
        let server = try LocalServer()
        let port = try await server.start()
        defer { server.stop() }
        let url = LocalServer.url(port: port)
        // A bare web view with no CSP, loading the same hostile page with and without the app's rules.
        func load(withRules: Bool) async throws {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            if withRules { configuration.userContentController.add(try await NetworkBlocker.ruleList()) }
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 200), configuration: configuration)
            let window = OffscreenWindow()
            window.contentView = webView
            window.orderFrontRegardless()
            let lock = NavigationLock()
            webView.navigationDelegate = lock
            lock.allowNextLoad(of: URL(string: "about:blank")!)
            try await lock.waitForLoad {
                webView.loadHTMLString("<img src=\"\(url)i.png\"><link rel=\"stylesheet\" href=\"\(url)s.css\"><script src=\"\(url)a.js\"></script>", baseURL: nil)
            }
            await settle(500)
            webView.navigationDelegate = nil
            window.close()
        }
        try await load(withRules: false)
        let control = server.connections
        #expect(control > 0, "control: without the rules the page does reach the server, so this test can see a leak")
        try await load(withRules: true)
        #expect(server.connections == control, "with the rules it made \(server.connections - control) more connection(s)")
    }

    @Test func popupsAndDialogsAreRefusedWithoutBlocking() async throws {
        let host = try await ScriptHost.start()
        defer { host.invalidate() }
        let outcome = try await page(host, """
            const opened = window.open('about:blank');
            alert('hello');
            const confirmed = confirm('sure?');
            const answer = prompt('name?', 'x');
            return JSON.stringify({ opened: opened === null, confirmed, answer });
        """)
        #expect(outcome as? String == #"{"opened":true,"confirmed":false,"answer":null}"#)
    }

    // MARK: Hostile document text

    @Test func mermaidLabelsCannotRunScripts() async throws {
        let host = try await ScriptHost.start()
        defer { host.invalidate() }
        let source = """
        flowchart LR
          A["<img src=x onerror='window.__pwned=1'>"] --> B["<script>window.__pwned=2</script>"]
          C["<a href='javascript:window.__pwned=3'>click</a>"] --> D
          click A call window.__pwned=4()
          click B "javascript:window.__pwned=5"
        """
        _ = try? await host.render(RenderRequest(kind: .mermaid, source: source))
        await settle()
        let state = try await page(host, """
            const stage = document.getElementById('stage');
            return JSON.stringify({
              pwned: window.__pwned === undefined,
              handlers: stage.querySelectorAll('[onerror],[onclick],[onload]').length,
              scripts: stage.querySelectorAll('script').length,
              jsLinks: stage.querySelectorAll('a[href^="javascript"], [xlink\\\\:href^="javascript"]').length,
            });
        """)
        #expect(state as? String == #"{"pwned":true,"handlers":0,"scripts":0,"jsLinks":0}"#, "\(String(describing: state))")
    }

    /// A diagram can carry its own configuration (`%%{init: …}%%`). Mermaid protects a few keys from it; this
    /// pins that `securityLevel` is one of them, so a document cannot switch label sanitising off.
    @Test func aDocumentCannotLoosenMermaidsSecurityLevel() async throws {
        let host = try await ScriptHost.start()
        defer { host.invalidate() }
        let source = """
        %%{init: {"securityLevel": "loose", "flowchart": {"htmlLabels": true}}}%%
        flowchart LR
          A["<img src=x onerror='window.__pwned=1'>"] --> B
        """
        _ = try? await host.render(RenderRequest(kind: .mermaid, source: source))
        await settle()
        let state = try await page(host, """
            const stage = document.getElementById('stage');
            return JSON.stringify({
              level: mermaid.mermaidAPI.getConfig().securityLevel,
              pwned: window.__pwned === undefined,
              handlers: stage.querySelectorAll('[onerror],[onclick],[onload]').length,
            });
        """)
        #expect(state as? String == #"{"level":"strict","pwned":true,"handlers":0}"#, "\(String(describing: state))")
    }

    @Test func katexRefusesLinksAndIncludedFiles() async throws {
        let server = try LocalServer()
        let port = try await server.start()
        defer { server.stop() }
        let host = try await ScriptHost.start()
        defer { host.invalidate() }
        let url = LocalServer.url(port: port, "p.png")
        for source in ["\\href{javascript:window.__pwned=1}{x}", "\\url{javascript:window.__pwned=1}", "\\includegraphics{\(url)}", "\\htmlClass{evil}{x}", "\\htmlData{k=v}{x}", "\\htmlId{evil}{x}", "\\htmlStyle{color:red}{x}"] {
            _ = try? await host.render(RenderRequest(kind: .katex(display: false), source: source))
        }
        await settle()
        let state = try await page(host, """
            const stage = document.getElementById('stage');
            return JSON.stringify({
              pwned: window.__pwned === undefined,
              links: stage.querySelectorAll('a[href]').length,
              images: stage.querySelectorAll('img').length,
              custom: stage.querySelectorAll('.evil, #evil, [data-k]').length,
            });
        """)
        #expect(state as? String == #"{"pwned":true,"links":0,"images":0,"custom":0}"#, "\(String(describing: state))")
        #expect(server.connections == 0)
    }

    @Test func documentTextIsPassedAsDataNeverAsScript() async throws {
        let host = try await ScriptHost.start()
        defer { host.invalidate() }
        let hostile = [
            "\"); window.__owned = true; (\"",
            "'); window.__owned = true; ('",
            "`); window.__owned = true; (`",
            "\\u0022); window.__owned = true; //",
            "</script><script>window.__owned = true</script>",
            "${window.__owned = true}",
        ]
        for text in hostile {
            _ = try? await host.render(RenderRequest(kind: .katex(display: false), source: text))
            _ = try? await host.render(RenderRequest(kind: .mermaid, source: text))
            _ = try? await host.render(RenderRequest(kind: .graphviz, source: text))
        }
        let owned = try await page(host, "return window.__owned === undefined")
        #expect(owned as? Bool == true)
    }

    @Test func graphvizCannotFetchImagesOrLinks() async throws {
        let server = try LocalServer()
        let port = try await server.start()
        defer { server.stop() }
        let host = try await ScriptHost.start()
        defer { host.invalidate() }
        let url = LocalServer.url(port: port, "i.png")
        let source = """
        digraph { a [image="\(url)"]; b [label="x", URL="javascript:window.__pwned=1"]; a -> b [href="javascript:window.__pwned=2"] }
        """
        _ = try? await host.render(RenderRequest(kind: .graphviz, source: source))
        await settle()
        let state = try await page(host, """
            const stage = document.getElementById('stage');
            return JSON.stringify({ pwned: window.__pwned === undefined, jsLinks: stage.querySelectorAll('a[*|href^="javascript"]').length });
        """)
        #expect((state as? String)?.contains(#""pwned":true"#) == true, "\(String(describing: state))")
        #expect(server.connections == 0)
    }

    // MARK: Raw HTML

    @Test func htmlBlocksRunNoScriptsAndLoadNothing() async throws {
        let server = try LocalServer()
        let port = try await server.start()
        defer { server.stop() }
        let host = try await SnapshotHost.start()
        defer { host.invalidate() }
        let base = LocalServer.url(port: port)
        let hostile = """
        <script>document.title = 'script ran'</script>
        <img src="x" onerror="document.title = 'onerror ran'">
        <img src="\(base)image.png" width="20" height="20">
        <iframe src="\(base)frame"></iframe>
        <object data="\(base)object"></object>
        <embed src="\(base)embed">
        <video src="\(base)video" poster="\(base)poster.png"></video>
        <link rel="stylesheet" href="\(base)style.css">
        <style>@import url("\(base)import.css"); body { background-image: url("\(base)bg.png"); } p::before { content: url("\(base)before.png") }</style>
        <meta http-equiv="refresh" content="0; url=\(base)refresh">
        <form action="\(base)form" method="post"><input name="a" value="1" autofocus><button>go</button></form>
        <a href="javascript:document.title = 'link ran'">link</a>
        <svg onload="document.title = 'svg ran'"><image href="\(base)svgimage.png"/></svg>
        <p onclick="document.title = 'click ran'" style="width: 100px">text</p>
        <body onload="document.title = 'body ran'">
        """
        let image = try await host.render(RenderRequest(kind: .html, source: hostile, width: 400))
        await settle(600)
        #expect(image.size.width >= 120)
        let title = try await host.evaluate("document.title")
        #expect(title as? String == "", "a script in the block ran: \(String(describing: title))")
        #expect(server.connections == 0, "the block made \(server.connections) connection(s)")
    }

    @Test func htmlBlocksCannotRedirectThePage() async throws {
        let host = try await SnapshotHost.start()
        defer { host.invalidate() }
        _ = try await host.render(RenderRequest(kind: .html, source: #"<meta http-equiv="refresh" content="0; url=file:///etc/hosts"><p>kept</p>"#))
        try? await Task.sleep(for: .milliseconds(400))
        let location = try await host.evaluate("location.href")
        #expect((location as? String)?.hasPrefix("about:") == true, "\(String(describing: location))")
        // And the host keeps working.
        let again = try await host.render(RenderRequest(kind: .html, source: "<p>second</p>"))
        #expect(PictureProbe.isPDF(again))
    }

    @Test func htmlBlocksCannotReadLocalFiles() async throws {
        let host = try await SnapshotHost.start()
        defer { host.invalidate() }
        let image = try await host.render(RenderRequest(kind: .html, source: #"<img src="file:///System/Library/CoreServices/DefaultDesktop.heic" width="50" height="50"><iframe src="file:///etc/hosts"></iframe><p>x</p>"#, width: 300))
        // The rule list lets file: through for the shell, but the snapshot page's CSP allows data: images only.
        let loaded = try await host.evaluate("[...document.images].filter(i => i.complete && i.naturalWidth > 0).length")
        #expect(loaded as? Int == 0)
        #expect(PictureProbe.isPDF(image))
    }

    // MARK: Everything together

    @Test func noRequestReachesALocalServerFromAnyRenderer() async throws {
        let server = try LocalServer()
        let port = try await server.start()
        defer { server.stop() }
        let renderer = WebRenderer()
        let url = LocalServer.url(port: port, "x.png")
        _ = try? await renderer.render(RenderRequest(kind: .mermaid, source: #"flowchart LR\#n  A["<img src='\#(url)'>"] --> B"#))
        _ = try? await renderer.render(RenderRequest(kind: .graphviz, source: #"digraph { a [image="\#(url)"] }"#))
        _ = try? await renderer.render(RenderRequest(kind: .katex(display: false), source: "\\includegraphics{\(url)}"))
        _ = try? await renderer.render(RenderRequest(kind: .html, source: #"<img src="\#(url)"><link rel="stylesheet" href="\#(url)">"#))
        await settle(800)
        #expect(server.connections == 0)
    }
}
