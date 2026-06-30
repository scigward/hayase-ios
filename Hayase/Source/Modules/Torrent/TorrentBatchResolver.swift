//
//  TorrentBatchResolver.swift
//  Hayase
//
//  Resolves which file in a multi-file torrent corresponds to a target
//  episode. The async path mirrors interface/src/lib/components/ui/player/
//  resolver.ts: parse with Anitomy, resolve parsed anime titles through
//  AniList, filter back to the requested media, then select the requested
//  episode.
//

import Foundation
import LibTorrent

/// Anime filename parser + episode matcher for torrent batches.
/// Only downloads the single episode the user selected instead of the entire batch.
struct TorrentBatchResolver {

    // MARK: - Public types

    struct ParsedFilename {
        let animeTitle: String
        let animeSeason: Int?
        let animeYear: Int?
        let animeTypes: [String]
        let episodeNumbers: [Int]
    }

    struct ResolvedFile {
        struct Metadata {
            let episode: Int
            let episodeEnd: Int?
            let media: AnimeItem?
            let failed: Bool
            let parsedFilename: ParsedFilename?
        }

        let entry: FileEntry
        let metadata: Metadata

        var episode: Int { metadata.episode }
        var episodeEnd: Int? { metadata.episodeEnd }
        var media: AnimeItem? { metadata.media }
        var failed: Bool { metadata.failed }
        var parsedFilename: ParsedFilename? { metadata.parsedFilename }

        init(entry: FileEntry,
             episode: Int,
             episodeEnd: Int? = nil,
             media: AnimeItem? = nil,
             failed: Bool = false,
             parsedFilename: ParsedFilename? = nil) {
            self.entry = entry
            self.metadata = Metadata(episode: episode,
                                     episodeEnd: episodeEnd,
                                     media: media,
                                     failed: failed,
                                     parsedFilename: parsedFilename)
        }
    }

    struct BatchResolution {
        let target: ResolvedFile?
        let targetAnimeFiles: [ResolvedFile]
        let otherFiles: [FileEntry]
        let resolvedFiles: [ResolvedFile]
    }

    typealias ResolveResult = BatchResolution

    // MARK: - Private types

    private struct ParsedFile {
        let entry: FileEntry
        let animeTitle: String
        let animeSeason: Int?
        let animeYear: Int?
        let animeTypes: [String]
        let episodeNumbers: [Int]

        var filename: ParsedFilename {
            ParsedFilename(animeTitle: animeTitle,
                           animeSeason: animeSeason,
                           animeYear: animeYear,
                           animeTypes: animeTypes,
                           episodeNumbers: episodeNumbers)
        }
    }

    private struct ResolvedCandidate {
        let entry: FileEntry
        let episode: Int
        let episodeEnd: Int?
        let media: AnimeItem?
        let failed: Bool
        let parseObject: ParsedFile?

        var publicFile: ResolvedFile {
            ResolvedFile(entry: entry,
                         episode: episode,
                         episodeEnd: episodeEnd,
                         media: media,
                         failed: failed,
                         parsedFilename: parseObject?.filename)
        }
    }

    private struct SeasonResolveResult {
        let media: AnimeItem
        let episode: Int
        let offset: Int
        let increment: Bool
        let rootMedia: AnimeItem
        let failed: Bool
    }

    // MARK: - Video / exclusion sets

    // Keep this list in lockstep with interface/src/lib/utils.ts videoExtensions.
    private static let videoExtensions: Set<String> = [
        "3g2", "3gp", "asf", "avi", "dv", "flv", "gxf", "m2ts", "m4a", "m4b",
        "m4p", "m4r", "m4v", "mkv", "mov", "mp4", "mpd", "mpeg", "mpg", "mxf",
        "nut", "ogm", "ogv", "swf", "ts", "vob", "webm", "wmv", "wtv"
    ]

    /// Non-episode media types to exclude (OP, ED, previews, etc.).
    private static let typeExclusions: Set<String> = [
        "ED", "ENDING", "NCED", "NCOP", "OP", "OPENING", "PREVIEW", "PV"
    ]

