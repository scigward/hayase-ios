//
//  AnimeRouteLoader.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/routes/app/anime/[id]/+layout.ts
//

import Foundation

// MARK: - AnimeRouteLoader

/// The anime route's `load`: the page waits for its media and the anizip episodes.
enum AnimeRouteLoader {
    private static let specialFormats = ["SPECIAL", "OVA", "ONA"]
    private static let parentRelations = ["PARENT", "PREQUEL", "SEQUEL"]

    static func load(id: Int, completion: @escaping (Result<AnimeItem, AniListRequestError>) -> Void) {
        let group = DispatchGroup()
        var media: Result<AnimeItem, AniListRequestError>?

        group.enter()
        AniListClient.shared.fetchResolverMediaByIdResult(id) { result in
            DispatchQueue.main.async {
                media = result
                group.leave()
            }
        }

        group.enter()
        AniZipService.shared.preloadEpisodes(anilistID: id) { episodes in
            guard episodes?.mappings?.anidb_id == nil else {
                group.leave()
                return
            }
            // without an anidb mapping a special borrows its parent's episodes
            AniListClient.shared.fetchResolverMediaByIdResult(id) { result in
                guard case .success(let item) = result else {
                    group.leave()
                    return
                }
                parentForSpecial(item) { parentID in
                    guard let parentID else {
                        group.leave()
                        return
                    }
                    AniZipService.shared.preloadEpisodes(anilistID: parentID) { _ in group.leave() }
                }
            }
        }

        group.notify(queue: .main) {
            if let media {
                completion(media)
            }
        }
    }

    private static func parentForSpecial(_ item: AnimeItem, completion: @escaping (Int?) -> Void) {
        guard specialFormats.contains(item.format ?? "") else {
            completion(nil)
            return
        }
        // `getParentForSpecial(media)`: the relations of the media that was loaded
        completion(parentID(in: item.relations))
    }

    private static func parentID(in relations: [AnimeRelation]) -> Int? {
        parentRelations.lazy.compactMap { type in
            relations.first { $0.relationType == type }?.media.id
        }.first
    }
}
