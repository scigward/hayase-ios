//
//  TorrentBackendManager.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

final class TorrentBackendManager {
    static let shared = TorrentBackendManager()

    private let webTorrentBackend = WebTorrentBackend.shared

    private init() {}

    func applyCurrentSettings() {
        webTorrentBackend.applySettings()
    }

    func playWebTorrent(torrentEntity: Torrents,
                        mediaID: Int,
                        episode: Int,
                        completion: @escaping (Result<[WebTorrentFile], Error>) -> Void) -> WebTorrentPlayRequest {
        webTorrentBackend.playTorrent(torrentEntity: torrentEntity,
                                      mediaID: mediaID,
                                      episode: episode,
                                      completion: completion)
    }

    func webTorrentCachedTorrents(completion: @escaping (Result<[String], Error>) -> Void) {
        webTorrentBackend.cachedTorrents(completion: completion)
    }

    /// interface's `native.checkIncomingConnections(port)`
    func webTorrentCheckIncomingConnections(port: Int, completion: @escaping (Result<Bool, Error>) -> Void) {
        webTorrentBackend.checkIncomingConnections(port: port, completion: completion)
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

    func rescanWebTorrents(hashes: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        webTorrentBackend.rescanTorrents(hashes: hashes, completion: completion)
    }

    func deleteWebTorrents(hashes: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        webTorrentBackend.deleteTorrents(hashes: hashes, completion: completion)
    }

    func createWebTorrentNZB(hash: String, url: String, completion: @escaping (Result<Void, Error>) -> Void) {
        webTorrentBackend.createNZB(hash: hash, url: url, completion: completion)
    }

    func createWebTorrentHTTPWebSeed(hash: String, seed: WebSeedResult, completion: @escaping (Result<Void, Error>) -> Void) {
        webTorrentBackend.createHTTPWebSeed(hash: hash, seed: seed, completion: completion)
    }

    // MARK: - Casting (Chromecast/DLNA — WebTorrent backend only, same as interface)

    func webTorrentListDisplays(completion: @escaping (Result<[WebTorrentDisplay], Error>) -> Void) {
        webTorrentBackend.listDisplays(completion: completion)
    }

    func webTorrentPlayDisplay(host: String,
                               hash: String,
                               id: Int,
                               media: [String: Any],
                               completion: @escaping (Result<Void, Error>) -> Void) {
        webTorrentBackend.playDisplay(host: host, hash: hash, id: id, media: media, completion: completion)
    }

    func webTorrentCloseDisplay(host: String, completion: @escaping (Result<Void, Error>) -> Void) {
        webTorrentBackend.closeDisplay(host: host, completion: completion)
    }
}