    // MARK: - Public API

    /// Resolves the file in `files` that best matches `targetEpisode`.
    ///
    /// This method is intentionally synchronous and remains the fallback for
    /// flows that do not have an AniList media object yet.
    func resolve(files: [FileEntry], targetEpisode: Int) -> ResolvedFile? {
        let videoFiles = files.filter { Self.isVideoFile($0.name) }
        guard !videoFiles.isEmpty else { return nil }

        if videoFiles.count == 1 {
            let ep = Self.extractEpisodeNumber(from: videoFiles[0].name) ?? targetEpisode
            return ResolvedFile(entry: videoFiles[0], episode: ep)
        }

        var parsed: [ResolvedFile] = []
        for entry in videoFiles {
            guard !Self.isExcludedType(entry.name) else { continue }
            if let ep = Self.extractEpisodeNumber(from: entry.name) {
                parsed.append(ResolvedFile(entry: entry, episode: ep))
            }
        }

        if let match = parsed.first(where: { $0.episode == targetEpisode }) {
            return match
        }

        let sorted = parsed.sorted { $0.episode < $1.episode }
        if let first = sorted.first, let last = sorted.last {
            let minEp = first.episode
            let maxEp = last.episode
            let batchSize = sorted.count

            if targetEpisode >= 1 && targetEpisode <= batchSize && minEp > batchSize {
                let offsetIndex = targetEpisode - 1
                if offsetIndex < sorted.count {
                    return sorted[offsetIndex]
                }
            }

            if targetEpisode >= minEp && targetEpisode <= maxEp {
                return sorted.min(by: { abs($0.episode - targetEpisode) < abs($1.episode - targetEpisode) })
            }
        }

        if parsed.isEmpty && targetEpisode >= 1 && targetEpisode <= videoFiles.count {
            let sortedByName = videoFiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let idx = targetEpisode - 1
            if idx < sortedByName.count {
                return ResolvedFile(entry: sortedByName[idx], episode: targetEpisode)
            }
        }

        return nil
    }

