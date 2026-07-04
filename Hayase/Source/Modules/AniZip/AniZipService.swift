//
//  AniZipService.swift
//  Hayase
//
//  AniZip API client — fetches episode metadata and ID mappings from ani.zip.
//  Mirrors: src/lib/modules/anizip/index.ts
//

import Foundation

final class AniZipService {
    static let shared = AniZipService()
    private init() {}

    private let baseURL = "https://api.ani.zip/v1"
    private let imagesBaseURL = "https://api.ani.zip/v2/images/tmdb"

    // MARK: - Cached episodes

    private var lastCachedID: Int = 0
    private var lastCachedData: AniZipEpisodesResponse?
    private var lastImagesCachedID: Int = 0
    private var lastImagesCachedData: AniZipImagesResponse?
    private let cacheQueue = DispatchQueue(label: "com.hayase.anizip.cache")

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


    func imagesCached(anilistID: Int, completion: @escaping (AniZipImagesResponse?) -> Void) {
        cacheQueue.async { [weak self] in
            guard let self else { completion(nil); return }
            if self.lastImagesCachedID == anilistID, let cached = self.lastImagesCachedData {
                completion(cached)
                return
            }
            self.images(anilistID: anilistID) { response in
                self.cacheQueue.async {
                    self.lastImagesCachedID = anilistID
                    self.lastImagesCachedData = response
                }
                completion(response)
            }
        }
    }

    // MARK: - TMDB Images

    func images(anilistID: Int, completion: @escaping (AniZipImagesResponse?) -> Void) {
        guard let url = URL(string: "\(imagesBaseURL)?anilist_id=\(anilistID)") else {
            completion(nil); return
        }
        safeFetch(url: url, completion: completion)
    }

    // MARK: - Episodes

    func episodes(anilistID: Int, completion: @escaping (AniZipEpisodesResponse?) -> Void) {
        guard let url = URL(string: "\(baseURL)/episodes?anilist_id=\(anilistID)") else {
            completion(nil); return
        }
        safeFetch(url: url, completion: completion)
    }

    // MARK: - Mappings

    func mappings(anilistID: Int, completion: @escaping (AniZipMappingsResponse?) -> Void) {
        guard let url = URL(string: "\(baseURL)/mappings?anilist_id=\(anilistID)") else {
            completion(nil); return
        }
        safeFetch(url: url, completion: completion)
    }

    func mappingsByKitsuId(_ kitsuId: Int, completion: @escaping (AniZipMappingsResponse?) -> Void) {
        guard let url = URL(string: "\(baseURL)/mappings?kitsu_id=\(kitsuId)") else {
            completion(nil); return
        }
        safeFetch(url: url, completion: completion)
    }

    func mappingsByMalId(_ malId: Int, completion: @escaping (AniZipMappingsResponse?) -> Void) {
        guard let url = URL(string: "\(baseURL)/mappings?mal_id=\(malId)") else {
            completion(nil); return
        }
        safeFetch(url: url, completion: completion)
    }

    // MARK: - Private

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
