// ExtensionWorker.swift
// Runs one Hayase extension's JavaScript in an isolated WKWebView sandbox.
// Mirrors the role of worker.ts + ExtensionWorker in scigward/interface but uses
// WKWebView instead of Web Workers (not available to Swift code on iOS).
//
// Loading approach:
//   <script type="module"> in loadHTMLString, which defines `__loadExtension`; the native side calls it once
//   the page has loaded. The code the interface keeps (storage.ts `CodeManager`, which hands the saved code to its
//   worker as a Blob URL) is imported the same way; when there is none, or it does not load, the extension is
//   imported from its esm.sh HTTPS URL, which is the most reliable method in WKWebView — static module
//   imports in <script type="module"> are fully supported, and esm.sh sets CORS Allow-Origin: *.

import Foundation
import WebKit

@MainActor
final class ExtensionWorker: NSObject, WKNavigationDelegate {

    // MARK: - Types

    enum WorkerError: LocalizedError {
        case notLoaded
        case loadFailed(String)
        case callFailed(String)
        case timedOut(TimeInterval)
        case jsonSerialisation

        var errorDescription: String? {
            switch self {
            case .notLoaded:             return "Extension worker not loaded"
            case .loadFailed(let msg):   return "Extension load failed: \(msg)"
            case .callFailed(let msg):   return "Extension call failed: \(msg)"
            case .timedOut(let seconds): return "Extension call failed: Timed out after \(Int(seconds)) seconds."
            case .jsonSerialisation:     return "JSON serialisation error"
            }
        }
    }

    // MARK: - Properties

    let id: String
    private var webView: WKWebView?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var loadTimeoutWork: DispatchWorkItem?
    /// `__loadExtension(code, url)` as JavaScript, for when the page has loaded
    private var pendingBootstrap: String?
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
    func load(extensionURL: URL, code: String? = nil) async throws {
        let handler = BridgeMessageHandler(worker: self)
        let userContent = WKUserContentController()
        userContent.add(handler, name: "extBridge")

        let config = WKWebViewConfiguration()
        config.userContentController = userContent

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.navigationDelegate = self
        wv.isUserInteractionEnabled = false
        self.webView = wv

        // the saved code (or null) and the URL, as JavaScript literals
        pendingBootstrap = "(function(){ window.__loadExtension(\(Self.javaScriptLiteral(code)), \(Self.javaScriptLiteral(extensionURL.absoluteString))); })();"

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
          function ready(mod) {
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
          }
          function fail(e) {
            var msg = (e && e.message) ? e.message : String(e);
            window.webkit.messageHandlers.extBridge.postMessage(
                JSON.stringify({type:'error',error:msg}));
          }
          // worker.ts `load`: the saved code is imported from a Blob URL. A code that does not load that way
          // (or none saved) is imported from the address it comes from.
          window.__loadExtension = function(code, url) {
            if (code === null) {
              import(url).then(ready).catch(fail);
              return;
            }
            var blobURL = URL.createObjectURL(new Blob([code], {type: 'application/javascript'}));
            import(blobURL).then(function(mod) {
              URL.revokeObjectURL(blobURL);
              ready(mod);
            }).catch(function() {
              URL.revokeObjectURL(blobURL);
              import(url).then(ready).catch(fail);
            });
          };
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
        // The <script type="module"> has defined `__loadExtension` by now; 'ready' or 'error' arrives via the
        // extBridge message handler once the extension has been imported.
        guard let bootstrap = pendingBootstrap else { return }
        pendingBootstrap = nil
        webView.evaluateJavaScript(bootstrap, completionHandler: nil)
    }

    /// A string as a JavaScript literal (`null` for none).
    private static func javaScriptLiteral(_ value: String?) -> String {
        guard let value, let data = try? JSONEncoder().encode(value), let literal = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return literal
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
        return Self.torrentResults(try await call(method: "single", query: query.toDict(), options: options))
    }

    /// mirrors TorrentSource.batch(query, options)
    func batch(query: TorrentQuery, options: [String: Any] = [:]) async throws -> [TorrentResult] {
        return Self.torrentResults(try await call(method: "batch", query: query.toDict(), options: options))
    }

