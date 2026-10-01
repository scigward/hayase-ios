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

    enum EpisodeReference: Equatable {
        case number(Double)
        case range(String)
        case missing

        var numericValue: Double? {
            guard case .number(let value) = self, value.isFinite else { return nil }
            return value
        }

        var intValue: Int? {
            numericValue.map { Int($0.rounded(.towardZero)) }
        }

        func matches(_ episode: Int) -> Bool {
            guard let value = numericValue else { return false }
            return value == Double(episode)
        }
    }

    struct ParsedFilename {
        let animeTitle: String
        let animeSeason: Int?
        let animeYear: Int?
        let animeSeasonValues: [String]
        let animeYearValues: [String]
        let animeTypes: [String]
        let episodeNumbers: [String]
    }

    struct ResolvedFile {
        struct Metadata {
            let episode: EpisodeReference
            let episodeEnd: Int?
            let media: AnimeItem?
            let failed: Bool
            let parsedFilename: ParsedFilename?
        }

        let entry: FileEntry
        let metadata: Metadata

        var episode: Int { metadata.episode.intValue ?? 0 }
        var episodeReference: EpisodeReference { metadata.episode }
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
            self.init(entry: entry,
                      episode: .number(Double(episode)),
                      episodeEnd: episodeEnd,
                      media: media,
                      failed: failed,
                      parsedFilename: parsedFilename)
        }

        init(entry: FileEntry,
             episode: EpisodeReference,
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

    struct ResolvedItem<Item> {
        let item: Item
        let episode: EpisodeReference
        let episodeEnd: Int?
        let media: AnimeItem?
        let failed: Bool
        let parsedFilename: ParsedFilename?

        var episodeReference: EpisodeReference { episode }
    }

    struct ItemResolution<Item> {
        let target: ResolvedItem<Item>?
        let targetAnimeFiles: [ResolvedItem<Item>]
        let resolvedFiles: [ResolvedItem<Item>]
    }

    typealias ResolveResult = BatchResolution

    // MARK: - Private types

    private struct ParsedFile {
        let entry: FileEntry
        let animeTitle: String
        let animeSeasonValues: [String]
        let animeYearValues: [String]
        let animeTypes: [String]
        let episodeNumbers: [String]

        var animeSeason: Int? { animeSeasonValues.first.flatMap(parseEpisodeInt) }
        var animeYear: Int? { animeYearValues.first.flatMap(parseEpisodeInt) }

        var filename: ParsedFilename {
            ParsedFilename(animeTitle: animeTitle,
                           animeSeason: animeSeason,
                           animeYear: animeYear,
                           animeSeasonValues: animeSeasonValues,
                           animeYearValues: animeYearValues,
                           animeTypes: animeTypes,
                           episodeNumbers: episodeNumbers)
        }
    }

    private struct ResolvedCandidate {
        let entry: FileEntry
        let episode: EpisodeReference
        let episodeEnd: Int?
        let media: AnimeItem?
        let failed: Bool
        let parseObject: ParsedFile?

        var episodeNumber: Int { episode.intValue ?? 0 }

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

    private struct FilenameChoice<Item> {
        let item: Item
        let episode: EpisodeReference
        let season: Int
        let parsedFilename: ParsedFilename?
        let originalIndex: Int
    }

    private struct ParsedItem<Item> {
        let item: Item
        let filename: ParsedFilename
        let originalIndex: Int

        var animeTitle: String { filename.animeTitle }
        var animeSeason: Int? { filename.animeSeason }
        var animeYear: Int? { filename.animeYear }
        var animeSeasonValues: [String] { filename.animeSeasonValues }
        var animeYearValues: [String] { filename.animeYearValues }
        var animeTypes: [String] { filename.animeTypes }
        var episodeNumbers: [String] { filename.episodeNumbers }
    }

    private struct ResolvedItemCandidate<Item> {
        let item: Item
        let episode: EpisodeReference
        let episodeEnd: Int?
        let media: AnimeItem?
        let failed: Bool
        let parseObject: ParsedItem<Item>

        var episodeNumber: Int { episode.intValue ?? 0 }

        var publicItem: ResolvedItem<Item> {
            ResolvedItem(item: item,
                         episode: episode,
                         episodeEnd: episodeEnd,
                         media: media,
                         failed: failed,
                         parsedFilename: parseObject.filename)
        }
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

    private static let titleIDCacheQueue = DispatchQueue(label: "app.hayase.torrent-resolver.title-cache")
    private static var titleIDCache: [String: Int] = [:]

    // MARK: - Public API

    /// Filename-only fallback for flows that do not have AniList media yet.
    ///
    /// This keeps the same batch result shape as the AniList-backed resolver so
    /// callers do not fall back to raw torrent-file indexing.
    func resolveByFilename(files: [FileEntry], targetEpisode: Int) -> BatchResolution {
        let videoFiles = files.filter { Self.isVideoFile($0.name) }
        let otherFiles = files.filter { !Self.isVideoFile($0.name) }
        let choices = Self.filenameChoices(from: videoFiles) { $0.name }

        if choices.count == 1, let choice = choices.first {
            let file = ResolvedFile(entry: choice.item,
                                    episode: .number(Double(targetEpisode)),
                                    parsedFilename: choice.parsedFilename)
            return BatchResolution(target: file,
                                   targetAnimeFiles: [file],
                                   otherFiles: otherFiles,
                                   resolvedFiles: [file])
        }

        let resolvedFiles = choices.map { choice in
            ResolvedFile(entry: choice.item,
                         episode: choice.episode,
                         parsedFilename: choice.parsedFilename)
        }
        let targetAnimeFiles = Self.sortedFilenameChoices(choices).map { choice in
            ResolvedFile(entry: choice.item,
                         episode: choice.episode,
                         parsedFilename: choice.parsedFilename)
        }
        let target = Self.pickFilenameChoice(from: choices, targetEpisode: targetEpisode).map { choice in
            ResolvedFile(entry: choice.item,
                         episode: choice.episode,
                         parsedFilename: choice.parsedFilename)
        }

        return BatchResolution(target: target,
                               targetAnimeFiles: targetAnimeFiles,
                               otherFiles: otherFiles,
                               resolvedFiles: resolvedFiles)
    }

    static func selectByFilename<Item>(from items: [Item],
                                       targetEpisode: Int,
                                       name: (Item) -> String?) -> Item? {
        let choices = filenameChoices(from: items, name: name)
        if choices.count == 1 { return choices[0].item }
        return pickFilenameChoice(from: choices, targetEpisode: targetEpisode)?.item
    }

    /// AniList-backed selector for file lists that are not represented by
    /// libtorrent `FileEntry` values, such as the WebTorrent backend. This
    /// mirrors the same resolver path as `resolve(files:targetEpisode:targetMedia:)`
    /// instead of falling back to raw filename episode matching.
    func selectByAnime<Item>(from items: [Item],
                             targetEpisode: Int,
                             targetMedia: AnimeItem,
                             name: @escaping (Item) -> String?,
                             completion: @escaping (Item?) -> Void) {
        resolveItemsByAnime(from: items,
                            targetEpisode: targetEpisode,
                            targetMedia: targetMedia,
                            name: name) { result in
            completion(result.target?.item)
        }
    }

    func resolveItemsByAnime<Item>(from items: [Item],
                                   targetEpisode: Int,
                                   targetMedia: AnimeItem,
                                   name: @escaping (Item) -> String?,
                                   completion: @escaping (ItemResolution<Item>) -> Void) {
        let parsedItems = Self.parsedItems(from: items, name: name)
        guard !parsedItems.isEmpty else {
            completion(ItemResolution(target: nil, targetAnimeFiles: [], resolvedFiles: []))
            return
        }

        if parsedItems.count == 1, let parsed = parsedItems.first {
            let item = ResolvedItem(item: parsed.item,
                                    episode: .number(Double(targetEpisode)),
                                    episodeEnd: nil,
                                    media: targetMedia,
                                    failed: false,
                                    parsedFilename: parsed.filename)
            completion(ItemResolution(target: item, targetAnimeFiles: [item], resolvedFiles: [item]))
            return
        }

        resolveItemAnime(parsedItems) { resolvedCandidates in
            var candidates = resolvedCandidates
            var targetAnimeFiles = candidates.filter { $0.media?.id == targetMedia.id }

            if targetAnimeFiles.isEmpty {
                if !candidates.isEmpty {
                    let commonTitle = Self.highestOccurence(candidates) { candidate in
                        candidate.parseObject.animeTitle
                    }
                    targetAnimeFiles = candidates.filter { $0.parseObject.animeTitle == commonTitle }
                } else {
                    candidates = parsedItems.map { parsed in
                        ResolvedItemCandidate(item: parsed.item,
                                              episode: Self.episodeReference(from: parsed.episodeNumbers.first),
                                              episodeEnd: nil,
                                              media: targetMedia,
                                              failed: false,
                                              parseObject: parsed)
                    }
                    targetAnimeFiles = candidates
                }
            }

            targetAnimeFiles = Self.sortedItemCandidates(targetAnimeFiles)
            let target = targetAnimeFiles.first { $0.episode.matches(targetEpisode) }
                ?? targetAnimeFiles.first { $0.episode.matches(1) }
                ?? targetAnimeFiles.first
                ?? candidates.first

            completion(ItemResolution(target: target?.publicItem,
                                      targetAnimeFiles: targetAnimeFiles.map { $0.publicItem },
                                      resolvedFiles: candidates.map { $0.publicItem }))
        }
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
                    candidates = videoFiles.map { file in
                        let parsed = Self.parseFile(file)
                        return Self.toCandidate(file,
                                                parseObject: parsed,
                                                media: targetMedia,
                                                episode: Self.episodeReference(from: parsed?.episodeNumbers.first),
                                                failed: false)
                    }
                    targetAnimeFiles = candidates
                }
            }

            targetAnimeFiles = Self.sortedCandidates(targetAnimeFiles)

            let target = targetAnimeFiles.first { $0.episode.matches(targetEpisode) }
                ?? targetAnimeFiles.first { $0.episode.matches(1) }
                ?? targetAnimeFiles.first
                ?? candidates.first

            completion(ResolveResult(target: target?.publicFile,
                                     targetAnimeFiles: targetAnimeFiles.map { $0.publicFile },
                                     otherFiles: otherFiles,
                                     resolvedFiles: candidates.map { $0.publicFile }))
        }
    }

    // MARK: - Interface resolver parity

    private func resolveFileAnime(_ parsedFiles: [ParsedFile],
                                  completion: @escaping ([ResolvedCandidate]) -> Void) {
        guard !parsedFiles.isEmpty else {
            completion([])
            return
        }

        let keys = Self.orderedUnique(parsedFiles.map { Self.cacheKey(for: $0) })
        var titleIDs = Self.cachedTitleIDs(for: keys)

        let titleGroups: [(key: String, titles: [String], year: String?)] = keys.compactMap { key in
            guard titleIDs[key] == nil,
                  let parsed = parsedFiles.first(where: { Self.cacheKey(for: $0) == key }) else { return nil }
            return (key: key, titles: Self.alternativeTitles(for: parsed), year: parsed.animeYearValues.first)
        }

        func fetchResolvedMedia() {
            let ids = Self.orderedUnique(keys.compactMap { titleIDs[$0] })
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
                Self.storeTitleIDs(ids)
                titleIDs.merge(ids) { cached, _ in cached }
            case .failure(let error):
                NSLog("[TorrentBatchResolver] AniList resolver search failed: %@", error.description)
            }
            fetchResolvedMedia()
        }
    }

    private static func resolveEpisode(parseObject: ParsedFile,
                                       media: AnimeItem,
                                       completion: @escaping (AnimeItem, EpisodeReference, Int?, Bool) -> Void) {
        resolveEpisode(parsedFilename: parseObject.filename, media: media, completion: completion)
    }

    private static func resolveEpisode(parsedFilename: ParsedFilename,
                                       media: AnimeItem,
                                       completion: @escaping (AnimeItem, EpisodeReference, Int?, Bool) -> Void) {
        let numbers = parsedFilename.episodeNumbers
        let firstRaw = numbers.first
        let secondRaw = numbers.dropFirst().first
        let firstEpisode = firstRaw.flatMap(parseEpisodeInt)
        let secondEpisode = secondRaw.flatMap(parseEpisodeInt)
        let maxEpisode = Self.episodes(for: media)
        let hasEpisodeCount = maxEpisode > 0
        let format = media.format
        let shouldResolve = format != "MOVIE" || hasEpisodeCount

        guard shouldResolve, firstRaw != nil else {
            completion(media, episodeReference(from: firstRaw), nil, false)
            return
        }

        if let secondRaw {
            if firstEpisode == 1 {
                completion(media, .range("\(firstRaw ?? "") ~ \(secondRaw)"), secondEpisode, false)
            } else if hasEpisodeCount, let secondEpisode, secondEpisode > maxEpisode {
                overflowRootMedia(for: media, animeSeason: parsedFilename.animeSeason) { root in
                    resolveSeason(media: root ?? media,
                                  episode: secondEpisode,
                                  increment: parsedFilename.animeSeason == nil ? nil : true,
                                  offset: 0,
                                  rootMedia: root ?? media,
                                  force: false) { result in
                        let secondValue = parseEpisodeDouble(secondRaw) ?? Double(secondEpisode)
                        let diff = secondValue - Double(result.episode)
                        let firstValue = parseEpisodeDouble(firstRaw ?? "")
                        let firstPart = firstValue.map { formatEpisodeNumber($0 - diff) } ?? "NaN"
                        let episode = "\(firstPart) ~ \(result.episode)"
                        completion(result.rootMedia, .range(episode), result.episode, result.failed)
                    }
                }
            } else {
                let episode = "\(numberString(firstRaw)) ~ \(numberString(secondRaw))"
                completion(media, .range(episode), secondEpisode, false)
            }
            return
        }

        if hasEpisodeCount, let firstEpisode, firstEpisode > maxEpisode {
            overflowRootMedia(for: media, animeSeason: parsedFilename.animeSeason) { root in
                resolveSeason(media: root ?? media,
                              episode: firstEpisode,
                              increment: parsedFilename.animeSeason == nil ? nil : true,
                              offset: 0,
                              rootMedia: root ?? media,
                              force: false) { result in
                    completion(result.rootMedia, .number(Double(result.episode)), nil, result.failed)
                }
            }
        } else {
            completion(media, episodeReference(from: firstRaw), nil, false)
        }
    }

    private static func overflowRootMedia(for media: AnimeItem,
                                          animeSeason: Int?,
                                          completion: @escaping (AnimeItem?) -> Void) {
        guard animeSeason == nil else {
            completion(nil)
            return
        }
        let wantsParent = media.format == "OVA" || media.format == "ONA"
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
        let rootHighest = Self.episodes(for: rootMedia)

        func finishWithoutEdge(_ resolvedIncrement: Bool) {
            completion(SeasonResolveResult(media: media,
                                           episode: episode - offset,
                                           offset: offset,
                                           increment: resolvedIncrement,
                                           rootMedia: rootMedia,
                                           failed: true))
        }

        func resolveUsing(prequel: AnimeItem?) {
            let shouldFindSequel = prequel == nil && (increment == true || increment == nil)
            let resolvedIncrement = (increment == true) || prequel == nil

            if let prequel {
                continueSeasonResolve(edge: prequel,
                                      media: media,
                                      episode: episode,
                                      increment: resolvedIncrement,
                                      offset: offset,
                                      rootMedia: rootMedia,
                                      rootHighest: rootHighest,
                                      force: force,
                                      visited: nextVisited,
                                      completion: completion)
                return
            }

            guard shouldFindSequel else {
                finishWithoutEdge(resolvedIncrement)
                return
            }

            findEdge(media: media, type: "SEQUEL") { sequel in
                guard let sequel else {
                    finishWithoutEdge(resolvedIncrement)
                    return
                }
                continueSeasonResolve(edge: sequel,
                                      media: media,
                                      episode: episode,
                                      increment: resolvedIncrement,
                                      offset: offset,
                                      rootMedia: rootMedia,
                                      rootHighest: rootHighest,
                                      force: force,
                                      visited: nextVisited,
                                      completion: completion)
            }
        }

        if increment != true {
            findEdge(media: media, type: "PREQUEL", completion: resolveUsing(prequel:))
        } else {
            resolveUsing(prequel: nil)
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
            let highest = Self.episodes(for: nextMedia)
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
            relation.relationType == type
                && formats.contains(relation.media.format ?? "")
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
        let pattern = #".("# + videoExtensions.sorted().joined(separator: "|") + #")$"#
        return name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Extracts the most likely episode number from an anime filename using Anitomy.
    static func extractEpisodeNumber(from filename: String) -> Int? {
        let name = fixedAnitomyFilename((filename as NSString).lastPathComponent)
        let anitomy = Anitomy()
        anitomy.parse(name)

        return parseEpisodeInt(anitomy.get(.episodeNumber))
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
                          animeSeasonValues: parsed.animeSeasonValues,
                          animeYearValues: parsed.animeYearValues,
                          animeTypes: parsed.animeTypes,
                          episodeNumbers: parsed.episodeNumbers)
    }

    private static func parseFileName(_ filename: String) -> (animeTitle: String, animeSeason: Int?, animeYear: Int?, animeSeasonValues: [String], animeYearValues: [String], animeTypes: [String], episodeNumbers: [String])? {
        let name = fixedAnitomyFilename((filename as NSString).lastPathComponent)
        let anitomy = Anitomy()
        anitomy.parse(name)

        let seasonValues = anitomy.getAll(.animeSeason)
        let yearValues = anitomy.getAll(.animeYear)
        let episodeNumbers = anitomy.getAll(.episodeNumber)
        let title = anitomy.get(.animeTitle)
        let season = seasonValues.first.flatMap(parseEpisodeInt)
        let year = yearValues.first.flatMap(parseEpisodeInt)

        return (title, season, year, seasonValues, yearValues, anitomy.getAll(.animeType), episodeNumbers)
    }

    private static func parsedItems<Item>(from items: [Item],
                                          name: (Item) -> String?) -> [ParsedItem<Item>] {
        items.enumerated().compactMap { offset, item in
            guard let filename = name(item), Self.isVideoFile(filename), !Self.isExcludedType(filename) else {
                return nil
            }
            guard let parsed = parseFileName(filename) else { return nil }
            let parsedFilename = ParsedFilename(animeTitle: parsed.animeTitle,
                                                animeSeason: parsed.animeSeason,
                                                animeYear: parsed.animeYear,
                                                animeSeasonValues: parsed.animeSeasonValues,
                                                animeYearValues: parsed.animeYearValues,
                                                animeTypes: parsed.animeTypes,
                                                episodeNumbers: parsed.episodeNumbers)
            return ParsedItem(item: item, filename: parsedFilename, originalIndex: offset)
        }
    }

    private func resolveItemAnime<Item>(_ parsedItems: [ParsedItem<Item>],
                                        completion: @escaping ([ResolvedItemCandidate<Item>]) -> Void) {
        guard !parsedItems.isEmpty else {
            completion([])
            return
        }

        let keys = Self.orderedUnique(parsedItems.map { Self.cacheKey(for: $0.filename) })
        var titleIDs = Self.cachedTitleIDs(for: keys)

        let titleGroups: [(key: String, titles: [String], year: String?)] = keys.compactMap { key in
            guard titleIDs[key] == nil,
                  let parsed = parsedItems.first(where: { Self.cacheKey(for: $0.filename) == key }) else { return nil }
            return (key: key, titles: Self.alternativeTitles(for: parsed.filename), year: parsed.animeYearValues.first)
        }

        func fetchResolvedMedia() {
            let ids = Self.orderedUnique(keys.compactMap { titleIDs[$0] })
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
            var candidates: [ResolvedItemCandidate<Item>] = []

            func build(at index: Int) {
                guard index < parsedItems.count else {
                    completion(candidates)
                    return
                }

                let parsed = parsedItems[index]
                let key = Self.cacheKey(for: parsed.filename)
                guard let id = titleIDs[key], let media = mediaByID[id] else {
                    build(at: index + 1)
                    return
                }

                Self.resolveEpisode(parsedFilename: parsed.filename, media: media) { resolvedMedia, episode, episodeEnd, failed in
                    candidates.append(ResolvedItemCandidate(item: parsed.item,
                                                            episode: episode,
                                                            episodeEnd: episodeEnd,
                                                            media: resolvedMedia,
                                                            failed: failed,
                                                            parseObject: parsed))
                    build(at: index + 1)
                }
            }

            build(at: 0)
        }

        AniListClient.shared.searchResolverAnimeIDsResult(titleGroups: titleGroups) { result in
            switch result {
            case .success(let ids):
                Self.storeTitleIDs(ids)
                titleIDs.merge(ids) { cached, _ in cached }
            case .failure(let error):
                NSLog("[TorrentBatchResolver] AniList resolver search failed: %@", error.description)
            }
            fetchResolvedMedia()
        }
    }

    private static func filenameChoices<Item>(from items: [Item],
                                              name: (Item) -> String?) -> [FilenameChoice<Item>] {
        items.enumerated().compactMap { offset, item in
            guard let filename = name(item), Self.isVideoFile(filename), !Self.isExcludedType(filename) else {
                return nil
            }
            let parsed = parseFileName(filename)
            let parsedFilename = parsed.map {
                ParsedFilename(animeTitle: $0.animeTitle,
                               animeSeason: $0.animeSeason,
                               animeYear: $0.animeYear,
                               animeSeasonValues: $0.animeSeasonValues,
                               animeYearValues: $0.animeYearValues,
                               animeTypes: $0.animeTypes,
                               episodeNumbers: $0.episodeNumbers)
            }
            return FilenameChoice(item: item,
                                  episode: episodeReference(from: parsed?.episodeNumbers.first),
                                  season: parsed?.animeSeason ?? 1,
                                  parsedFilename: parsedFilename,
                                  originalIndex: offset)
        }
    }

    private static func sortedFilenameChoices<Item>(_ choices: [FilenameChoice<Item>]) -> [FilenameChoice<Item>] {
        choices.sorted { lhs, rhs in
            if lhs.season != rhs.season {
                return lhs.season > rhs.season
            }
            switch (lhs.episode.numericValue, rhs.episode.numericValue) {
            case let (left?, right?) where left != right:
                return left < right
            default:
                return lhs.originalIndex < rhs.originalIndex
            }
        }
    }

    private static func pickFilenameChoice<Item>(from choices: [FilenameChoice<Item>],
                                                 targetEpisode: Int) -> FilenameChoice<Item>? {
        let sorted = sortedFilenameChoices(choices)
        return sorted.first { $0.episode.matches(targetEpisode) }
            ?? sorted.first { $0.episode.matches(1) }
            ?? sorted.first
    }

    private static func fixedAnitomyFilename(_ name: String) -> String {
        guard !name.contains(" ") else { return name }
        return name.replacingOccurrences(of: #"s(\d{2})e(\d{2})\.([A-z])\."#,
                                          with: "S$1E$2 $3 ",
                                          options: [.regularExpression, .caseInsensitive])
    }

    private static func parseEpisodeInt(_ value: String) -> Int? {
        guard !value.isEmpty else { return nil }
        let digits = value.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private static func parseEpisodeDouble(_ value: String) -> Double? {
        guard !value.isEmpty else { return nil }
        return Double(value)
    }

    private static func episodeReference(from value: String?) -> EpisodeReference {
        guard let value else { return .missing }
        guard let number = parseEpisodeDouble(value), number.isFinite else { return .missing }
        return .number(number)
    }

    private static func numberString(_ value: String?) -> String {
        guard let value else { return "NaN" }
        guard let number = parseEpisodeDouble(value), number.isFinite else { return "NaN" }
        return formatEpisodeNumber(number)
    }

    private static func formatEpisodeNumber(_ value: Double) -> String {
        guard value.isFinite else { return "NaN" }
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(value)
    }

    private static func toCandidate(_ entry: FileEntry,
                                    parseObject: ParsedFile?,
                                    media: AnimeItem?,
                                    episode: Int,
                                    episodeEnd: Int? = nil,
                                    failed: Bool) -> ResolvedCandidate {
        toCandidate(entry,
                    parseObject: parseObject,
                    media: media,
                    episode: .number(Double(episode)),
                    episodeEnd: episodeEnd,
                    failed: failed)
    }

    private static func toCandidate(_ entry: FileEntry,
                                    parseObject: ParsedFile?,
                                    media: AnimeItem?,
                                    episode: EpisodeReference,
                                    episodeEnd: Int? = nil,
                                    failed: Bool) -> ResolvedCandidate {
        ResolvedCandidate(entry: entry,
                          episode: episode,
                          episodeEnd: episodeEnd,
                          media: media,
                          failed: failed,
                          parseObject: parseObject)
    }

    private static func sortedCandidates(_ candidates: [ResolvedCandidate]) -> [ResolvedCandidate] {
        candidates.enumerated().sorted { lhs, rhs in
            let left = lhs.element
            let right = rhs.element
            let leftSeason = left.parseObject?.animeSeason ?? 1
            let rightSeason = right.parseObject?.animeSeason ?? 1
            if leftSeason != rightSeason {
                return leftSeason > rightSeason
            }

            switch (left.episode.numericValue, right.episode.numericValue) {
            case let (leftEpisode?, rightEpisode?) where leftEpisode != rightEpisode:
                return leftEpisode < rightEpisode
            default:
                return lhs.offset < rhs.offset
            }
        }.map { $0.element }
    }

    private static func sortedItemCandidates<Item>(_ candidates: [ResolvedItemCandidate<Item>]) -> [ResolvedItemCandidate<Item>] {
        candidates.sorted { lhs, rhs in
            let leftSeason = lhs.parseObject.animeSeason ?? 1
            let rightSeason = rhs.parseObject.animeSeason ?? 1
            if leftSeason != rightSeason {
                return leftSeason > rightSeason
            }

            switch (lhs.episode.numericValue, rhs.episode.numericValue) {
            case let (leftEpisode?, rightEpisode?) where leftEpisode != rightEpisode:
                return leftEpisode < rightEpisode
            default:
                return lhs.parseObject.originalIndex < rhs.parseObject.originalIndex
            }
        }
    }

    private static func cacheKey(for parseObject: ParsedFile) -> String {
        cacheKey(for: parseObject.filename)
    }

    private static func cacheKey(for parsedFilename: ParsedFilename) -> String {
        var key = AniListUtil.removeDiacritics(parsedFilename.animeTitle)
        if let year = parsedFilename.animeYearValues.first {
            key += year
        }
        if let season = parsedFilename.animeSeasonValues.first {
            key += "S\(season)"
        }
        return key
    }

    private static func alternativeTitles(for parseObject: ParsedFile) -> [String] {
        alternativeTitles(for: parseObject.filename)
    }

    /// resolver.ts `alternativeTitles`, in the order it adds them: the first title that finds a media
    /// is the one a file is given.
    private static func alternativeTitles(for parseObject: ParsedFilename) -> [String] {
        let title = AniListUtil.removeDiacritics(parseObject.animeTitle)

        var titles: [String] = []
        var modified = title

        // remove trailing ` 2020`
        if let yearMatch = firstMatch(in: title, pattern: #"\D(\d{4})$"#),
           parseObject.animeYearValues.isEmpty || yearMatch == parseObject.animeYearValues.first {
            modified = replaceFirst(in: title, pattern: #"\D(\d{4})$"#, with: "")
            appendUnique(modified, to: &titles)
        }

        // preemptively change S2 into Season 2 or 2nd Season, otherwise this will have accuracy issues
        let seasonMatch = firstMatch(in: modified, pattern: #" S(\d+)"#)
        if let season = parseObject.animeSeason, season > 1 {
            modified = modified + " \(season)\(seasonSuffix(season)) Season"
            appendUnique(modified, to: &titles)
            appendUnique(modified + " Season \(season)", to: &titles)
        } else if let seasonMatch, let season = Int(seasonMatch) {
            if season == 1 {
                // if this is S1, remove the " S1" or " S01"
                modified = replaceFirst(in: modified, pattern: #" S(\d+)"#, with: "")
                appendUnique(modified, to: &titles)
            } else {
                modified = replaceFirst(in: modified, pattern: #" S(\d+)"#, with: " \(season)\(seasonSuffix(season)) Season")
                appendUnique(modified, to: &titles)
                appendUnique(replaceFirst(in: modified, pattern: #" S(\d+)"#, with: " Season \(season)"), to: &titles)
            }
        } else {
            // only add original title [to not duplicate with year] if we're sure there's no season stuff
            appendUnique(title, to: &titles)
        }

        // remove - :
        if modified.range(of: #"[-:]"#, options: .regularExpression) != nil {
            modified = modified.replacingOccurrences(of: #"[-:]"#, with: "", options: .regularExpression)
            modified = replaceFirst(in: modified, pattern: #"[ ]{2,}"#, with: " ")
            appendUnique(modified, to: &titles)
        }

        // remove (TV)
        if modified.contains("(TV)") {
            modified = modified.replacingOccurrences(of: "(TV)", with: "", options: [], range: modified.range(of: "(TV)"))
            appendUnique(modified, to: &titles)
        }

        return titles
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

    /// util.ts `episodes(media)`
    static func episodes(for media: AnimeItem) -> Int {
        AniListUtil.episodes(for: media)
    }

    private static func cachedTitleIDs(for keys: [String]) -> [String: Int] {
        titleIDCacheQueue.sync {
            var result: [String: Int] = [:]
            for key in keys {
                if let id = titleIDCache[key] {
                    result[key] = id
                }
            }
            return result
        }
    }

    private static func storeTitleIDs(_ ids: [String: Int]) {
        guard !ids.isEmpty else { return }
        titleIDCacheQueue.sync {
            for (key, id) in ids where titleIDCache[key] == nil {
                titleIDCache[key] = id
            }
        }
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func orderedUnique(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func appendUnique(_ value: String, to values: inout [String]) {
        guard !value.isEmpty, !values.contains(value) else { return }
        values.append(value)
    }

    private static func firstMatch(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[swiftRange])
    }

    private static func replaceFirst(in value: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let swiftRange = Range(match.range, in: value) else { return value }
        return value.replacingCharacters(in: swiftRange, with: replacement)
    }

    private static func seasonSuffix(_ value: Int) -> String {
        switch value {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
