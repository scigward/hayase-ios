//
//  AnimeThemesService.swift
//  Hayase
//
//  AnimeThemes API client — fetches OP/ED themes from animethemes.moe.
//  Mirrors: src/lib/modules/animethemes/index.ts
//
//  Provides theme lookup by AniList external ID with the exact same API
//  query parameters and field selections as the web interface.
//

import Foundation

final class AnimeThemesService {
    static let shared = AnimeThemesService()
    private init() {}

    /// Fetches anime themes (OP/ED) from animethemes.moe by AniList ID.
    /// Mirrors `themes()` from animethemes/index.ts — uses exact same API
    /// endpoint with identical field filters and includes.
    func themes(anilistID: Int, completion: @escaping (AnimeThemesResponse?) -> Void) {
        // Exact query from interface: animethemes/index.ts themes()
        var components = URLComponents(string: "https://api.animethemes.moe/anime/")!
        components.percentEncodedQuery = [
            "fields%5Baudio%5D=id,basename,link,size",
            "fields%5Bvideo%5D=id,basename,link,tags",
            "filter%5Bexternal_id%5D=\(anilistID)",
            "filter%5Bhas%5D=resources",
            "filter%5Bsite%5D=AniList",
            "include=animethemes.animethemeentries.videos,animethemes.song,animethemes.song.artists"
        ].joined(separator: "&")

        guard let url = components.url else { completion(nil); return }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else {
                completion(nil); return
            }
            let result = try? JSONDecoder().decode(AnimeThemesResponse.self, from: data)
            completion(result)
        }.resume()
    }
}
