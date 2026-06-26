//
//  NativeTorrentBackend.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation
import LibTorrent

final class NativeTorrentBackend {
    static let shared = NativeTorrentBackend()

    private init() {}

    func applySettings() {
        TorrentService.sharedTorrentService.applyUserSettings()
    }

    func updateTorrentEntityInController(_ torrentEntity: Torrents,
                                         completion: @escaping (Result<TorrentHandle, Error>) -> Void) {
        TorrentService.sharedTorrentService.UpdateTorrentEntityInController(torrentEntity, completion: completion)
    }
}
