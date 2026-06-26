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
    case emptyTorrentFile(String)
    case startupTimedOut

    var errorDescription: String? {
        switch self {
        case .missingBridgeScript:
            return "WebTorrent bridge script is missing from the app bundle."
        case .missingTorrentIdentifier:
            return "Torrent has no magnet link, download URL, or info hash."
        case .invalidTorrentURL(let value):
            return "Invalid torrent URL: \(value)"
        case .emptyTorrentFile(let url):
            return "Torrent file request returned an empty body: \(url)"
        case .startupTimedOut:
            return "WebTorrent bridge did not become ready in time."
        }
    }
}

final class WebTorrentBackend {
    static let shared = WebTorrentBackend()

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
    private lazy var bridge = WebTorrentBridgeClient(port: port)

    private init() {}

    func applySettings() {
        ensureStarted { [weak self] result in
            guard case .success = result else { return }
            self?.bridge.updateSettings(TorrentBackendSettings())
        }
    }

    func playTorrent(torrentEntity: Torrents,
                     mediaID: Int,
                     episode: Int,
                     completion: @escaping (Result<[WebTorrentFile], Error>) -> Void) {
        resolveTorrentSource(for: torrentEntity) { [weak self] sourceResult in
            guard let self else { return }
            switch sourceResult {
            case .success(let torrentID):
                self.ensureStarted { [weak self] startResult in
                    guard let self else { return }
                    switch startResult {
                    case .success:
                        self.bridge.updateSettings(TorrentBackendSettings()) { _ in
                            self.bridge.playTorrent(id: torrentID,
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

    private func ensureStarted(completion: @escaping (Result<Void, Error>) -> Void) {
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
            try NodeMobileRuntime.shared.start(scriptURL: scriptURL, arguments: [
                "--port", "\(port)",
                "--download-path", settings.path,
                "--temp-path", tempPath,
            ])
            waitForBridge(attempt: 0)
        } catch NodeMobileRuntimeError.alreadyStarted {
            waitForBridge(attempt: 0)
        } catch {
            finishStart(.failure(error))
        }
    }

    private func waitForBridge(attempt: Int) {
        bridge.health { [weak self] ready in
            guard let self else { return }
            if ready {
                self.finishStart(.success(()))
                return
            }
            guard attempt < 80 else {
                self.finishStart(.failure(WebTorrentBackendError.startupTimedOut))
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
                self.waitForBridge(attempt: attempt + 1)
            }
        }
    }

    private func finishStart(_ result: Result<Void, Error>) {
        lock.lock()
        let completions = pendingStarts
        pendingStarts.removeAll()
        switch result {
        case .success:
            startState = .ready
        case .failure(let error):
            startState = .failed(error)
        }
        lock.unlock()

        DispatchQueue.main.async {
            completions.forEach { $0(result) }
        }
    }

    private func resolveTorrentSource(for torrentEntity: Torrents,
                                      completion: @escaping (Result<Any, Error>) -> Void) {
        let link = Self.clean(torrentEntity.torrentDownloadURL)
        let hash = Self.clean(torrentEntity.torrentHashString)

        // Some extensions put the playable magnet in `hash` and a web/download
        // page in `link`. Prefer a real magnet from either field before trying
        // any HTTP .torrent fetch path.
        if let magnet = Self.magnet(from: link) ?? Self.magnet(from: hash) {
            completion(.success(magnet))
            return
        }

        if let link {
            if Self.isHTTPURL(link) {
                fetchTorrentFile(from: link) { result in
                    switch result {
                    case .success(let data):
                        completion(.success([
                            "kind": "torrentFileBase64",
                            "data": data.base64EncodedString(),
                            "source": link,
                        ]))
                    case .failure(let error):
                        print("WebTorrentBackend: Swift .torrent fetch failed, falling back to URL string: \(error.localizedDescription)")
                        completion(.success(link))
                    }
                }
            } else {
                completion(.success(link))
            }
            return
        }

        if let fallback = Self.torrentIdentifier(fromHash: hash) {
            completion(.success(fallback))
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

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error))
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
}
