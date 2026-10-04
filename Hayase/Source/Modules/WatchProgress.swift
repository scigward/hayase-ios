//
//  WatchProgress.swift
//  Hayase
//
//  Mirrors: src/lib/modules/watchProgress.ts: one record for each media, `watchProgress[mediaId] = { episode,
//  currentTime, safeduration }`, whichever episode of it was played last. The player writes it every 10 seconds
//  while it plays (`saveAnimeProgress`) and reads it when the file has loaded (`loadAnimeProgress`); the episode
//  list shows the bar of `liveAnimeProgress` on that episode.
//
//  Before this model the app kept a record for each video path, under `nyais_watchProgress`. Those are carried
//  over once: the one that was played last of each media becomes its record.
//

import Foundation

// MARK: - WatchProgress

/// `WatchProgress`
struct WatchProgress: Equatable {
    let episode: Int
    let currentTime: Double
    let safeduration: Double
}

// MARK: - WatchProgressService

final class WatchProgressService {
    static let shared = WatchProgressService()
    /// Every write of the store, which `liveAnimeProgress` is derived from
    static let didChange = Notification.Name("WatchProgressDidChange")

    private let key = "watchProgress"
    private let legacyKey = "nyais_watchProgress"

    private init() {
        migrateLegacyProgress()
    }

    // MARK: Read

    /// `getAnimeProgress`
    func getAnimeProgress(mediaID: Int) -> WatchProgress? {
        guard let entry = store()[String(mediaID)] else { return nil }
        return decode(entry)
    }

    /// `liveAnimeProgress`: `Math.ceil(currentTime / safeduration * 100)` and the episode, for the episode list
    func liveAnimeProgress(mediaID: Int) -> (progress: Int, episode: Int)? {
        guard mediaID != 0, let entry = getAnimeProgress(mediaID: mediaID) else { return nil }
        let percent = (entry.currentTime / entry.safeduration * 100).rounded(.up)
        // a width that is not a number is no width: the bar is as wide as its row
        return (percent.isFinite ? Int(percent) : 100, entry.episode)
    }

    // MARK: Write

    /// `setAnimeProgress`
    func setAnimeProgress(mediaID: Int, _ progress: WatchProgress) {
        var data = store()
        data[String(mediaID)] = [
            "episode": progress.episode,
            "currentTime": progress.currentTime,
            "safeduration": progress.safeduration,
        ]
        UserDefaults.standard.set(data, forKey: key)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    // MARK: Private

    private func store() -> [String: [String: Any]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Any]] ?? [:]
    }

    private func decode(_ entry: [String: Any]) -> WatchProgress? {
        guard let episode = entry["episode"] as? Int,
              let currentTime = entry["currentTime"] as? Double,
              let safeduration = entry["safeduration"] as? Double else { return nil }
        return WatchProgress(episode: episode, currentTime: currentTime, safeduration: safeduration)
    }

    /// The records of video paths of the earlier model: for each media the one that was played last
    private func migrateLegacyProgress() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.dictionary(forKey: legacyKey) as? [String: [String: Any]] else { return }
        var data = store()
        var newest: [Int: Double] = [:]
        for entry in legacy.values {
            guard let mediaID = entry["anilistID"] as? Int, mediaID > 0,
                  let episode = entry["episode"] as? Int,
                  let currentTime = entry["currentTime"] as? Double,
                  let duration = entry["duration"] as? Double,
                  let updatedAt = entry["updatedAt"] as? Double else { continue }
            // a record of the new model is not replaced; of the old ones the latest is taken
            let isNewer = newest[mediaID].map { updatedAt > $0 } ?? (data[String(mediaID)] == nil)
            guard isNewer else { continue }
            newest[mediaID] = updatedAt
            data[String(mediaID)] = ["episode": episode, "currentTime": currentTime, "safeduration": duration]
        }
        defaults.set(data, forKey: key)
        defaults.removeObject(forKey: legacyKey)
    }
}
