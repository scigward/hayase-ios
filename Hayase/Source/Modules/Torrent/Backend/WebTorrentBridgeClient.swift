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
    case versionMismatch(expected: String, actual: String?)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid WebTorrent bridge URL."
        case .invalidResponse:
            return "Invalid WebTorrent bridge response."
        case .versionMismatch(let expected, let actual):
            return "WebTorrent bridge version mismatch. Expected \(expected), got \(actual ?? "unknown"). Restart the app so the new bridge is used."
        case .server(let message):
            return message
        }
    }
}

final class WebTorrentBridgeClient {
    static let expectedVersion = "hayase-webtorrent-bridge-v10"

    private struct BridgeErrorPayload: Decodable {
        let message: String
    }

    private struct BridgeResponse<T: Decodable>: Decodable {
        let ok: Bool
        let result: T?
        let error: BridgeErrorPayload?
    }

    private struct HealthPayload: Decodable {
        let ok: Bool
        let version: String?
        let phase: String?
    }

    private struct EmptyResult: Decodable {}

    private let baseURL: URL
    private let token: String
    private let session: URLSession

    init(port: Int, token: String, session: URLSession = .shared) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        self.token = token
        self.session = session
    }

    /// Every bridge request carries the per-launch token; the bridge rejects the rest.
    private func makeRequest(path: String, query: [URLQueryItem] = [], timeout: TimeInterval) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        var request = URLRequest(url: components?.url ?? baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    func health(completion: @escaping (Result<Void, Error>) -> Void) {
        let request = makeRequest(path: "health", timeout: 1.0)
        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data else {
                completion(.failure(WebTorrentBridgeError.invalidResponse))
                return
            }
            do {
                let health = try JSONDecoder().decode(HealthPayload.self, from: data)
                guard health.ok else {
                    completion(.failure(WebTorrentBridgeError.invalidResponse))
                    return
                }
                guard health.version == Self.expectedVersion else {
                    completion(.failure(WebTorrentBridgeError.versionMismatch(expected: Self.expectedVersion,
                                                                              actual: health.version)))
                    return
                }
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    /// `afterEventID`: the last event the caller has seen. The bridge then returns every event
    /// since, where otherwise it returns only the latest few.
    func status(afterEventID: Int? = nil, completion: @escaping (Result<WebTorrentBridgeStatus, Error>) -> Void) {
        let request = makeRequest(path: "status",
                                  query: afterEventID.map { [URLQueryItem(name: "after", value: String($0))] } ?? [],
                                  timeout: 2.0)
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
                let response = try JSONDecoder().decode(BridgeResponse<WebTorrentBridgeStatus>.self, from: data)
                if response.ok, let status = response.result {
                    completion(.success(status))
                } else {
                    completion(.failure(WebTorrentBridgeError.server(response.error?.message ?? "WebTorrent status failed.")))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func updateSettings(_ settings: TorrentBackendSettings, completion: ((Result<Void, Error>) -> Void)? = nil) {
        call(method: "updateSettings", params: ["settings": settings.dictionary(), "debug": Settings.debugLevel]) { (result: Result<EmptyResult, Error>) in
            completion?(result.map { _ in () })
        }
    }

    /// `requestID` names the load, so `cancelPlay` can drop it.
    func playTorrent(id: Any,
                     mediaID: Int,
                     episode: Int,
                     requestID: String,
                     completion: @escaping (Result<[WebTorrentFile], Error>) -> Void) -> URLSessionDataTask? {
        call(method: "playTorrent", params: [
            "id": id,
            "mediaID": mediaID,
            "episode": episode,
            "requestID": requestID,
        ], completion: completion)
    }

    func cancelPlay(requestID: String) {
        call(method: "cancelPlay", params: ["requestID": requestID]) { (_: Result<EmptyResult, Error>) in }
    }

    /// Releases the backend session. With a `requestID` only the load that owns it may.
    func stopSession(requestID: String?) {
        var params: [String: Any] = [:]
        params["requestID"] = requestID
        call(method: "stopSession", params: params) { (_: Result<EmptyResult, Error>) in }
    }

    func cachedTorrents(completion: @escaping (Result<[String], Error>) -> Void) {
        call(method: "cachedTorrents", params: [:], completion: completion)
    }


    func library(completion: @escaping (Result<[WebTorrentLibraryEntry], Error>) -> Void) {
        call(method: "library", params: [:], completion: completion)
    }

    func torrentInfo(hash: String, completion: @escaping (Result<WebTorrentTorrentInfo, Error>) -> Void) {
        call(method: "torrentInfo", params: ["hash": hash], completion: completion)
    }

    func peerInfo(hash: String, completion: @escaping (Result<[WebTorrentPeerInfo], Error>) -> Void) {
        call(method: "peerInfo", params: ["hash": hash], completion: completion)
    }

    func fileInfo(hash: String, completion: @escaping (Result<[WebTorrentFileInfo], Error>) -> Void) {
        call(method: "fileInfo", params: ["hash": hash], completion: completion)
    }

    func protocolStatus(hash: String, completion: @escaping (Result<WebTorrentProtocolStatus, Error>) -> Void) {
        call(method: "protocolStatus", params: ["hash": hash], completion: completion)
    }

    func trackers(hash: String, completion: @escaping (Result<[String: WebTorrentTrackerInfo], Error>) -> Void) {
        call(method: "trackers", params: ["hash": hash], completion: completion)
    }

    func rescanTorrents(hashes: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        call(method: "rescanTorrents", params: ["hashes": hashes]) { (result: Result<EmptyResult, Error>) in
            completion(result.map { _ in () })
        }
    }

    func deleteTorrents(hashes: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        call(method: "deleteTorrents", params: ["hashes": hashes]) { (result: Result<EmptyResult, Error>) in
            completion(result.map { _ in () })
        }
    }

    // MARK: - Web seeds (mirrors interface's native.createNZB / createHTTPWebSeed)

    func createNZB(hash: String, url: String, completion: @escaping (Result<Void, Error>) -> Void) {
        call(method: "createNZB", params: ["hash": hash, "url": url]) { (result: Result<EmptyResult, Error>) in
            completion(result.map { _ in () })
        }
    }

    func createHTTPWebSeed(hash: String, seed: WebSeedResult, completion: @escaping (Result<Void, Error>) -> Void) {
        // Omit absent fields: torrent-client treats a null file index as present.
        var params: [String: Any] = ["hash": hash, "url": seed.url]
        params["authorization"] = seed.authorization
        params["index"] = seed.index
        params["rateLimit"] = seed.rateLimit
        call(method: "createHTTPWebSeed", params: params) { (result: Result<EmptyResult, Error>) in
            completion(result.map { _ in () })
        }
    }

    // MARK: - Casting (mirrors interface's native.getDisplays / castPlay / castClose)

    func listDisplays(completion: @escaping (Result<[WebTorrentDisplay], Error>) -> Void) {
        call(method: "listDisplays", params: [:], completion: completion)
    }

    func playDisplay(host: String,
                     hash: String,
                     id: Int,
                     media: [String: Any],
                     completion: @escaping (Result<Void, Error>) -> Void) {
        call(method: "playDisplay", params: [
            "host": host,
            "hash": hash,
            "id": id,
            "media": media,
        ]) { (result: Result<EmptyResult, Error>) in
            completion(result.map { _ in () })
        }
    }

    func closeDisplay(host: String, completion: @escaping (Result<Void, Error>) -> Void) {
        call(method: "closeDisplay", params: ["host": host]) { (result: Result<EmptyResult, Error>) in
            completion(result.map { _ in () })
        }
    }

    @discardableResult
    private func call<T: Decodable>(method: String,
                                    params: [String: Any],
                                    completion: @escaping (Result<T, Error>) -> Void) -> URLSessionDataTask? {
        var request = makeRequest(path: "rpc", timeout: 120)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let data = JSONSerialization.safeData([
            "id": UUID().uuidString,
            "method": method,
            "params": params,
        ]) else {
            completion(.failure(CocoaError(.coderInvalidValue)))
            return nil
        }
        request.httpBody = data

        let task = session.dataTask(with: request) { data, _, error in
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
        }
        task.resume()
        return task
    }
}
