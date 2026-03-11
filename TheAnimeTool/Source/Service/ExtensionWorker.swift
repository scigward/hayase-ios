// ExtensionWorker.swift
// Runs one Hayase extension's JavaScript in an isolated WKWebView sandbox.
// Mirrors the role of worker.ts + ExtensionWorker in scigward/interface but uses
// WKWebView instead of Web Workers (not available to Swift code on iOS).
//
// Loading approach:
//   <script type="module"> in loadHTMLString with the direct esm.sh HTTPS URL.
//   This is the most reliable method in WKWebView — static module imports in
//   <script type="module"> are fully supported, and esm.sh sets CORS Allow-Origin: *.
//   No blob URLs, no evaluateJavaScript code injection, no file:// pages.

import Foundation
import WebKit

@MainActor
final class ExtensionWorker: NSObject, WKNavigationDelegate {

    // MARK: - Types

    enum WorkerError: LocalizedError {
        case notLoaded
        case loadFailed(String)
        case callFailed(String)
        case jsonSerialisation

        var errorDescription: String? {
            switch self {
            case .notLoaded:             return "Extension worker not loaded"
            case .loadFailed(let msg):   return "Extension load failed: \(msg)"
            case .callFailed(let msg):   return "Extension call failed: \(msg)"
            case .jsonSerialisation:     return "JSON serialisation error"
            }
        }
    }

    // MARK: - Properties

    let id: String
    private var webView: WKWebView?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var loadTimeoutWork: DispatchWorkItem?
    private var pending: [String: (Result<Any, Error>) -> Void] = [:]

    // MARK: - Initialiser

    init(id: String) {
        self.id = id
        super.init()
    }

    // MARK: - Load

    /// Load the extension from its esm.sh URL into an isolated WKWebView sandbox.
    ///
    /// Uses <script type="module"> with a direct import(url) of the extension's
    /// HTTPS esm.sh URL. This is the most reliable approach in WKWebView:
    ///   - Static/dynamic imports in module scripts work natively
    ///   - esm.sh serves Access-Control-Allow-Origin: * so cross-origin imports work
    ///   - No blob URLs (unreliable in WKWebView), no evaluateJavaScript injection
    ///   - loadHTMLString works without the WKWebView being in the view hierarchy
    func load(extensionURL: URL) async throws {
        let handler = BridgeMessageHandler(worker: self)
        let userContent = WKUserContentController()
        userContent.add(handler, name: "extBridge")

        let config = WKWebViewConfiguration()
        config.userContentController = userContent

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.navigationDelegate = self
        wv.isUserInteractionEnabled = false
        self.webView = wv

        // Escape URL for safe embedding in JS string literal.
        // esm.sh URLs are always clean HTTPS URLs, but be defensive.
        let jsURL = extensionURL.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        // Bootstrap HTML:
        //   1. onerror + unhandledrejection → post 'error' to Swift (catches module load failures)
        //   2. <script type="module"> does import(url) of the extension entry point
        //   3. On success: sets window.__ext, window.__call, posts 'ready'
        //   4. On failure: posts 'error'
        //
        // baseURL = https://esm.sh so the page has esm.sh origin → all esm.sh imports
        // are same-origin. WKWebView supports <script type="module"> fully since iOS 14.
        let html = """
        <!DOCTYPE html><html><head>
        <script>
        window.onerror = function(msg, src, line, col, err) {
            try { window.webkit.messageHandlers.extBridge.postMessage(
                JSON.stringify({type:'error',error:msg||String(err)})); } catch(_){}
            return true;
        };
        window.addEventListener('unhandledrejection', function(e) {
            try {
                var reason = e.reason;
                var msg = (reason && reason.message) ? reason.message : String(reason || 'Unknown error');
                window.webkit.messageHandlers.extBridge.postMessage(
                    JSON.stringify({type:'error',error:msg}));
            } catch(_){}
        });
        </script>
        <script type="module">
        (function() {
          import('\(jsURL)').then(function(mod) {
            window.__ext = mod.default;
            window.__call = async function(callId, method, query, options) {
              try {
                var q = Object.assign({}, query, {fetch: window.fetch.bind(window)});
                var result = await window.__ext[method](q, options);
                window.webkit.messageHandlers.extBridge.postMessage(
                    JSON.stringify({callId: callId, result: result}));
              } catch(e) {
                window.webkit.messageHandlers.extBridge.postMessage(
                    JSON.stringify({callId: callId, error: (e && e.message) ? e.message : String(e)}));
              }
            };
            window.webkit.messageHandlers.extBridge.postMessage(JSON.stringify({type:'ready'}));
          }).catch(function(e) {
            var msg = (e && e.message) ? e.message : String(e);
            window.webkit.messageHandlers.extBridge.postMessage(
                JSON.stringify({type:'error',error:msg}));
          });
        })();
        </script>
        </head><body></body></html>
        """

        try await withCheckedThrowingContinuation { [weak self] (cont: CheckedContinuation<Void, Error>) in
            guard let self else { cont.resume(throwing: WorkerError.notLoaded); return }
            self.readyContinuation = cont

            // 45s timeout — enough for slow CDN + first-ever module graph fetch
            let item = DispatchWorkItem { [weak self] in
                guard let self, let c = self.readyContinuation else { return }
                self.readyContinuation = nil
                c.resume(throwing: WorkerError.loadFailed(
                    "Extension load timed out (45s). Check your network connection."))
            }
            self.loadTimeoutWork = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: item)

            self.webView?.loadHTMLString(html, baseURL: URL(string: "https://esm.sh"))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The <script type="module"> runs automatically as part of page load.
        // 'ready' or 'error' arrives via the extBridge message handler.
        // No code injection needed here.
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadTimeoutWork?.cancel()
        loadTimeoutWork = nil
        let cont = readyContinuation
        readyContinuation = nil
        cont?.resume(throwing: WorkerError.loadFailed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        loadTimeoutWork?.cancel()
        loadTimeoutWork = nil
        let cont = readyContinuation
        readyContinuation = nil
        cont?.resume(throwing: WorkerError.loadFailed(error.localizedDescription))
    }

    /// Called when the WebContent process crashes (OOM, JS engine fault, etc.).
    /// Reject all pending continuations so call() / load() don't hang forever.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadTimeoutWork?.cancel()
        loadTimeoutWork = nil
        let cont = readyContinuation
        readyContinuation = nil
        cont?.resume(throwing: WorkerError.loadFailed("WebContent process terminated"))
        pending.values.forEach { $0(.failure(WorkerError.callFailed("WebContent process terminated"))) }
        pending.removeAll()
    }

