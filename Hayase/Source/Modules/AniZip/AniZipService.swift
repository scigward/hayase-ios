//
//  AniZipService.swift
//  Hayase
//
//  AniZip API client — fetches episode metadata and ID mappings from ani.zip.
//  Mirrors: src/lib/modules/anizip/index.ts
//
//  Provides cached and non-cached episode fetching, plus mapping lookups
//  by AniList ID, Kitsu ID, and MAL ID.
//

import Foundation

final class AniZipService {
    static let shared = AniZipService()
    private init() {}

    private let baseURL = "https://api.ani.zip/v1"

    // MARK: - Cached episodes (matches episodesCached in index.ts)

    private var lastCachedID: Int = 0
    private var lastCachedData: AniZipEpisodesResponse?
    private let cacheQueue = DispatchQueue(label: "com.hayase.anizip.cache")

    /// Fetches episodes for an AniList ID with simple in-memory caching.
    /// Mirrors `episodesCached()` from anizip/index.ts.
    func episodesCached(anilistID: Int, completion: @escaping (AniZipEpisodesResponse?) -> Void) {
        cacheQueue.async { [weak self] in
            guard let self else { completion(nil); return }
            if self.lastCachedID == anilistID, let cached = self.lastCachedData {
                completion(cached)
                return
            }
            self.episodes(anilistID: anilistID) { response in
                self.cacheQueue.async {
                    self.lastCachedID = anilistID
                    self.lastCachedData = response
                }
                completion(response)
            }
        }
    }

    // MARK: - Episodes (matches episodes() in index.ts)

    /// Fetches episode metadata for an AniList ID from ani.zip.
    /// Mirrors `episodes()` from anizip/index.ts.
    func episodes(anilistID: Int, completion: @escaping (AniZipEpisodesResponse?) -> Void) {
        guard let url = URL(string: "\(baseURL)/episodes?anilist_id=\(anilistID)") else {
            completion(nil); return
        }
        safeFetch(url: url, completion: completion)
    }

    // MARK: - Mappings (matches mappings() in index.ts)

    /// Fetches ID mappings for an AniList ID from ani.zip.
    /// Mirrors `mappings()` from anizip/index.ts.
    func mappings(anilistID: Int, completion: @escaping (AniZipMappingsResponse?) -> Void) {
        guard let url = URL(string: "\(baseURL)/mappings?anilist_id=\(anilistID)") else {
            completion(nil); return
        }
        safeFetch(url: url, completion: completion)
    }

    /// Fetches ID mappings by Kitsu ID from ani.zip.
    /// Mirrors `mappingsByKitsuId()` from anizip/index.ts.
    func mappingsByKitsuId(_ kitsuId: Int, completion: @escaping (AniZipMappingsResponse?) -> Void) {
        guard let url = URL(string: "\(baseURL)/mappings?kitsu_id=\(kitsuId)") else {
            completion(nil); return
        }
        safeFetch(url: url, completion: completion)
    }

    /// Fetches ID mappings by MAL ID from ani.zip.
    /// Mirrors `mappingsByMalId()` from anizip/index.ts.
    func mappingsByMalId(_ malId: Int, completion: @escaping (AniZipMappingsResponse?) -> Void) {
        guard let url = URL(string: "\(baseURL)/mappings?mal_id=\(malId)") else {
            completion(nil); return
        }
        safeFetch(url: url, completion: completion)
    }

    // MARK: - Private

    /// Generic fetch with JSON decoding — mirrors safefetch<T>() from $lib/utils.
    private func safeFetch<T: Decodable>(url: URL, completion: @escaping (T?) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else {
                completion(nil); return
            }
            let result = try? JSONDecoder().decode(T.self, from: data)
            completion(result)
        }.resume()
    }
}
