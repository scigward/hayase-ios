//
//  TorrentBackendManager.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation
import LibTorrent

final class TorrentBackendManager {
    static let shared = TorrentBackendManager()

    private let nativeBackend = NativeTorrentBackend.shared
    private let webTorrentBackend = WebTorrentBackend.shared

    private init() {}

    var currentKind: TorrentBackendKind {
        TorrentBackendKind.current()
    }

    func applyCurrentSettings() {
        switch currentKind {
        case .native:
            nativeBackend.applySettings()
        case .webtorrent:
            webTorrentBackend.applySettings()
        }
    }

    func backendSelectionDidChange() {
        applyCurrentSettings()
    }

    func updateNativeTorrentEntityInController(_ torrentEntity: Torrents,
                                               completion: @escaping (Result<TorrentHandle, Error>) -> Void) {
        nativeBackend.updateTorrentEntityInController(torrentEntity, completion: completion)
    }

    func playWebTorrent(torrentEntity: Torrents,
                        mediaID: Int,
                        episode: Int,
                        completion: @escaping (Result<[WebTorrentFile], Error>) -> Void) {
        webTorrentBackend.playTorrent(torrentEntity: torrentEntity,
                                      mediaID: mediaID,
                                      episode: episode,
                                      completion: completion)
    }

    func webTorrentStatus(completion: @escaping (Result<WebTorrentBridgeStatus, Error>) -> Void) {
        webTorrentBackend.status(completion: completion)
    }
}