    // MARK: - Public API (mirror TorrentSource methods in types.d.ts)

    /// mirrors TorrentSource.single(query, options)
    func single(query: TorrentQuery, options: [String: Any] = [:]) async throws -> [TorrentResult] {
        return try await call(method: "single", query: query.toDict(), options: options)
    }

    /// mirrors TorrentSource.batch(query, options)
    func batch(query: TorrentQuery, options: [String: Any] = [:]) async throws -> [TorrentResult] {
        return try await call(method: "batch", query: query.toDict(), options: options)
    }

    /// mirrors TorrentSource.movie(query, options)
    func movie(query: TorrentQuery, options: [String: Any] = [:]) async throws -> [TorrentResult] {
        return try await call(method: "movie", query: query.toDict(), options: options)
    }

    /// mirrors TorrentSource.test()
    func test() async throws -> Bool {
        let callId = UUID().uuidString
        // 'void' prefix prevents iOS 16+ from awaiting the IIFE's returned Promise (same
        // deadlock fix as call() above).
        let js = """
        void (async () => {
            try {
                var result = await window.__ext.test();
                window.webkit.messageHandlers.extBridge.postMessage(
                    JSON.stringify({callId: '\(callId)', result: result}));
            } catch(e) {
                window.webkit.messageHandlers.extBridge.postMessage(
                    JSON.stringify({callId: '\(callId)', error: String(e.message ?? e)}));
            }
        })();
        """
        let result: Any = try await withCheckedThrowingContinuation { cont in
            pending[callId] = { cont.resume(with: $0) }
            webView?.evaluateJavaScript(js) { [weak self] _, err in
                guard let self, let err else { return }
                if let handler = self.pending.removeValue(forKey: callId) {
                    handler(.failure(err))
                }
            }
        }
        return (result as? Bool) ?? true
    }

