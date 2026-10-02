//
//  TraceMoe.swift
//  Hayase
//
//  Mirrors: src/lib/utils.ts `TraceAnime` and `traceAnime`
//

import Foundation

/// A frame trace.moe matched to an image: which anime, which episode, and where in it.
struct TraceAnime: Decodable {
    let anilist: Int
    let filename: String?
    /// Shown as is: trace.moe gives a number, text, a list of them, or nothing.
    let episode: String
    let from: Double
    let to: Double
    let similarity: Double
    let video: String
    let image: String

    private enum CodingKeys: String, CodingKey {
        case anilist, filename, episode, from, to, similarity, video, image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        anilist = try container.decode(Int.self, forKey: .anilist)
        filename = try? container.decode(String.self, forKey: .filename)
        if let number = try? container.decode(Int.self, forKey: .episode) {
            episode = String(number)
        } else if let number = try? container.decode(Double.self, forKey: .episode) {
            episode = String(number)
        } else if let text = try? container.decode(String.self, forKey: .episode) {
            episode = text
        } else if let list = try? container.decode([Int].self, forKey: .episode) {
            episode = list.map(String.init).joined(separator: ",")
        } else {
            episode = ""   // `Episode {null}` renders nothing after the word
        }
        from = (try? container.decode(Double.self, forKey: .from)) ?? 0
        to = (try? container.decode(Double.self, forKey: .to)) ?? 0
        similarity = (try? container.decode(Double.self, forKey: .similarity)) ?? 0
        video = try container.decode(String.self, forKey: .video)
        image = try container.decode(String.self, forKey: .image)
    }
}

enum TraceMoe {
    private struct Response: Decodable {
        let result: [TraceAnime]
    }

    struct LookupError: Error {}

    /// `traceAnime(file)`: the image is the body of the request, as its own type, and trace.moe is
    /// asked to cut away black borders. No match is an error. `completion` runs on a background queue.
    static func lookup(image data: Data, mimeType: String,
                       completion: @escaping (Result<[TraceAnime], Error>) -> Void) {
        guard let url = URL(string: "https://api.trace.moe/search?cutBorders") else {
            completion(.failure(LookupError()))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-type")
        request.httpBody = data
        URLSession.shared.dataTask(with: request) { data, _, error in
            let result: Result<[TraceAnime], Error>
            if let error {
                result = .failure(error)
            } else if let data, let response = try? JSONDecoder().decode(Response.self, from: data),
                      !response.result.isEmpty {
                result = .success(response.result)
            } else {
                result = .failure(LookupError())
            }
            completion(result)
        }.resume()
    }
}