    /// mirrors TorrentSource.movie(query, options)
    func movie(query: TorrentQuery, options: [String: Any] = [:]) async throws -> [TorrentResult] {
        return Self.torrentResults(try await call(method: "movie", query: query.toDict(), options: options))
    }

    /// mirrors TorrentSource.test()
    func test() async throws -> Bool {
        let result = try await testResult()
        return (result as? Bool) ?? true
    }

    /// Keep a provider's custom status text for the settings tooltip instead of collapsing it to true.
    func testResult() async throws -> Any {
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
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: WorkerError.notLoaded)
                    return
                }
                self.pending[callId] = { cont.resume(with: $0) }

                // Match the upstream web loader's extension check timeout.
                let timeoutWork = DispatchWorkItem { [weak self] in
                    guard let self, let handler = self.pending.removeValue(forKey: callId) else { return }
                    self.callTimeouts.removeValue(forKey: callId)
                    handler(.failure(WorkerError.callFailed("Extension check timed out.")))
                }
                self.callTimeouts[callId] = timeoutWork
                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeoutWork)

                self.webView?.evaluateJavaScript(js) { [weak self] _, err in
                    guard let self, let err else { return }
                    self.callTimeouts.removeValue(forKey: callId)?.cancel()
                    if let handler = self.pending.removeValue(forKey: callId) {
                        handler(.failure(err))
                    }
                }
            }
        }
        return result
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

    // MARK: - Calls

    /// Calls `method` on the extension module and returns its raw JSON result.
    /// NZB and HTTP sources share the method names of torrent sources but
    /// return their own result shapes, so decoding is left to the caller.
    func call(method: String,
              query: [String: Any],
              options: [String: Any],
              timeout: TimeInterval = 20) async throws -> Any {
        guard webView != nil else { throw WorkerError.notLoaded }

        let callId = UUID().uuidString
        guard let queryData   = JSONSerialization.safeData(query),
              let optionsData = JSONSerialization.safeData(options),
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

        return try await withCheckedThrowingContinuation { cont in
            Task { @MainActor [weak self] in
                guard let self, let webView = self.webView else {
                    cont.resume(throwing: WorkerError.notLoaded)
                    return
                }

                self.pending[callId] = { cont.resume(with: $0) }

                // The 20s default matches the interface's raceWithHandler().
                let timeoutWork = DispatchWorkItem { [weak self] in
                    guard let self, let handler = self.pending.removeValue(forKey: callId) else { return }
                    self.callTimeouts.removeValue(forKey: callId)
                    handler(.failure(WorkerError.timedOut(timeout)))
                }
                self.callTimeouts[callId] = timeoutWork
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

                webView.evaluateJavaScript(js) { [weak self] _, err in
                    // Route errors through the pending handler so cont has a single owner.
                    guard let self, let err else { return }
                    self.callTimeouts.removeValue(forKey: callId)?.cancel()
                    if let handler = self.pending.removeValue(forKey: callId) {
                        handler(.failure(err))
                    }
                }
            }
        }
    }

    private static func torrentResults(_ raw: Any) -> [TorrentResult] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { TorrentResult(from: $0) }
    }

    // MARK: - Message dispatch (called by BridgeMessageHandler)

    /// Rejects a pending proxied fetch. The message goes through JSON so it cannot break out of the script.
    private static func rejectFetch(_ id: Int, _ message: String, in webView: WKWebView?) {
        guard let data = JSONSerialization.safeData([message]),
              let array = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__fetchReject(\(id),\(array)[0]);", completionHandler: nil)
    }

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
                Self.rejectFetch(fetchId, "Invalid URL: \(urlStr.prefix(80))", in: webView)
                return
            }
            guard ExtensionFetchPolicy.allows(url) else {
                Self.rejectFetch(fetchId, "Request blocked: \(url.scheme ?? "")://\(url.host ?? "") is not allowed", in: webView)
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
                    let (data, resp) = try await ExtensionFetchPolicy.session.data(for: req)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 200
                    let bodyBase64 = data.base64EncodedString()
                    // JSON-encode base64 so it is safe to embed in the JS call.
                    guard let td  = JSONSerialization.safeData([bodyBase64]),
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
                    Self.rejectFetch(fetchId, error.localizedDescription, in: wv)
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
