//
//  WebTorrentDownloaded.swift
//  Hayase
//

// Mirrors: interface/src/lib/modules/torrent/client.ts (`server.downloaded`)

import Foundation

/// The hashes of the torrents the WebTorrent backend has cached. Search ranks them first and
/// marks them, and the set is kept as interface keeps it: read from the backend before search
/// needs it, added to when a torrent is played and replaced whenever the library is read.
/// Main thread only.
final class WebTorrentDownloaded {
    static let shared = WebTorrentDownloaded()
    static let didChange = Notification.Name("HayaseWebTorrentDownloadedDidChange")

    private(set) var hashes = Set<String>()

    private init() {}

    func contains(_ hash: String) -> Bool {
        hashes.contains(hash.lowercased())
    }

    /// `native.cachedTorrents()`
    func refresh() {
        TorrentBackendManager.shared.webTorrentCachedTorrents { [weak self] result in
            guard case .success(let hashes) = result else { return }
            DispatchQueue.main.async { self?.replace(with: hashes) }
        }
    }

    func replace(with newHashes: [String]) {
        let normalized = Set(newHashes.map { $0.lowercased() })
        guard normalized != hashes else { return }
        hashes = normalized
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func add(_ hash: String?) {
        guard let hash = hash?.lowercased(), !hash.isEmpty, hashes.insert(hash).inserted else { return }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
