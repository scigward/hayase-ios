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
    /// Stores per-call timeout DispatchWorkItems so they can be cancelled when
    /// the result arrives (prevents 30s leaking work items after every call).
    private var callTimeouts: [String: DispatchWorkItem] = [:]

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
        //   1. window.fetch proxy — routes ALL extension fetch() calls through Swift URLSession.
        //      This is the iOS equivalent of Hayase's native.enableCORS() (Electron/Tauri bypass).
        //      WKWebView enforces CORS: extension fetch() to torrent sites (nyaa.si etc.) is blocked
        //      because those sites don't set Access-Control-Allow-Origin: *.
        //      URLSession has NO CORS restrictions → requests succeed → results returned.
        //   2. onerror + unhandledrejection → post 'error' to Swift (catches module load failures)
        //   3. <script type="module"> does import(url) of the extension entry point
        //   4. On success: sets window.__ext, window.__call, posts 'ready'
        //   5. On failure: posts 'error'
        //
        // The fetch proxy must be in a plain <script> BEFORE the module script so it is
        // already installed when the module executes and Hayase's worker.ts does:
        //   const queryWithFetch = { ...query, fetch }   ← picks up our proxy
        //
        // baseURL = https://esm.sh so the page has esm.sh origin → all esm.sh module
        // imports are same-origin. WKWebView supports <script type="module"> since iOS 14.
        let html = """
        <!DOCTYPE html><html><head>
        <script>
        // ── Native fetch proxy ──────────────────────────────────────────────────────
        // Intercepts window.fetch and routes through Swift URLSession (no CORS limit).
        // Mirrors what Hayase's native.enableCORS() achieves in Electron/Tauri.
        (function() {
          var __pending = new Map();
          var __seq = 0;

          function __bytesFromBase64(base64) {
            var bin = atob(base64 || '');
            var bytes = new Uint8Array(bin.length);
            for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
            return bytes;
          }

          function __base64FromBytes(bytes) {
            var bin = '';
            for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
            return btoa(bin);
          }

          function __decodeText(bytes) {
            try {
              return new TextDecoder('utf-8', {fatal: true}).decode(bytes);
            } catch(e) {
              try { return new TextDecoder('iso-8859-1').decode(bytes); }
              catch(_) { return new TextDecoder().decode(bytes); }
            }
          }

          // Called by Swift after URLSession completes.
          window.__fetchResolve = function(id, status, bodyBase64) {
            var p = __pending.get(id);
            __pending.delete(id);
            if (!p) return;
            var bytes = __bytesFromBase64(bodyBase64);
            p.resolve({
              ok: status >= 200 && status < 300,
              status: status,
              statusText: '',
              url: '',
              headers: { get: function() { return null; }, has: function() { return false; } },
              text: function() { return Promise.resolve(__decodeText(bytes)); },
              json: function() {
                return new Promise(function(res, rej) {
                  try { res(JSON.parse(__decodeText(bytes))); } catch(e) { rej(e); }
                });
              },
              arrayBuffer: function() {
                return Promise.resolve(bytes.slice().buffer);
              },
              blob: function() { return Promise.resolve(new Blob([bytes])); },
              clone: function() { return this; }
            });
          };

          // Called by Swift when URLSession fails.
          window.__fetchReject = function(id, error) {
            var p = __pending.get(id);
            __pending.delete(id);
            if (p) p.reject(new TypeError(String(error)));
          };

          // Override global fetch.
          window.fetch = function(resource, init) {
            var id = ++__seq;
            var url = (typeof resource === 'string') ? resource
                    : (resource && resource.url) ? resource.url : String(resource);
            var method = (init && init.method) ? init.method
                       : (resource && resource.method) ? resource.method : 'GET';
            // Flatten headers to a plain object
            var headers = {};
            var h = (init && init.headers) || (resource && resource.headers);
            if (h) {
              if (typeof h.forEach === 'function') {
                h.forEach(function(v, k) { headers[k] = v; });
              } else if (typeof h === 'object') {
                Object.assign(headers, h);
              }
            }
            var body = null;
            var bodyBase64 = null;
            if (init && init.body != null) {
              if (typeof init.body === 'string') {
                body = init.body;
              } else if (init.body instanceof URLSearchParams) {
                body = init.body.toString();
              } else if (init.body instanceof ArrayBuffer) {
                bodyBase64 = __base64FromBytes(new Uint8Array(init.body));
              } else if (ArrayBuffer.isView(init.body)) {
                bodyBase64 = __base64FromBytes(new Uint8Array(init.body.buffer, init.body.byteOffset, init.body.byteLength));
              } else {
                body = String(init.body);
              }
            }

            return new Promise(function(resolve, reject) {
              __pending.set(id, { resolve: resolve, reject: reject });
              try {
                window.webkit.messageHandlers.extBridge.postMessage(
                  JSON.stringify({ type: 'fetch', fetchId: id, url: url,
                                   method: method, headers: headers, body: body,
                                   bodyBase64: bodyBase64 }));
              } catch(e) {
                __pending.delete(id);
                reject(new TypeError('Fetch proxy unavailable: ' + String(e)));
              }
            });
          };
        })();
        // ── End fetch proxy ─────────────────────────────────────────────────────────

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
                // Pass window.fetch (our proxy) as query.fetch, matching Hayase worker.ts:
                //   const queryWithFetch = { ...query, fetch }
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
        guard webView != nil else { throw WorkerError.notLoaded }
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

            // Match the upstream web loader's extension check timeout.
            let timeoutWork = DispatchWorkItem { [weak self] in
                guard let self, let handler = self.pending.removeValue(forKey: callId) else { return }
                self.callTimeouts.removeValue(forKey: callId)
                handler(.failure(WorkerError.callFailed("Extension check timed out.")))
            }
            callTimeouts[callId] = timeoutWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeoutWork)

            webView?.evaluateJavaScript(js) { [weak self] _, err in
                guard let self, let err else { return }
                self.callTimeouts.removeValue(forKey: callId)?.cancel()
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
        // Cancel all per-call timeouts
        callTimeouts.values.forEach { $0.cancel() }
        callTimeouts.removeAll()
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
                self.callTimeouts.removeValue(forKey: callId)
                handler(.failure(WorkerError.callFailed("Extension call timed out (30s)")))
            }
            callTimeouts[callId] = timeoutWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeoutWork)

            webView?.evaluateJavaScript(js) { [weak self] _, err in
                // Route errors through the pending handler so cont has a single owner.
                guard let self, let err else { return }
                self.callTimeouts.removeValue(forKey: callId)?.cancel()
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

        // 'fetch' — extension called window.fetch(); proxy it through URLSession (no CORS).
        // This is the iOS equivalent of Hayase's native.enableCORS() Electron/Tauri bypass.
        if msgType == "fetch" {
            guard let fetchId = dict["fetchId"] as? Int,
                  let urlStr  = dict["url"] as? String else { return }

            // Build URL with percent-encoding fallback — extensions sometimes pass URLs
            // with unencoded spaces (e.g. "https://nyaa.si/?q=JUJUTSU KAISEN") which
            // URL(string:) rejects. Without the fallback the guard returns silently,
            // the fetch Promise hangs, and 30s later the call times out → "No results found".
            let url: URL
            if let u = URL(string: urlStr) {
                url = u
            } else if let encoded = urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let u = URL(string: encoded) {
                url = u
            } else {
                // URL is genuinely malformed — reject immediately so the extension doesn't hang.
                let wv = webView
                wv?.evaluateJavaScript("window.__fetchReject(\(fetchId),'Invalid URL: \(urlStr.prefix(80))');",
                                       completionHandler: nil)
                return
            }
            let method  = (dict["method"] as? String) ?? "GET"
            let headers = (dict["headers"] as? [String: String]) ?? [:]
            let bodyStr =  dict["body"]   as? String
            let bodyBase64 = dict["bodyBase64"] as? String
            let wv = webView                          // capture before Task
            Task {
                do {
                    var req = URLRequest(url: url, timeoutInterval: 30)
                    req.httpMethod = method
                    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
                    // Send a browser-like UA so torrent sites don't reject the request
                    if req.value(forHTTPHeaderField: "User-Agent") == nil {
                        req.setValue(
                            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
                            "AppleWebKit/537.36 (KHTML, like Gecko) " +
                            "Chrome/120.0.0.0 Safari/537.36",
                            forHTTPHeaderField: "User-Agent")
                    }
                    if let b = bodyStr, !b.isEmpty {
                        req.httpBody = b.data(using: .utf8)
                    } else if let b64 = bodyBase64, !b64.isEmpty {
                        req.httpBody = Data(base64Encoded: b64)
                    }
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 200
                    let bodyBase64 = data.base64EncodedString()
                    // JSON-encode base64 so it is safe to embed in the JS call.
                    guard let td  = try? JSONSerialization.data(withJSONObject: [bodyBase64]),
                          let raw = String(data: td, encoding: .utf8) else {
                        wv?.evaluateJavaScript(
                            "window.__fetchReject(\(fetchId),'Serialization failed');",
                            completionHandler: nil)
                        return
                    }
                    let bodyJSON = String(raw.dropFirst().dropLast()) // strip [ ]
                    // Add a completionHandler so if evaluateJavaScript itself fails
                    // (e.g. webView torn down), we reject
                    // the pending fetch so the extension doesn't hang.
                    wv?.evaluateJavaScript(
                        "window.__fetchResolve(\(fetchId),\(status),\(bodyJSON));") { _, jsErr in
                        if jsErr != nil {
                            wv?.evaluateJavaScript(
                                "window.__fetchReject(\(fetchId),'Response delivery failed');",
                                completionHandler: nil)
                        }
                    }
                } catch {
                    // Escape single quotes so the error message is safe in JS
                    let msg = error.localizedDescription
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'")
                    wv?.evaluateJavaScript(
                        "window.__fetchReject(\(fetchId),'\(msg)');",
                        completionHandler: nil)
                }
            }
            return
        }

        guard let callId = dict["callId"] as? String,
              let handler = pending.removeValue(forKey: callId) else { return }

        // Cancel the per-call timeout now that we have a result/error
        callTimeouts.removeValue(forKey: callId)?.cancel()

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
