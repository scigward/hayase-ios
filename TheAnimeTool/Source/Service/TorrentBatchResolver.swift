//
//  TorrentBatchResolver.swift
//  TheAnimeTool
//
//  Resolves which file in a multi-file (batch) torrent corresponds to a
//  target episode number. Uses the Anitomy parser (a faithful port of
//  erengy/anitomy) for robust anime filename parsing, handling all common
//  naming conventions including Japanese counters, fractional episodes,
//  multi-episode ranges, season+episode patterns, and more.
//
//  Usage:
//      let resolver = TorrentBatchResolver()
//      if let match = resolver.resolve(files: snapshot.files, targetEpisode: 5) {
//          videoService.selectFileForStreaming(UInt(match.index))
//      }

import Foundation
import LibTorrent

/// Anime filename parser + episode matcher for torrent batches.
/// Only downloads the single episode the user selected instead of the entire batch.
struct TorrentBatchResolver {

    // MARK: - Public types

    struct ResolvedFile {
        let entry: FileEntry
        let episode: Int
    }

    // MARK: - Video / exclusion sets

    private static let videoExtensions: Set<String> = [
        "mkv", "mp4", "avi", "webm", "mov", "flv", "wmv", "m4v", "ts", "mpg", "mpeg",
        "ogm", "3gp", "m2ts", "rmvb", "divx", "rm"
    ]

    /// Non-episode media types to exclude (OP, ED, previews, etc.)
    private static let typeExclusions: Set<String> = [
        "ED", "ENDING", "NCED", "NCOP", "OP", "OPENING", "PREVIEW", "PV",
        "MENU", "EXTRA", "BONUS", "SPECIAL", "TRAILER", "CM", "CREDITLESS"
    ]

    // MARK: - Public API

    /// Resolves the file in `files` that best matches `targetEpisode`.
    ///
    /// - Parameters:
    ///   - files: All `FileEntry` objects from the torrent snapshot.
    ///   - targetEpisode: The episode number the user wants to watch.
    /// - Returns: The `ResolvedFile` if a match is found, or `nil`.
    func resolve(files: [FileEntry], targetEpisode: Int) -> ResolvedFile? {
        let videoFiles = files.filter { Self.isVideoFile($0.name) }
        guard !videoFiles.isEmpty else { return nil }

        // If only one video file, it's the target regardless of episode number
        if videoFiles.count == 1 {
            let ep = Self.extractEpisodeNumber(from: videoFiles[0].name) ?? targetEpisode
            return ResolvedFile(entry: videoFiles[0], episode: ep)
        }

        // Parse all video files using Anitomy, excluding OP/ED/etc.
        var parsed: [ResolvedFile] = []
        for entry in videoFiles {
            guard !Self.isExcludedType(entry.name) else { continue }
            if let ep = Self.extractEpisodeNumber(from: entry.name) {
                parsed.append(ResolvedFile(entry: entry, episode: ep))
            }
        }

        // Direct episode match
        if let match = parsed.first(where: { $0.episode == targetEpisode }) {
            return match
        }

        // If parsed episodes look like absolute numbering (e.g. 13-24 for S2),
        // try matching by position in the sorted episode list.
        let sorted = parsed.sorted { $0.episode < $1.episode }
        if let first = sorted.first, let last = sorted.last {
            let minEp = first.episode
            let maxEp = last.episode
            let batchSize = sorted.count

            // Offset mapping: if episodes are 13-24 and user wants episode 1,
            // the offset-based index is targetEpisode - 1 = 0 → episode 13
            if targetEpisode >= 1 && targetEpisode <= batchSize && minEp > batchSize {
                let offsetIndex = targetEpisode - 1
                if offsetIndex < sorted.count {
                    return sorted[offsetIndex]
                }
            }

            // If the target episode falls within the detected range, find closest
            if targetEpisode >= minEp && targetEpisode <= maxEp {
                return sorted.min(by: { abs($0.episode - targetEpisode) < abs($1.episode - targetEpisode) })
            }
        }

        // Fallback: if no episodes could be parsed, try matching by file position.
        // Many batch torrents order files sequentially.
        if parsed.isEmpty && targetEpisode >= 1 && targetEpisode <= videoFiles.count {
            let sortedByName = videoFiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let idx = targetEpisode - 1
            if idx < sortedByName.count {
                return ResolvedFile(entry: sortedByName[idx], episode: targetEpisode)
            }
        }

        return nil
    }

    /// Returns all video files with their parsed episode numbers, sorted by episode.
    /// Useful for displaying a resolved file list.
    func resolveAll(files: [FileEntry]) -> [ResolvedFile] {
        let videoFiles = files.filter { Self.isVideoFile($0.name) }
        var result: [ResolvedFile] = []
        for entry in videoFiles {
            guard !Self.isExcludedType(entry.name) else { continue }
            let ep = Self.extractEpisodeNumber(from: entry.name) ?? 0
            result.append(ResolvedFile(entry: entry, episode: ep))
        }
        return result.sorted { $0.episode < $1.episode }
    }

    // MARK: - Helpers

    static func isVideoFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }

    /// Extracts the most likely episode number from an anime filename using Anitomy.
    static func extractEpisodeNumber(from filename: String) -> Int? {
        let name = (filename as NSString).lastPathComponent
        let anitomy = Anitomy()
        anitomy.parse(name)

        let episodeStr = anitomy.get(.episodeNumber)
        guard !episodeStr.isEmpty else { return nil }

        // Handle fractional episodes like "07.5" → 7
        if episodeStr.contains(".") {
            if let dotIdx = episodeStr.firstIndex(of: ".") {
                let intPart = String(episodeStr[episodeStr.startIndex..<dotIdx])
                if let num = Int(intPart), num > 0 { return num }
            }
        }

        // Handle partial episodes like "4a" → 4
        let digits = episodeStr.prefix(while: { $0.isNumber })
        if let num = Int(digits), num > 0 { return num }

        return Int(episodeStr)
    }

    /// Returns true if the filename looks like an OP, ED, preview, or other non-episode content.
    static func isExcludedType(_ name: String) -> Bool {
        let basename = (name as NSString).lastPathComponent
        let anitomy = Anitomy()
        anitomy.parse(basename)

        for typeStr in anitomy.getAll(.animeType) {
            if typeExclusions.contains(typeStr.uppercased()) {
                return true
            }
        }

        return false
    }
}
