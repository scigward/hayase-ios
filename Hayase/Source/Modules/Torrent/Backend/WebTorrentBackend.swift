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
    case startupTimedOut

    var errorDescription: String? {
        switch self {
        case .missingBridgeScript:
            return "WebTorrent bridge script is missing from the app bundle."
        case .missingTorrentIdentifier:
            return "Torrent has no magnet link, download URL, or info hash."
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
        guard let torrentID = Self.torrentIdentifier(for: torrentEntity) else {
            completion(.failure(WebTorrentBackendError.missingTorrentIdentifier))
            return
        }

        ensureStarted { [weak self] result in
            guard let self else { return }
            switch result {
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

    private static func torrentIdentifier(for torrentEntity: Torrents) -> String? {
        if let urlString = torrentEntity.torrentDownloadURL,
           !urlString.isEmpty,
           URL(string: urlString)?.scheme == "magnet" {
            return urlString
        }

        // Prefer the info-hash for WebTorrent playback when it is available.
        // Search providers often return HTTP torrent download links that work
        // in browsers but fail under Node Mobile's fetch/undici path. The
        // torrent-client adds its own tracker list, so a hash magnet is enough
        // and avoids a fragile pre-download step.
        if let hash = torrentEntity.torrentHashString, !hash.isEmpty {
            return "magnet:?xt=urn:btih:\(hash)"
        }

        if let url = torrentEntity.torrentDownloadURL, !url.isEmpty {
            return url
        }
        return nil
    }
}
