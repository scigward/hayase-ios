//
//  WebTorrentWebSeeds.swift
//  Hayase
//

// Mirrors: interface/src/lib/modules/torrent/client.ts (_addNZBs, _addHTTPWebSeeds)

import Foundation

/// Adds the NZB and HTTP web seeds that the user's extensions provide for a
/// torrent, so it also downloads from Usenet and HTTP mirrors.
enum WebTorrentWebSeeds {
    /// `episode` is nil when it is not known, for example a torrent opened from Downloads.
    /// `media` is the media the caller already has; it is looked up only when there is none,
    /// as interface passes the one it is playing.
    static func add(hash: String, mediaID: Int, media: AnimeItem? = nil, episode: Int?, files: ExtensionFileQuery) {
        guard !hash.isEmpty, mediaID > 0 else { return }
        Task { @MainActor in
            guard let item = await resolvedMedia(media, id: mediaID),
                  let info = try? await result({ TorrentBackendManager.shared.webTorrentInfo(hash: hash, completion: $0) }),
                  info.progress < 1 else { return }
            async let nzbs: Void = addNZBs(hash: hash, name: info.name, files: files, item: item, episode: episode)
            async let seeds: Void = addHTTPWebSeeds(hash: hash, name: info.name, files: files, item: item, episode: episode)
            _ = await (nzbs, seeds)
        }
    }

    private static func resolvedMedia(_ media: AnimeItem?, id: Int) async -> AnimeItem? {
        if let media { return media }
        do {
            return try await result { AniListClient.shared.fetchResolverMediaByIdResult(id, completion: $0) }
        } catch {
            StreamingLogger.shared.error("Could not load media \(id) for web seeds: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    private static func addNZBs(hash: String, name: String, files: ExtensionFileQuery,
                                item: AnimeItem, episode: Int?) async {
        guard TorrentBackendSettings().hasNZBServer else { return }
        let urls = await ExtensionService.shared.nzbURLs(hash: hash, name: name, files: files,
                                                         item: item, episode: episode)
        for url in urls {
            do {
                try await result { TorrentBackendManager.shared.createWebTorrentNZB(hash: hash, url: url, completion: $0) }
            } catch {
                AppErrorToast.show(error.localizedDescription, title: "Failed to add NZB")
            }
        }
    }

    @MainActor
    private static func addHTTPWebSeeds(hash: String, name: String, files: ExtensionFileQuery,
                                        item: AnimeItem, episode: Int?) async {
        let seeds = await ExtensionService.shared.webSeeds(hash: hash, name: name, files: files,
                                                           item: item, episode: episode)
        for seed in seeds {
            do {
                try await result { TorrentBackendManager.shared.createWebTorrentHTTPWebSeed(hash: hash, seed: seed, completion: $0) }
            } catch {
                AppErrorToast.show(error.localizedDescription, title: "Failed to add HTTP webseed")
            }
        }
    }

    /// Awaits a completion-handler API of the backend and AniList modules.
    private static func result<T, E: Error>(_ start: (@escaping (Result<T, E>) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            start { continuation.resume(with: $0.mapError { $0 as Error }) }
        }
    }
}