    // MARK: - Destroy

    func destroy() {
        loadTimeoutWork?.cancel()
        loadTimeoutWork = nil
        // Resume pending load continuation so load() doesn't hang if destroy() is called
        // before the 'ready' message arrives (prevents CheckedContinuation leak crash)
        let pendingLoad = readyContinuation
        readyContinuation = nil
        pendingLoad?.resume(throwing: WorkerError.notLoaded)
        webView?.removeFromSuperview()
        webView?.stopLoading()
        webView = nil
        pending.values.forEach { $0(.failure(WorkerError.notLoaded)) }
        pending.removeAll()
    }

    // MARK: - Internal call helper

    private func call(method: String, query: [String: Any], options: [String: Any]) async throws -> [TorrentResult] {
        guard webView != nil else { throw WorkerError.notLoaded }

        let callId = UUID().uuidString
        guard let queryData   = try? JSONSerialization.data(withJSONObject: query),
              let optionsData = try? JSONSerialization.data(withJSONObject: options),
              let queryJSON   = String(data: queryData, encoding: .utf8),
              let optionsJSON = String(data: optionsData, encoding: .utf8) else {
            throw WorkerError.jsonSerialisation
        }

        let escapedId = callId.replacingOccurrences(of: "'", with: "\\'")
        // IMPORTANT: prefix with 'void' so evaluateJavaScript sees 'undefined' (not a Promise).
        // Since iOS 16, evaluateJavaScript awaits any returned Promise — which would deadlock:
        // the Promise resolves by calling postMessage, but postMessage delivery needs the main
        // thread that evaluateJavaScript is already blocking. 'void expr' → undefined → no await.
        let js = "void window.__call('\(escapedId)', '\(method)', \(queryJSON), \(optionsJSON));"

        let raw: Any = try await withCheckedThrowingContinuation { cont in
            pending[callId] = { cont.resume(with: $0) }

            // 30s safety timeout — if postMessage is never delivered, unblock the caller.
            let timeoutWork = DispatchWorkItem { [weak self] in
                guard let self, let handler = self.pending.removeValue(forKey: callId) else { return }
                handler(.failure(WorkerError.callFailed("Extension call timed out (30s)")))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeoutWork)

            webView?.evaluateJavaScript(js) { [weak self] _, err in
                // Route errors through the pending handler so cont has a single owner.
                guard let self, let err else { return }
                timeoutWork.cancel()
                if let handler = self.pending.removeValue(forKey: callId) {
                    handler(.failure(err))
                }
            }
        }

        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { TorrentResult(from: $0) }
    }

    // MARK: - Message dispatch (called by BridgeMessageHandler)

    func handleBridgeMessage(_ body: Any) {
        guard let str = body as? String,
              let data = str.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let msgType = dict["type"] as? String

        // 'ready' fires once after bootstrap module script runs successfully
        if msgType == "ready" {
            loadTimeoutWork?.cancel()
            loadTimeoutWork = nil
            let cont = readyContinuation
            readyContinuation = nil
            cont?.resume()
            return
        }

        // 'error' fires when the bootstrap try/catch catches a module import failure
        if msgType == "error" {
            loadTimeoutWork?.cancel()
            loadTimeoutWork = nil
            let cont = readyContinuation
            readyContinuation = nil
            let errMsg = (dict["error"] as? String) ?? "Extension module failed to load"
            cont?.resume(throwing: WorkerError.loadFailed(errMsg))
            return
        }

        guard let callId = dict["callId"] as? String,
              let handler = pending.removeValue(forKey: callId) else { return }

        if let errMsg = dict["error"] as? String {
            handler(.failure(WorkerError.callFailed(errMsg)))
        } else {
            handler(.success(dict["result"] ?? []))
        }
    }

}

// MARK: - WKScriptMessageHandler (holds weak ref to avoid retain cycle)

private class BridgeMessageHandler: NSObject, WKScriptMessageHandler {
    weak var worker: ExtensionWorker?
    init(worker: ExtensionWorker) { self.worker = worker }

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        Task { @MainActor in
            self.worker?.handleBridgeMessage(message.body)
        }
    }
}
