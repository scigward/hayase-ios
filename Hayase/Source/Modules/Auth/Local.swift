//
//  Local.swift
//  Hayase
//
//  Local offline-first media tracking provider.
//  Mirrors: src/lib/modules/auth/local.ts
//

import Foundation

struct LocalMediaTrackingEntry: Codable {
    let mediaID: Int
    var status: String?
    var progress: Int
    var score: Int
    var repeatCount: Int
    var customLists: [String]
    var updatedAt: Date

    var animeEntry: AnimeItem.MediaListEntry {
        AnimeItem.MediaListEntry(
            listID: mediaID,
            status: status,
            progress: progress,
            score: score,
            repeatCount: repeatCount,
            customLists: customLists)
    }
}

final class LocalTracking {
    static let shared = LocalTracking()
    static let didChange = Notification.Name("LocalTrackingDidChange")

    private let udKey = "hayase_localTracking"
    private let entriesLock = NSLock()
    private init() {}

    func entry(mediaID: Int,
               status: String? = nil,
               progress: Int? = nil,
               score: Int? = nil,
               repeatCount: Int? = nil,
               lists: [String]? = nil) -> AnimeItem.MediaListEntry {
        entriesLock.lock()

        var entries = allEntries()
        var entry = entries[mediaID] ?? LocalMediaTrackingEntry(
            mediaID: mediaID,
            status: nil,
            progress: 0,
            score: 0,
            repeatCount: 0,
            customLists: [],
            updatedAt: Date())

        let old = entry
        if let status { entry.status = status }
        if let progress { entry.progress = max(entry.progress, progress) }
        if let score { entry.score = score }
        if let repeatCount { entry.repeatCount = repeatCount }
        if let lists { entry.customLists = lists }
        if entry.status == nil { entry.status = "CURRENT" }
        let changed = old.status != entry.status ||
            old.progress != entry.progress ||
            old.score != entry.score ||
            old.repeatCount != entry.repeatCount ||
            old.customLists != entry.customLists
        if changed {
            entry.updatedAt = Date()
            entries[mediaID] = entry
            save(entries)
        }
        let result = entry.animeEntry
        entriesLock.unlock()

        if changed { notify() }
        return result
    }

    func delete(mediaID: Int) -> Bool {
        entriesLock.lock()
        var entries = allEntries()
        let removed = entries.removeValue(forKey: mediaID) != nil
        if removed {
            save(entries)
        }
        entriesLock.unlock()

        if removed { notify() }
        return removed
    }

    func watch(anilistID: Int, episodeProgress: Int, totalEpisodes: Int? = nil) {
        guard anilistID > 0, episodeProgress > 0 else { return }
        let total = totalEpisodes ?? Int.max
        let status = episodeProgress >= total ? "COMPLETED" : "CURRENT"
        _ = entry(mediaID: anilistID, status: status, progress: episodeProgress)
    }

    func setInitialState(anilistID: Int, episode: Int) {
        guard anilistID > 0, episode == 1 else { return }
        let current = entry(for: anilistID)
        if current == nil || current?.status == "PLANNING" || current?.status == "PAUSED" {
            _ = entry(mediaID: anilistID, status: "CURRENT", progress: current?.progress ?? 0)
        }
    }

    func entry(for mediaID: Int) -> AnimeItem.MediaListEntry? {
        entriesLock.lock()
        defer { entriesLock.unlock() }
        return allEntries()[mediaID]?.animeEntry
    }

    func progress(for mediaID: Int) -> Int? {
        entry(for: mediaID)?.progress
    }

    private func allEntries() -> [Int: LocalMediaTrackingEntry] {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let decoded = try? JSONDecoder().decode([Int: LocalMediaTrackingEntry].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func save(_ entries: [Int: LocalMediaTrackingEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: udKey)
    }

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }
}
