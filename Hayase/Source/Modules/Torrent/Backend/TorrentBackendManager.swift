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

    func webTorrentLibrary(completion: @escaping (Result<[WebTorrentLibraryEntry], Error>) -> Void) {
        webTorrentBackend.library(completion: completion)
    }

    func webTorrentInfo(hash: String, completion: @escaping (Result<WebTorrentTorrentInfo, Error>) -> Void) {
        webTorrentBackend.torrentInfo(hash: hash, completion: completion)
    }

    func webTorrentPeerInfo(hash: String, completion: @escaping (Result<[WebTorrentPeerInfo], Error>) -> Void) {
        webTorrentBackend.peerInfo(hash: hash, completion: completion)
    }

    func webTorrentFileInfo(hash: String, completion: @escaping (Result<[WebTorrentFileInfo], Error>) -> Void) {
        webTorrentBackend.fileInfo(hash: hash, completion: completion)
    }

    func webTorrentProtocolStatus(hash: String, completion: @escaping (Result<WebTorrentProtocolStatus, Error>) -> Void) {
        webTorrentBackend.protocolStatus(hash: hash, completion: completion)
    }

    func webTorrentTrackers(hash: String, completion: @escaping (Result<[String: WebTorrentTrackerInfo], Error>) -> Void) {
        webTorrentBackend.trackers(hash: hash, completion: completion)
    }

    func deleteWebTorrents(hashes: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        webTorrentBackend.deleteTorrents(hashes: hashes, completion: completion)
    }
}
