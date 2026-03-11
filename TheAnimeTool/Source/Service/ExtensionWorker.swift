// ExtensionWorker.swift
// Runs one Hayase extension's JavaScript in an isolated WKWebView sandbox.
// Mirrors the role of worker.ts + ExtensionWorker in scigward/interface but uses
// WKWebView instead of Web Workers (iOS does not expose Web Workers to Swift code).
//
// Loading approach mirrors Hayase's worker.ts load():
//   URL.createObjectURL(new Blob([code], {type:'application/javascript'})) + import(url)
// This works because blob: URLs can load https:// sub-imports (esm.sh CORS: *),
// while file:// pages cannot.

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
            case .notLoaded:              return "Extension worker not loaded"
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
    /// Timeout work item that fires if the 'ready' message never arrives
    private var loadTimeoutWork: DispatchWorkItem?
    /// Pending call completions keyed by callId UUID string
    private var pending: [String: (Result<Any, Error>) -> Void] = [:]

    // MARK: - Initialiser

    init(id: String) {
        self.id = id
        super.init()
    }

    // MARK: - Load

    // Pending code to inject after WKWebView finishes loading the bootstrap page.
    // Stored here so webView(_:didFinish:) can access it without capture-list gymnastics.
    private var pendingCode: String?

    /// Load the extension code into an isolated WKWebView sandbox.
    ///
    /// Mirrors Hayase's CodeManager._loadWorker / worker.ts load() exactly:
    ///   1. Hayase worker.ts: URL.createObjectURL(new Blob([code], {type:'application/javascript'}))
    ///                        then import(blobUrl) — dynamic import of a Blob module.
    ///   2. We do the same inside a WKWebView instead of a Web Worker.
    ///
    /// WHY NOT <script type="module"> with file://baseURL (the old approach)?
    ///   Extension code fetched from esm.sh contains bare https:// sub-import statements.
    ///   A file:// page is not allowed to fetch https:// resources (cross-origin policy) —
    ///   the import() fails silently, 'ready' is never posted, and the continuation hangs.
    ///   A blob: URL CAN import https:// resources because esm.sh sets CORS Allow-Origin: *.
    ///   This is exactly the same reason Hayase uses a Web Worker (blob: origin) not a
    ///   <script type="module"> in a regular page.
    func load(code: String) async throws {
        let handler = BridgeMessageHandler(worker: self)
        let userContent = WKUserContentController()
        userContent.add(handler, name: "extBridge")

        let config = WKWebViewConfiguration()
        config.userContentController = userContent
        // No file-access KVC keys needed — we use blob: URLs, not file://

        let wv = WKWebView(frame: CGRect(x: -1, y: -1, width: 1, height: 1),
                           configuration: config)
        wv.navigationDelegate = self
        self.webView = wv
        self.pendingCode = code

        // Bootstrap page — defines window.__loadExtension(code).
        // The actual extension code is injected via evaluateJavaScript after didFinish fires,
        // with code serialised as a JSON string literal so all special characters are safe.
        //
        // __loadExtension mirrors Hayase worker.ts load():
        //   const url = URL.createObjectURL(new Blob([code], {type:'application/javascript'}))
        //   const module = await import(url)
        //   URL.revokeObjectURL(url)
        //   return module.default
        let bootstrap = """
        <!DOCTYPE html><html><head><script>
        window.__loadExtension = async function(code) {
          try {
            const blob = new Blob([code], { type: 'application/javascript' });
            const url = URL.createObjectURL(blob);
            const mod = await import(url);
            URL.revokeObjectURL(url);
            window.__ext = mod.default;
            window.__call = async function(callId, method, query, options) {
              try {
                var result = await window.__ext[method]({...query, fetch: fetch}, options);
                window.webkit.messageHandlers.extBridge.postMessage(
                    JSON.stringify({callId: callId, result: result}));
              } catch(e) {
                window.webkit.messageHandlers.extBridge.postMessage(
                    JSON.stringify({callId: callId, error: String(e.message ?? e)}));
              }
            };
            window.webkit.messageHandlers.extBridge.postMessage(
                JSON.stringify({type: 'ready'}));
          } catch(e) {
            window.webkit.messageHandlers.extBridge.postMessage(
                JSON.stringify({type: 'error', error: String(e.message ?? e)}));
          }
        };
        </script></head><body></body></html>
        """

        try await withCheckedThrowingContinuation { [weak self] (cont: CheckedContinuation<Void, Error>) in
            guard let self else { cont.resume(throwing: WorkerError.notLoaded); return }
            self.readyContinuation = cont

            // 30s timeout — covers slow CDN on first-ever install
            let item = DispatchWorkItem { [weak self] in
                guard let self, let c = self.readyContinuation else { return }
                self.readyContinuation = nil
                c.resume(throwing: WorkerError.loadFailed("Extension load timed out (30s). Check network."))
            }
            self.loadTimeoutWork = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: item)

            // Load from about:blank — no file:// needed
            self.webView?.loadHTMLString(bootstrap, baseURL: nil)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Page is ready. Inject extension code safely using JSON serialisation,
        // which handles backticks, quotes, backslashes, Unicode, etc.
        guard let code = pendingCode else { return }
        pendingCode = nil

        // Wrap code in an array so NSJSONSerialization (which requires a top-level
        // Array or Dictionary) can produce a valid JSON string literal for the string.
        // We then strip the surrounding brackets to get just the quoted string.
        guard let codeData = try? JSONSerialization.data(withJSONObject: [code]),
              let codeArray = String(data: codeData, encoding: .utf8),
              codeArray.count > 2 else {
            loadTimeoutWork?.cancel(); loadTimeoutWork = nil
            let cont = readyContinuation; readyContinuation = nil
            cont?.resume(throwing: WorkerError.loadFailed("Code JSON serialisation failed"))
            return
        }
        // Strip leading "[" and trailing "]" to get the quoted string literal
        let codeJSON = String(codeArray.dropFirst().dropLast())

        webView.evaluateJavaScript("window.__loadExtension(\(codeJSON));") { [weak self] _, err in
            if let err = err {
                self?.loadTimeoutWork?.cancel(); self?.loadTimeoutWork = nil
                let cont = self?.readyContinuation; self?.readyContinuation = nil
                cont?.resume(throwing: WorkerError.loadFailed(err.localizedDescription))
            }
            // On success: wait for 'ready' or 'error' message via extBridge handler
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadTimeoutWork?.cancel()
        loadTimeoutWork = nil
        let cont = readyContinuation
        readyContinuation = nil
        cont?.resume(throwing: WorkerError.loadFailed(error.localizedDescription))
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
        let js = """
        (async () => {
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
                if let err = err {
                    self?.pending.removeValue(forKey: callId)
                    cont.resume(throwing: err)
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
        webView?.loadHTMLString("", baseURL: nil)
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
        let js = "window.__call('\(escapedId)', '\(method)', \(queryJSON), \(optionsJSON));"

        let raw: Any = try await withCheckedThrowingContinuation { cont in
            pending[callId] = { cont.resume(with: $0) }
            webView?.evaluateJavaScript(js) { [weak self] _, err in
                if let err = err {
                    self?.pending.removeValue(forKey: callId)
                    cont.resume(throwing: err)
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
