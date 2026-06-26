//
//  AnimeThemesService.swift
//  Hayase
//
//  AnimeThemes API client — fetches OP/ED themes from animethemes.moe.
//  Mirrors: src/lib/modules/animethemes/index.ts
//

import Foundation

final class AnimeThemesService {
    static let shared = AnimeThemesService()
    private init() {}

    // MARK: - Themes

    func themes(anilistID: Int, completion: @escaping (AnimeThemesResponse?) -> Void) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.animethemes.moe"
        components.path = "/anime/"
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
