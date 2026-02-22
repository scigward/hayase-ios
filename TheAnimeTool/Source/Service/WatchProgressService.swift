//
//  WatchProgressService.swift
//  TheAnimeTool
//
//  Matches Hayase's watchProgress.ts: persists episode currentTime + duration per
//  video file. Lets VideoPlayerController restore position on re-open and lets
//  BrowseAnimeViewController build the "Continue Watching" home section.
//

import Foundation

// MARK: - WatchProgress

struct WatchProgress {
    let anilistID: Int       // AniList media ID (0 if unknown)
    let episodeNumber: Int   // episode index (1-based; file index + 1 if no ani.zip data)
    let currentTime: Double  // seconds played
    let duration: Double     // total duration in seconds
    let updatedAt: Date

    /// 0.0 … 1.0 — how much of the episode has been watched
    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    /// Matches Hayase: < 5% = not started, ≥ 95% = completed → hide progress bar
    var isInProgress: Bool { fraction >= 0.05 && fraction < 0.95 }
    var isCompleted:  Bool { fraction >= 0.95 }
}

// MARK: - WatchProgressService

/// Singleton that stores watch progress in UserDefaults.
/// Key space: "nyais_watchProgress" → [videoPath: {currentTime, duration, episode, anilistID, updatedAt}]
final class WatchProgressService {
    static let shared = WatchProgressService()
    private init() {}

    private let udKey = "nyais_watchProgress"

    // MARK: Read

    func getProgress(videoPath: String) -> WatchProgress? {
        guard let all = UserDefaults.standard.dictionary(forKey: udKey) as? [String: [String: Any]],
              let d = all[videoPath] else { return nil }
        return decode(d)
    }

    /// Returns the most-recent in-progress entry for a given (anilistID, episodeNumber) pair.
    func getProgress(anilistID: Int, episode: Int) -> WatchProgress? {
        guard anilistID > 0 else { return nil }
        return allProgress().values
            .filter { $0.anilistID == anilistID && $0.episodeNumber == episode }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    // MARK: Write

    func setProgress(videoPath: String,
                     anilistID: Int,
                     episode: Int,
                     currentTime: Double,
                     duration: Double) {
        guard !videoPath.isEmpty, duration > 0 else { return }
        var dict = (UserDefaults.standard.dictionary(forKey: udKey) as? [String: [String: Any]]) ?? [:]
        dict[videoPath] = [
            "currentTime": currentTime,
            "duration":    duration,
            "episode":     episode,
            "anilistID":   anilistID,
            "updatedAt":   Date().timeIntervalSince1970,
        ]
        UserDefaults.standard.set(dict, forKey: udKey)
    }

    // MARK: Continue Watching

    /// Unique AniList IDs for which the user has an in-progress episode,
    /// sorted by most-recently-watched first. Matches Hayase's continueIDs.
    func continueWatchingAnilistIDs() -> [Int] {
        // Matches Hayase home/+page.svelte: continueIDs.slice(0, 50) — we cap at 20 for UI density
        let maxItems = 20
        let inProgress = allProgress().values.filter { $0.isInProgress && $0.anilistID > 0 }
        let sorted = inProgress.sorted { $0.updatedAt > $1.updatedAt }
        var seen  = Set<Int>()
        var result: [Int] = []
        for p in sorted {
            if seen.insert(p.anilistID).inserted { result.append(p.anilistID) }
        }
        return Array(result.prefix(maxItems))
    }

    // MARK: Private helpers

    private func allProgress() -> [String: WatchProgress] {
        guard let all = UserDefaults.standard.dictionary(forKey: udKey) as? [String: [String: Any]] else { return [:] }
        var result: [String: WatchProgress] = [:]
        for (path, d) in all {
            if let p = decode(d) { result[path] = p }
        }
        return result
    }

    private func decode(_ d: [String: Any]) -> WatchProgress? {
        guard let ct  = d["currentTime"] as? Double,
              let dur = d["duration"]    as? Double,
              let ep  = d["episode"]     as? Int,
              let aid = d["anilistID"]   as? Int,
              let ts  = d["updatedAt"]   as? Double else { return nil }
        return WatchProgress(
            anilistID:     aid,
            episodeNumber: ep,
            currentTime:   ct,
            duration:      dur,
            updatedAt:     Date(timeIntervalSince1970: ts)
        )
    }
}
