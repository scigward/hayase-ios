//
//  TorrentBatchResolver.swift
//  TheAnimeTool
//
//  Resolves which file in a multi-file (batch) torrent corresponds to a
//  target episode number. Mirrors the logic in resolver.ts from the
//  scigward/interface web client, adapted for the iOS native stack.
//
//  Usage:
//      let resolver = TorrentBatchResolver()
//      if let match = resolver.resolve(files: snapshot.files, targetEpisode: 5) {
//          videoService.selectFileForStreaming(UInt(match.index))
//      }

import Foundation
import LibTorrent

/// Lightweight anime filename parser + episode matcher for torrent batches.
/// Only downloads the single episode the user selected instead of the entire batch.
struct TorrentBatchResolver {

    // MARK: - Public types

    struct ResolvedFile {
        let entry: FileEntry
        let episode: Int
    }

    // MARK: - Video / exclusion sets

    private static let videoExtensions: Set<String> = [
        "mkv", "mp4", "avi", "webm", "mov", "flv", "wmv", "m4v", "ts", "mpg", "mpeg", "ogm"
    ]

    /// Non-episode media types to exclude (OP, ED, previews, etc.)
    private static let typeExclusions: Set<String> = [
        "ED", "ENDING", "NCED", "NCOP", "OP", "OPENING", "PREVIEW", "PV",
        "MENU", "EXTRA", "BONUS", "SPECIAL", "TRAILER", "CM", "CREDITLESS"
    ]

    // MARK: - Regex patterns for episode number extraction

    /// Ordered from most specific to least specific. First match wins.
    private static let episodePatterns: [NSRegularExpression] = {
        let patterns = [
            // [Group] Title - 05 (1080p).mkv  or  Title - S01E05.mkv
            #"[_\s]-[_\s](?:S\d+E)?(\d{1,4})(?:v\d+)?(?:[_\s]|\[|\(|\.(?:mkv|mp4|avi|webm))"#,
            // Episode 05 or Ep.05 or Ep 05
            #"(?:Episode|Ep\.?)[_\s]*(\d{1,4})"#,
            // S01E05 format
            #"S\d+E(\d{1,4})"#,
            // E05 standalone
            #"(?:^|[\s_\[\(])E(\d{1,4})(?:v\d+)?(?:[\s_\]\).]|$)"#,
            // Bare number between separators: " 05 " or "_05_" or " 05."
            #"(?:^|[\s_])(\d{2,4})(?:v\d+)?(?:[\s_.]|$)"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    /// Detects non-episode content (OP, ED, NCOP, NCED, PV, etc.)
    private static let exclusionPattern: NSRegularExpression? = {
        let joined = typeExclusions.joined(separator: "|")
        return try? NSRegularExpression(
            pattern: #"(?:^|[\s_\[\(])(?:\#(joined))(?:\d*)?(?:[\s_\]\).]|$)"#,
            options: .caseInsensitive)
    }()

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

        // Parse all video files and extract episode numbers, excluding OP/ED/etc.
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
        if !sorted.isEmpty {
            let minEp = sorted.first!.episode
            let maxEp = sorted.last!.episode
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

    /// Extracts the most likely episode number from an anime filename.
    static func extractEpisodeNumber(from filename: String) -> Int? {
        // Work with the filename component only (strip directory path)
        let name = (filename as NSString).lastPathComponent

        for regex in episodePatterns {
            let range = NSRange(name.startIndex..., in: name)
            if let match = regex.firstMatch(in: name, range: range),
               match.numberOfRanges > 1,
               let captureRange = Range(match.range(at: 1), in: name) {
                let numStr = String(name[captureRange])
                if let num = Int(numStr), num > 0, num < 10000 {
                    return num
                }
            }
        }
        return nil
    }

    /// Returns true if the filename looks like an OP, ED, preview, or other non-episode content.
    static func isExcludedType(_ name: String) -> Bool {
        guard let pattern = exclusionPattern else { return false }
        let basename = (name as NSString).lastPathComponent
        let range = NSRange(basename.startIndex..., in: basename)
        return pattern.firstMatch(in: basename, range: range) != nil
    }
}
