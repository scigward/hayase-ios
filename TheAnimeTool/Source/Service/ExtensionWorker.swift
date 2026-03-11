// ExtensionWorker.swift
// Runs one Hayase extension's JavaScript in an isolated WKWebView sandbox.
// Mirrors the role of worker.ts + ExtensionWorker in scigward/interface but uses
// WKWebView instead of Web Workers (iOS does not expose Web Workers to Swift code).
//
// The extension JS code is written to Library/Application Support/Extensions/{id}.js
// so it can be loaded as an ES module via <script type="module"> with a relative import.
// WKWebView loaded with baseURL = that directory can import './id.js' as a module,
// which is exactly what Hayase extensions expect (they use `export default {...}`).

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
    /// Pending call completions keyed by callId UUID string
    private var pending: [String: (Result<Any, Error>) -> Void] = [:]

    // MARK: - Initialiser

    init(id: String) {
        self.id = id
        super.init()
    }

    // MARK: - Load

    /// Write code to disk and load the WKWebView sandbox.
    /// Mirrors CodeManager._loadWorker: write code → create Worker → construct → loaded.
    func load(code: String) async throws {
        let extDir = try extensionsDirectory()
        let codeFile = extDir.appendingPathComponent("\(id).js")
        try code.write(to: codeFile, atomically: true, encoding: .utf8)

        let handler = BridgeMessageHandler(worker: self)
        let userContent = WKUserContentController()
        userContent.add(handler, name: "extBridge")

        let config = WKWebViewConfiguration()
        config.userContentController = userContent
        // Allow file:// access across Extensions directory for ES module imports
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let wv = WKWebView(frame: CGRect(x: -1, y: -1, width: 1, height: 1),
                           configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        // The bootstrap page: a module script that imports the extension, stores it as
        // window.__ext, and exposes window.__call for Swift to invoke methods.
        let bootstrap = """
        <!DOCTYPE html><html><head>
        <script type="module">
        import ext from './\(id).js';
        window.__ext = ext;
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
        </script>
        </head><body></body></html>
        """

        try await withCheckedThrowingContinuation { [weak self] (cont: CheckedContinuation<Void, Error>) in
            guard let self else { cont.resume(throwing: WorkerError.notLoaded); return }
            self.readyContinuation = cont
            self.webView?.loadHTMLString(bootstrap, baseURL: extDir)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
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

        // 'ready' fires once after bootstrap module script runs
        if (dict["type"] as? String) == "ready" {
            let cont = readyContinuation
            readyContinuation = nil
            cont?.resume()
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

    // MARK: - Helpers

    private func extensionsDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Extensions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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
