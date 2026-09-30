//
//  WebTorrentBackend.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

enum WebTorrentBackendError: LocalizedError {
    case missingBridgeScript
    case missingTorrentIdentifier
    case invalidTorrentURL(String)
    case torrentURLFetchFailed(url: String, statusCode: Int?, reason: String)
    case emptyTorrentFile(String)
    case startupTimedOut
    case nodeExited(Int32)
    case nodeStartupFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBridgeScript:
            return "WebTorrent bridge script is missing from the app bundle."
        case .missingTorrentIdentifier:
            return "Torrent has no magnet link, download URL, or info hash."
        case .invalidTorrentURL(let value):
            return "Invalid torrent URL: \(value)"
        case .torrentURLFetchFailed(let url, let statusCode, let reason):
            if let statusCode {
                return "Could not download .torrent file (HTTP \(statusCode)): \(url)"
            }
            return "Could not download .torrent file: \(reason) (\(url))"
        case .emptyTorrentFile(let url):
            return "Torrent file request returned an empty body: \(url)"
        case .startupTimedOut:
            return "WebTorrent bridge did not become ready in time."
        case .nodeExited(let code):
            return "NodeMobile exited unexpectedly with code \(code). Restart the app before trying the WebTorrent backend again."
        case .nodeStartupFailed(let reason):
            return "WebTorrent could not start: \(reason)"
        }
    }
}

final class WebTorrentBackend {
    static let shared = WebTorrentBackend()

    private struct Source {
        let payload: Any
        let kind: String
        let preview: String
    }

    private enum StartState {
        case idle
        case starting
        case ready
        case failed(Error)
    }

    private let lock = NSLock()
    private var startState: StartState = .idle
    private var pendingStarts: [(Result<Void, Error>) -> Void] = []
    private let port = 43817
    /// Shared secret for this launch: the bridge answers only requests that present it.
    private let bridgeToken = UUID().uuidString
    private let startupErrorURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("HayaseWebTorrent-startup-error.txt")
    private lazy var bridge = WebTorrentBridgeClient(port: port, token: bridgeToken)
    private var errorTimer: Timer?
    private var lastErrorEventID = 0
    private var errorPollInFlight = false