    /// AniList-backed resolver that mirrors the web interface resolver.
    func resolve(files: [FileEntry], targetEpisode: Int, targetMedia: AnimeItem, completion: @escaping (ResolveResult) -> Void) {
        let videoFiles = files.filter { Self.isVideoFile($0.name) }
        let otherFiles = files.filter { !Self.isVideoFile($0.name) }
        guard !videoFiles.isEmpty else {
            completion(ResolveResult(target: nil, targetAnimeFiles: [], otherFiles: otherFiles, resolvedFiles: []))
            return
        }

        let parsedFiles = videoFiles
            .compactMap { Self.parseFile($0) }
            .filter { parsed in
                !Self.typeExclusions.contains(parsed.animeTypes.first?.uppercased() ?? "")
            }

        if parsedFiles.count == 1, let parsed = parsedFiles.first {
            let candidate = Self.toCandidate(parsed.entry, parseObject: parsed, media: targetMedia, episode: targetEpisode, failed: false)
            completion(ResolveResult(target: candidate.publicFile,
                                     targetAnimeFiles: [candidate.publicFile],
                                     otherFiles: otherFiles,
                                     resolvedFiles: [candidate.publicFile]))
            return
        }

        resolveFileAnime(parsedFiles) { resolvedCandidates in
            var candidates = resolvedCandidates
            var targetAnimeFiles = candidates.filter { $0.media?.id == targetMedia.id }

            if targetAnimeFiles.isEmpty {
                if !candidates.isEmpty {
                    let commonTitle = Self.highestOccurence(candidates) { candidate in
                        candidate.parseObject?.animeTitle ?? ""
                    }
                    targetAnimeFiles = candidates.filter { ($0.parseObject?.animeTitle ?? "") == commonTitle }
                } else {
                    candidates = videoFiles.map {
                        Self.toCandidate($0, parseObject: Self.parseFile($0), media: targetMedia, episode: targetEpisode, failed: false)
                    }
                    targetAnimeFiles = candidates
                }
            }

            targetAnimeFiles.sort { lhs, rhs in
                let leftSeason = lhs.parseObject?.animeSeason ?? 1
                let rightSeason = rhs.parseObject?.animeSeason ?? 1
                if leftSeason != rightSeason {
                    return leftSeason > rightSeason
                }
                return lhs.episode < rhs.episode
            }

            let target = targetAnimeFiles.first { $0.episode == targetEpisode }
                ?? targetAnimeFiles.first { $0.episode == 1 }
                ?? targetAnimeFiles.first
                ?? candidates.first

            completion(ResolveResult(target: target?.publicFile,
                                     targetAnimeFiles: targetAnimeFiles.map { $0.publicFile },
                                     otherFiles: otherFiles,
                                     resolvedFiles: candidates.map { $0.publicFile }))
        }
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

    // MARK: - Interface resolver parity

    private func resolveFileAnime(_ parsedFiles: [ParsedFile], completion: @escaping ([ResolvedCandidate]) -> Void) {
        guard !parsedFiles.isEmpty else {
            completion([])
            return
        }

        let keys = Array(Set(parsedFiles.map { Self.cacheKey(for: $0) }.filter { !$0.isEmpty }))
        var titleIDs: [String: Int] = [:]

        let titleGroups: [(key: String, titles: [String], year: Int?)] = keys.compactMap { key in
            guard let parsed = parsedFiles.first(where: { Self.cacheKey(for: $0) == key }) else { return nil }
            return (key: key, titles: Self.alternativeTitles(for: parsed), year: parsed.animeYear)
        }

        func fetchResolvedMedia() {
            let ids = Array(Set(titleIDs.values))
            var mediaByID: [Int: AnimeItem] = [:]

            func fetchID(at index: Int) {
                guard index < ids.count else {
                    buildCandidates(mediaByID: mediaByID)
                    return
                }

                let id = ids[index]
                AniListClient.shared.fetchResolverMediaByIdResult(id) { result in
                    switch result {
                    case .success(let item):
                        mediaByID[id] = item
                    case .failure(let error):
                        NSLog("[TorrentBatchResolver] Resolver media fetch failed: %@", error.description)
                    }
                    fetchID(at: index + 1)
                }
            }

            fetchID(at: 0)
        }

        func buildCandidates(mediaByID: [Int: AnimeItem]) {
            var candidates: [ResolvedCandidate] = []

            func build(at index: Int) {
                guard index < parsedFiles.count else {
                    completion(candidates)
                    return
                }

                let parsed = parsedFiles[index]
                let key = Self.cacheKey(for: parsed)
                guard let id = titleIDs[key], let media = mediaByID[id] else {
                    build(at: index + 1)
                    return
                }

                Self.resolveEpisode(parseObject: parsed, media: media) { resolvedMedia, episode, episodeEnd, failed in
                    candidates.append(Self.toCandidate(parsed.entry,
                                                       parseObject: parsed,
                                                       media: resolvedMedia,
                                                       episode: episode,
                                                       episodeEnd: episodeEnd,
                                                       failed: failed))
                    build(at: index + 1)
                }
            }

            build(at: 0)
        }

        AniListClient.shared.searchResolverAnimeIDsResult(titleGroups: titleGroups) { result in
            switch result {
            case .success(let ids):
                titleIDs = ids
            case .failure(let error):
                NSLog("[TorrentBatchResolver] AniList resolver search failed: %@", error.description)
                titleIDs = [:]
            }
            fetchResolvedMedia()
        }
    }

    private static func resolveEpisode(parseObject: ParsedFile,
                                       media: AnimeItem,
                                       completion: @escaping (AnimeItem, Int, Int?, Bool) -> Void) {
        let numbers = parseObject.episodeNumbers
        let firstEpisode = numbers.first ?? 0
        let maxEpisode = media.episodes
        let format = media.format?.uppercased()
        let shouldResolve = format != "MOVIE" || (maxEpisode != nil && firstEpisode > 0)

        guard shouldResolve, firstEpisode > 0 else {
            completion(media, firstEpisode, nil, false)
            return
        }

        if numbers.count > 1 {
            let secondEpisode = numbers[1]
            if firstEpisode == 1 {
                completion(media, firstEpisode, secondEpisode, false)
            } else if let maxEpisode, secondEpisode > maxEpisode {
                overflowRootMedia(for: media, parseObject: parseObject) { root in
                    resolveSeason(media: root ?? media,
                                  episode: secondEpisode,
                                  increment: parseObject.animeSeason == nil ? nil : true,
                                  offset: 0,
                                  rootMedia: root ?? media,
                                  force: false) { result in
                        let diff = secondEpisode - result.episode
                        completion(result.rootMedia, firstEpisode - diff, result.episode, result.failed)
                    }
                }
            } else {
                completion(media, firstEpisode, secondEpisode, false)
            }
            return
        }

        if let maxEpisode, firstEpisode > maxEpisode {
            overflowRootMedia(for: media, parseObject: parseObject) { root in
                resolveSeason(media: root ?? media,
                              episode: firstEpisode,
                              increment: parseObject.animeSeason == nil ? nil : true,
                              offset: 0,
                              rootMedia: root ?? media,
                              force: false) { result in
                    completion(result.rootMedia, result.episode, nil, result.failed)
                }
            }
        } else {
            completion(media, firstEpisode, nil, false)
        }
    }

    private static func overflowRootMedia(for media: AnimeItem,
                                          parseObject: ParsedFile,
                                          completion: @escaping (AnimeItem?) -> Void) {
        guard parseObject.animeSeason == nil else {
            completion(nil)
            return
        }
        let wantsParent = media.format?.uppercased() == "OVA" || media.format?.uppercased() == "ONA"
        findEdge(media: media, type: "PREQUEL") { prequel in
            if let prequel {
                fetchAndForceResolveRoot(edgeMedia: prequel, completion: completion)
            } else if wantsParent {
                findEdge(media: media, type: "PARENT") { parent in
                    guard let parent else {
                        completion(nil)
                        return
                    }
                    fetchAndForceResolveRoot(edgeMedia: parent, completion: completion)
                }
            } else {
                completion(nil)
            }
        }
    }

    private static func fetchAndForceResolveRoot(edgeMedia: AnimeItem, completion: @escaping (AnimeItem?) -> Void) {
        AniListClient.shared.fetchResolverMediaByIdResult(edgeMedia.id) { result in
            guard case .success(let fullMedia) = result else {
                if case .failure(let error) = result {
                    NSLog("[TorrentBatchResolver] Root media fetch failed: %@", error.description)
                }
                completion(edgeMedia)
                return
            }
            resolveSeason(media: fullMedia,
                          episode: 1,
                          increment: nil,
                          offset: 0,
                          rootMedia: fullMedia,
                          force: true) { result in
                completion(result.media)
            }
        }
    }

    private static func resolveSeason(media: AnimeItem,
                                      episode: Int,
                                      increment: Bool?,
                                      offset: Int,
                                      rootMedia: AnimeItem,
                                      force: Bool,
                                      visited: Set<Int> = [],
                                      completion: @escaping (SeasonResolveResult) -> Void) {
        guard !visited.contains(media.id) else {
            completion(SeasonResolveResult(media: media,
                                           episode: episode - offset,
                                           offset: offset,
                                           increment: increment ?? true,
                                           rootMedia: rootMedia,
                                           failed: true))
            return
        }
        let nextVisited = visited.union([media.id])
        let rootHighest = rootMedia.episodes ?? 1

        let resolveWithPrequel: (AnimeItem?) -> Void = { prequel in
            if let prequel, increment != true {
                continueSeasonResolve(edge: prequel,
                                      media: media,
                                      episode: episode,
                                      increment: false,
                                      offset: offset,
                                      rootMedia: rootMedia,
                                      rootHighest: rootHighest,
                                      force: force,
                                      visited: nextVisited,
                                      completion: completion)
                return
            }

            if increment == true || increment == nil {
                findEdge(media: media, type: "SEQUEL") { sequel in
                    guard let sequel else {
                        completion(SeasonResolveResult(media: media,
                                                       episode: episode - offset,
                                                       offset: offset,
                                                       increment: increment ?? true,
                                                       rootMedia: rootMedia,
                                                       failed: true))
                        return
                    }
                    continueSeasonResolve(edge: sequel,
                                          media: media,
                                          episode: episode,
                                          increment: true,
                                          offset: offset,
                                          rootMedia: rootMedia,
                                          rootHighest: rootHighest,
                                          force: force,
                                          visited: nextVisited,
                                          completion: completion)
                }
            } else {
                completion(SeasonResolveResult(media: media,
                                               episode: episode - offset,
                                               offset: offset,
                                               increment: false,
                                               rootMedia: rootMedia,
                                               failed: true))
            }
        }

        if increment != true {
            findEdge(media: media, type: "PREQUEL", completion: resolveWithPrequel)
        } else {
            resolveWithPrequel(nil)
        }
    }

    private static func continueSeasonResolve(edge: AnimeItem,
                                              media: AnimeItem,
                                              episode: Int,
                                              increment: Bool,
                                              offset: Int,
                                              rootMedia: AnimeItem,
                                              rootHighest: Int,
                                              force: Bool,
                                              visited: Set<Int>,
                                              completion: @escaping (SeasonResolveResult) -> Void) {
        AniListClient.shared.fetchResolverMediaByIdResult(edge.id) { result in
            if case .failure(let error) = result {
                NSLog("[TorrentBatchResolver] Season edge media fetch failed: %@", error.description)
            }
            let nextMedia = (try? result.get()) ?? edge
            let highest = nextMedia.episodes ?? 1
            let diff = episode - (highest + offset)
            let nextOffset = offset + (increment ? rootHighest : highest)
            let nextRootMedia = increment ? nextMedia : rootMedia

            if !force && diff <= rootHighest {
                completion(SeasonResolveResult(media: nextMedia,
                                               episode: episode - nextOffset,
                                               offset: nextOffset,
                                               increment: increment,
                                               rootMedia: nextRootMedia,
                                               failed: false))
                return
            }

            resolveSeason(media: nextMedia,
                          episode: episode,
                          increment: increment,
                          offset: nextOffset,
                          rootMedia: nextRootMedia,
                          force: force,
                          visited: visited,
                          completion: completion)
        }
    }

    private static func findEdge(media: AnimeItem,
                                 type: String,
                                 formats: Set<String> = ["TV", "TV_SHORT"],
                                 skip: Bool = false,
                                 completion: @escaping (AnimeItem?) -> Void) {
        if let relation = media.relations.first(where: { relation in
            relation.relationType.uppercased() == type
                && formats.contains(relation.media.format?.uppercased() ?? "")
        }) {
            completion(relation.media)
            return
        }

        if !skip && type == "SEQUEL" {
            findEdge(media: media, type: type, formats: ["TV", "TV_SHORT", "OVA"], skip: true, completion: completion)
            return
        }

        completion(nil)
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

        return parseEpisodeNumber(anitomy.get(.episodeNumber))
    }

    /// Returns true if the filename looks like an OP, ED, preview, or other non-episode content.
    static func isExcludedType(_ name: String) -> Bool {
        guard let parsed = parseFileName(name) else { return false }
        return typeExclusions.contains(parsed.animeTypes.first?.uppercased() ?? "")
    }

    private static func parseFile(_ entry: FileEntry) -> ParsedFile? {
        guard let parsed = parseFileName(entry.name) else { return nil }
        return ParsedFile(entry: entry,
                          animeTitle: parsed.animeTitle,
                          animeSeason: parsed.animeSeason,
                          animeYear: parsed.animeYear,
                          animeTypes: parsed.animeTypes,
                          episodeNumbers: parsed.episodeNumbers)
    }

    private static func parseFileName(_ filename: String) -> (animeTitle: String, animeSeason: Int?, animeYear: Int?, animeTypes: [String], episodeNumbers: [Int])? {
        let name = (filename as NSString).lastPathComponent
        let anitomy = Anitomy()
        anitomy.parse(name)

        let episodeNumbers = anitomy.getAll(.episodeNumber).compactMap { parseEpisodeNumber($0) }
        let title = anitomy.get(.animeTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        let season = parseEpisodeNumber(anitomy.get(.animeSeason))
        let year = parseEpisodeNumber(anitomy.get(.animeYear))

        return (title, season, year, anitomy.getAll(.animeType), episodeNumbers)
    }

    private static func parseEpisodeNumber(_ value: String) -> Int? {
        guard !value.isEmpty else { return nil }

        if value.contains("."),
           let dotIdx = value.firstIndex(of: ".") {
            let intPart = String(value[value.startIndex..<dotIdx])
            if let num = Int(intPart), num > 0 { return num }
        }

        let digits = value.prefix(while: { $0.isNumber })
        if let num = Int(digits), num > 0 { return num }

        if let num = Int(value), num > 0 { return num }
        return nil
    }

    private static func toCandidate(_ entry: FileEntry,
                                    parseObject: ParsedFile?,
                                    media: AnimeItem?,
                                    episode: Int,
                                    episodeEnd: Int? = nil,
                                    failed: Bool) -> ResolvedCandidate {
        ResolvedCandidate(entry: entry,
                          episode: episode,
                          episodeEnd: episodeEnd,
                          media: media,
                          failed: failed,
                          parseObject: parseObject)
    }

    private static func cacheKey(for parseObject: ParsedFile) -> String {
        var key = parseObject.animeTitle
        if let year = parseObject.animeYear {
            key += "\(year)"
        }
        if let season = parseObject.animeSeason {
            key += " S\(season)"
        }
        return normalizeSpaces(key)
    }

    private static func alternativeTitles(for parseObject: ParsedFile) -> [String] {
        let title = parseObject.animeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return [] }

        var titles = Set<String>()
        var modified = title

        if let season = parseObject.animeSeason, season > 1 {
            modified = "\(title) \(ordinal(season)) Season"
            titles.insert(modified)
            titles.insert("\(title) Season \(season)")
        } else if let seasonMatch = firstMatch(in: title, pattern: #" S(\d+)"#),
                  let season = Int(seasonMatch) {
            if season == 1 {
                modified = title.replacingOccurrences(of: #" S(\d+)"#, with: "", options: .regularExpression)
                titles.insert(modified)
            } else {
                modified = title.replacingOccurrences(of: #" S(\d+)"#, with: " \(ordinal(season)) Season", options: .regularExpression)
                titles.insert(modified)
                titles.insert(title.replacingOccurrences(of: #" S(\d+)"#, with: " Season \(season)", options: .regularExpression))
            }
        } else {
            titles.insert(title)
        }

        if let yearMatch = firstMatch(in: modified, pattern: #"\D(\d{4})$"#),
           parseObject.animeYear == nil || yearMatch == "\(parseObject.animeYear ?? 0)" {
            modified = modified.replacingOccurrences(of: #"\D(\d{4})$"#, with: "", options: .regularExpression)
            titles.insert(modified)
        }

        if modified.range(of: #"[-:]"#, options: .regularExpression) != nil {
            modified = modified.replacingOccurrences(of: #"[-:]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"[ ]{2,}"#, with: " ", options: .regularExpression)
            titles.insert(modified)
        }

        if modified.contains("(TV)") {
            modified = modified.replacingOccurrences(of: "(TV)", with: "")
            titles.insert(modified)
        }

        return Array(titles).filter { !$0.isEmpty }
    }

    private static func highestOccurence<T>(_ values: [T], key: (T) -> String) -> String {
        var counts: [String: Int] = [:]
        var best = ""
        var bestCount = 0
        for value in values {
            let current = key(value)
            counts[current, default: 0] += 1
            if counts[current, default: 0] >= bestCount {
                best = current
                bestCount = counts[current, default: 0]
            }
        }
        return best
    }

    private static func normalizeSpaces(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[swiftRange])
    }

    private static func ordinal(_ value: Int) -> String {
        let suffix: String
        let mod100 = value % 100
        if (11...13).contains(mod100) {
            suffix = "th"
        } else {
            switch value % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(value)\(suffix)"
    }
}
