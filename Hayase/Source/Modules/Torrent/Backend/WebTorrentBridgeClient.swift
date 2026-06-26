//
//  WebTorrentBridgeClient.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

enum WebTorrentBridgeError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid WebTorrent bridge URL."
        case .invalidResponse:
            return "Invalid WebTorrent bridge response."
        case .server(let message):
            return message
        }
    }
}

final class WebTorrentBridgeClient {
    private struct BridgeErrorPayload: Decodable {
        let message: String
    }

    private struct BridgeResponse<T: Decodable>: Decodable {
        let ok: Bool
        let result: T?
        let error: BridgeErrorPayload?
    }

    private struct EmptyResult: Decodable {}

    private let baseURL: URL
    private let session: URLSession

    init(port: Int, session: URLSession = .shared) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        self.session = session
    }

    func health(completion: @escaping (Bool) -> Void) {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        session.dataTask(with: request) { _, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            completion(status == 200)
        }.resume()
    }

    func updateSettings(_ settings: TorrentBackendSettings, completion: ((Result<Void, Error>) -> Void)? = nil) {
        call(method: "updateSettings", params: ["settings": settings.dictionary()]) { (result: Result<EmptyResult, Error>) in
            completion?(result.map { _ in () })
        }
    }

    func playTorrent(id: String,
                     mediaID: Int,
                     episode: Int,
                     completion: @escaping (Result<[WebTorrentFile], Error>) -> Void) {
        call(method: "playTorrent", params: [
            "id": id,
            "mediaID": mediaID,
            "episode": episode,
        ], completion: completion)
    }

    private func call<T: Decodable>(method: String,
                                    params: [String: Any],
                                    completion: @escaping (Result<T, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("rpc")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "id": UUID().uuidString,
                "method": method,
                "params": params,
            ])
        } catch {
            completion(.failure(error))
            return
        }

        session.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(WebTorrentBridgeError.invalidResponse))
                return
            }
            do {
                let response = try JSONDecoder().decode(BridgeResponse<T>.self, from: data)
                if response.ok, let result = response.result {
                    completion(.success(result))
                } else {
                    completion(.failure(WebTorrentBridgeError.server(response.error?.message ?? "WebTorrent bridge failed.")))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