    private func startErrorNotifications() {
        guard errorTimer == nil else { return }
        errorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.errorPollInFlight else { return }
            self.errorPollInFlight = true
            self.bridge.status { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.errorPollInFlight = false
                    guard case .success(let status) = result else { return }
                    for event in status.events ?? [] {
                        guard let id = event.id, id > self.lastErrorEventID else { continue }
                        self.lastErrorEventID = id
                        guard event.userFacing == true else { continue }
                        TorrentErrorToast.show(event.message, title: event.title ?? "Torrent Process Error!")
                    }
                }
            }
        }
    }

    private init() {}

    func applySettings() {
        ensureStarted { [weak self] result in
            if case .failure(let error) = result {
                StreamingLogger.shared.error("Failed to apply torrent settings: \(error.localizedDescription)")
                return
            }
            self?.bridge.updateSettings(TorrentBackendSettings()) { result in
                if case .failure(let error) = result {
                    StreamingLogger.shared.error("Failed to apply torrent settings: \(error.localizedDescription)")
                }
            }
        }
    }

    func status(completion: @escaping (Result<WebTorrentBridgeStatus, Error>) -> Void) {
        ensureStarted { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.bridge.status(completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }


    func library(completion: @escaping (Result<[WebTorrentLibraryEntry], Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.library(completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    func torrentInfo(hash: String, completion: @escaping (Result<WebTorrentTorrentInfo, Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.torrentInfo(hash: hash, completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    func peerInfo(hash: String, completion: @escaping (Result<[WebTorrentPeerInfo], Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.peerInfo(hash: hash, completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    func fileInfo(hash: String, completion: @escaping (Result<[WebTorrentFileInfo], Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.fileInfo(hash: hash, completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    func protocolStatus(hash: String, completion: @escaping (Result<WebTorrentProtocolStatus, Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.protocolStatus(hash: hash, completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    func trackers(hash: String, completion: @escaping (Result<[String: WebTorrentTrackerInfo], Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.trackers(hash: hash, completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    func rescanTorrents(hashes: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.rescanTorrents(hashes: hashes, completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    func deleteTorrents(hashes: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.deleteTorrents(hashes: hashes, completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    func createNZB(hash: String, url: String, completion: @escaping (Result<Void, Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.createNZB(hash: hash, url: url, completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    func createHTTPWebSeed(hash: String, seed: WebSeedResult, completion: @escaping (Result<Void, Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.createHTTPWebSeed(hash: hash, seed: seed, completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    // MARK: - Casting

    func listDisplays(completion: @escaping (Result<[WebTorrentDisplay], Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.listDisplays(completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    func playDisplay(host: String,
                     hash: String,
                     id: Int,
                     media: [String: Any],
                     completion: @escaping (Result<Void, Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.playDisplay(host: host, hash: hash, id: id, media: media, completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    func closeDisplay(host: String, completion: @escaping (Result<Void, Error>) -> Void) {
        withReadyBridge { bridge in
            bridge.closeDisplay(host: host, completion: completion)
        } failure: { error in
            completion(.failure(error))
        }
    }

    func playTorrent(torrentEntity: Torrents,
                     mediaID: Int,
                     episode: Int,
                     completion: @escaping (Result<[WebTorrentFile], Error>) -> Void) {
        resolveTorrentSource(for: torrentEntity) { [weak self] sourceResult in
            guard let self else { return }
            switch sourceResult {
            case .success(let source):
                print("WebTorrentBackend: source=\(source.kind) value=\(source.preview)")
                self.ensureStarted { [weak self] startResult in
                    guard let self else { return }
                    switch startResult {
                    case .success:
                        self.bridge.updateSettings(TorrentBackendSettings()) { _ in
                            self.bridge.playTorrent(id: source.payload,
                                                    mediaID: mediaID,
                                                    episode: episode,
                                                    completion: completion)
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func withReadyBridge(_ body: @escaping (WebTorrentBridgeClient) -> Void,
                                 failure: @escaping (Error) -> Void) {
        ensureStarted { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                body(self.bridge)
            case .failure(let error):
                failure(error)
            }
        }
    }

    private func ensureStarted(completion: @escaping (Result<Void, Error>) -> Void) {
        if case .exited(let code) = NodeMobileRuntime.shared.currentState {
            let error = nodeExitError(code)
            lock.lock()
            startState = .failed(error)
            lock.unlock()
            completion(.failure(error))
            return
        }

        lock.lock()
        switch startState {
        case .ready:
            lock.unlock()
            completion(.success(()))
            return
        case .failed(let error):
            lock.unlock()
            completion(.failure(error))
            return
        case .starting:
            pendingStarts.append(completion)
            lock.unlock()
            return
        case .idle:
            startState = .starting
            pendingStarts.append(completion)
            lock.unlock()
        }

        startRuntime()
    }

    private func startRuntime() {
        guard let scriptURL = Bundle.main.url(forResource: "webtorrent-bridge",
                                              withExtension: "js",
                                              subdirectory: "WebTorrentBackend") else {
            finishStart(.failure(WebTorrentBackendError.missingBridgeScript))
            return
        }

        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("HayaseWebTorrent", isDirectory: true)
            .path
        let settings = TorrentBackendSettings()

        do {
            try? FileManager.default.removeItem(at: startupErrorURL)
            try NodeMobileRuntime.shared.start(scriptURL: scriptURL, arguments: [
                "--port", "\(port)",
                "--token", bridgeToken,
                "--download-path", settings.path,
                "--temp-path", tempPath,
                "--startup-error-path", startupErrorURL.path,
            ])
            waitForBridge(attempt: 0, lastError: nil)
        } catch NodeMobileRuntimeError.alreadyStarted {
            waitForBridge(attempt: 0, lastError: nil)
        } catch NodeMobileRuntimeError.exited(let code) {
            finishStart(.failure(nodeExitError(code)))
        } catch {
            finishStart(.failure(error))
        }
    }

    private func waitForBridge(attempt: Int, lastError: Error?) {
        bridge.health { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.finishStart(.success(()))
            case .failure(let error):
                if let bridgeError = error as? WebTorrentBridgeError,
                   case .versionMismatch = bridgeError {
                    self.finishStart(.failure(error))
                    return
                }
                if case .exited(let code) = NodeMobileRuntime.shared.currentState {
                    self.finishStart(.failure(self.nodeExitError(code)))
                    return
                }
                guard attempt < 80 else {
                    self.finishStart(.failure(lastError ?? error))
                    return
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
                    self.waitForBridge(attempt: attempt + 1, lastError: error)
                }
            }
        }
    }

    private func nodeExitError(_ code: Int32) -> Error {
        if let details = try? String(contentsOf: startupErrorURL, encoding: .utf8),
           let firstLine = details.split(separator: "\n").first,
           !firstLine.isEmpty {
            return WebTorrentBackendError.nodeStartupFailed(String(firstLine))
        }
        return WebTorrentBackendError.nodeExited(code)
    }

    private func finishStart(_ result: Result<Void, Error>) {
        lock.lock()
        let completions = pendingStarts
        pendingStarts.removeAll()
        switch result {
        case .success:
            startState = .ready
            DispatchQueue.main.async { [weak self] in self?.startErrorNotifications() }
        case .failure(let error):
            startState = .failed(error)
        }
        lock.unlock()

        DispatchQueue.main.async {
            completions.forEach { $0(result) }
        }
    }

    private func resolveTorrentSource(for torrentEntity: Torrents,
                                      completion: @escaping (Result<Source, Error>) -> Void) {
        let link = Self.clean(torrentEntity.torrentDownloadURL)
        let hash = Self.clean(torrentEntity.torrentHashString)

        if let magnet = Self.magnet(from: link) ?? Self.magnet(from: hash) {
            completion(.success(Source(payload: magnet,
                                       kind: "magnet",
                                       preview: Self.preview(magnet))))
            return
        }

        if let link {
            if Self.isHTTPURL(link) {
                fetchTorrentFile(from: link) { result in
                    switch result {
                    case .success(let data):
                        completion(.success(Source(payload: [
                            "kind": "torrentFileBase64",
                            "data": data.base64EncodedString(),
                            "source": link,
                        ], kind: "torrent-file", preview: Self.preview(link))))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            } else {
                completion(.success(Source(payload: link,
                                           kind: "torrent-id",
                                           preview: Self.preview(link))))
            }
            return
        }

        if let fallback = Self.torrentIdentifier(fromHash: hash) {
            completion(.success(Source(payload: fallback,
                                       kind: "info-hash",
                                       preview: Self.preview(fallback))))
            return
        }

        completion(.failure(WebTorrentBackendError.missingTorrentIdentifier))
    }

    private func fetchTorrentFile(from urlString: String,
                                  completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(WebTorrentBackendError.invalidTorrentURL(urlString)))
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-bittorrent,*/*;q=0.8", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(WebTorrentBackendError.torrentURLFetchFailed(url: urlString,
                                                                                  statusCode: nil,
                                                                                  reason: error.localizedDescription)))
                return
            }
            if let statusCode = (response as? HTTPURLResponse)?.statusCode,
               !(200...299).contains(statusCode) {
                completion(.failure(WebTorrentBackendError.torrentURLFetchFailed(url: urlString,
                                                                                  statusCode: statusCode,
                                                                                  reason: HTTPURLResponse.localizedString(forStatusCode: statusCode))))
                return
            }
            guard let data, !data.isEmpty else {
                completion(.failure(WebTorrentBackendError.emptyTorrentFile(urlString)))
                return
            }
            completion(.success(data))
        }.resume()
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isHTTPURL(_ value: String) -> Bool {
        guard let scheme = URL(string: value)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func magnet(from value: String?) -> String? {
        guard let value = clean(value), value.lowercased().hasPrefix("magnet:") else { return nil }
        return value
    }

    private static func torrentIdentifier(fromHash value: String?) -> String? {
        guard let value = clean(value) else { return nil }
        let lower = value.lowercased()
        if lower.hasPrefix("magnet:") || lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return value
        }
        return "magnet:?xt=urn:btih:\(value)"
    }

    private static func preview(_ value: String) -> String {
        if value.count <= 180 { return value }
        let end = value.index(value.startIndex, offsetBy: 177)
        return String(value[..<end]) + "..."
    }
}
