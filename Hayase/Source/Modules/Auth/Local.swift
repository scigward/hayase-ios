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
    var isFavourite: Bool
    var hasMediaListEntry: Bool
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

    init(mediaID: Int,
         isFavourite: Bool = false,
         hasMediaListEntry: Bool = true,
         status: String? = nil,
         progress: Int = 0,
         score: Int = 0,
         repeatCount: Int = 0,
         customLists: [String] = [],
         updatedAt: Date = Date()) {
        self.mediaID = mediaID
        self.isFavourite = isFavourite
        self.hasMediaListEntry = hasMediaListEntry
        self.status = status
        self.progress = progress
        self.score = score
        self.repeatCount = repeatCount
        self.customLists = customLists
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case mediaID
        case isFavourite
        case hasMediaListEntry
        case status
        case progress
        case score
        case repeatCount
        case customLists
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaID = try container.decode(Int.self, forKey: .mediaID)
        isFavourite = try container.decodeIfPresent(Bool.self, forKey: .isFavourite) ?? false
        hasMediaListEntry = try container.decodeIfPresent(Bool.self, forKey: .hasMediaListEntry) ?? true
        status = try container.decodeIfPresent(String.self, forKey: .status)
        progress = try container.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        score = try container.decodeIfPresent(Int.self, forKey: .score) ?? 0
        repeatCount = try container.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 0
        customLists = try container.decodeIfPresent([String].self, forKey: .customLists) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

final class LocalTracking {
    static let shared = LocalTracking()
    static let didChange = Notification.Name("LocalTrackingDidChange")

    private let udKey = "hayase_localTracking"
    private let entriesLock = NSLock()
    /// `entries` is a Map that was filled from an object: its keys come back in ascending order, and
    /// whatever is added after that goes at the end.
    private var order: [Int] = []

    private init() {
        order = allEntries().keys.sorted()
    }

    func entry(mediaID: Int,
               status: String? = nil,
               progress: Int? = nil,
               score: Int? = nil,
               repeatCount: Int? = nil,
               lists: [String]? = nil) -> AnimeItem.MediaListEntry {
        entriesLock.lock()

        var entries = allEntries()
        var entry = entries[mediaID] ?? LocalMediaTrackingEntry(mediaID: mediaID)

        let old = entry
        entry.hasMediaListEntry = true
        if let status { entry.status = status }
        if let progress { entry.progress = max(0, progress) }
        if let score { entry.score = score }
        if let repeatCount { entry.repeatCount = repeatCount }
        if let lists { entry.customLists = lists }
        if entry.status == nil { entry.status = "CURRENT" }
        let changed = old.hasMediaListEntry != entry.hasMediaListEntry ||
            old.status != entry.status ||
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
        var entry = entries[mediaID] ?? LocalMediaTrackingEntry(mediaID: mediaID)
        let changed = entry.hasMediaListEntry
        if changed {
            entry.hasMediaListEntry = false
            entry.status = nil
            entry.progress = 0
            entry.score = 0
            entry.repeatCount = 0
            entry.customLists = []
            entry.updatedAt = Date()
            entries[mediaID] = entry
            save(entries)
        }
        entriesLock.unlock()

        if changed { notify() }
        return changed
    }

    func toggleFavourite(mediaID: Int) -> Bool {
        entriesLock.lock()
        var entries = allEntries()
        var entry = entries[mediaID] ?? LocalMediaTrackingEntry(mediaID: mediaID)
        entry.isFavourite.toggle()
        entry.updatedAt = Date()
        entries[mediaID] = entry
        save(entries)
        let isFavourite = entry.isFavourite
        entriesLock.unlock()

        notify()
        return isFavourite
    }

    func isFavourite(mediaID: Int) -> Bool {
        entriesLock.lock()
        defer { entriesLock.unlock() }
        return allEntries()[mediaID]?.isFavourite ?? false
    }

    func entry(for mediaID: Int) -> AnimeItem.MediaListEntry? {
        entriesLock.lock()
        defer { entriesLock.unlock() }
        guard let entry = allEntries()[mediaID],
              entry.hasMediaListEntry else { return nil }
        return entry.animeEntry
    }

    func progress(for mediaID: Int) -> Int? {
        entry(for: mediaID)?.progress
    }

    func planningIDs() -> [Int] {
        mediaIDs(withStatuses: ["PLANNING"])
    }

    func continueIDs() -> [Int] {
        mediaIDs(withStatuses: ["CURRENT", "REPEATING"])
    }

    func scheduleMediaIDs() -> [Int] {
        mediaIDs(withStatuses: ["CURRENT", "PLANNING", "COMPLETED", "PAUSED", "REPEATING"])
    }

    private func mediaIDs(withStatuses statuses: Set<String>) -> [Int] {
        entriesLock.lock()
        defer { entriesLock.unlock() }
        let entries = allEntries()
        return order.compactMap { id -> Int? in
            guard let entry = entries[id], entry.hasMediaListEntry, let status = entry.status,
                  statuses.contains(status) else { return nil }
            return id
        }
    }

    private func allEntries() -> [Int: LocalMediaTrackingEntry] {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let decoded = try? JSONDecoder().decode([Int: LocalMediaTrackingEntry].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func save(_ entries: [Int: LocalMediaTrackingEntry]) {
        for id in entries.keys.sorted() where !order.contains(id) { order.append(id) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: udKey)
    }

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }
}
