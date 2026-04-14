//
//  MALAuth.swift
//  Hayase
//
//  MyAnimeList OAuth2 PKCE authentication provider.
//  Mirrors: src/lib/modules/auth/mal.ts
//

import Foundation

// MARK: - MAL Auth

final class MALAuth {

    static let defaultClientID = "6114d00ca681b67b7e37a611c4b054b4"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: "pref_malClientID") ?? defaultClientID }
        set { UserDefaults.standard.set(newValue, forKey: "pref_malClientID") }
    }

    static func generateCodeVerifier() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<128).map { _ in chars.randomElement()! })
    }

    static func authorizeURL(codeChallenge: String) -> URL {
        var components = URLComponents(string: "https://myanimelist.net/v1/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "plain"),
        ]
        return components.url!
    }

    static func exchangeCode(_ code: String, codeVerifier: String, completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: "https://myanimelist.net/v1/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(clientID)&grant_type=authorization_code&code=\(code)&code_verifier=\(codeVerifier)"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                completion(nil)
                return
            }
            completion(token)
        }.resume()
    }

    static func fetchViewer(token: String, completion: @escaping (TrackerViewer?) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.myanimelist.net/v2/users/@me?fields=anime_statistics")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? Int,
                  let name = json["name"] as? String else {
                completion(nil)
                return
            }
            let avatar = json["picture"] as? String
            completion(TrackerViewer(id: String(id), name: name, avatarURL: avatar))
        }.resume()
    }

    static func completeLogin(code: String, codeVerifier: String) {
        exchangeCode(code, codeVerifier: codeVerifier) { token in
            guard let token = token else { return }
            TrackerAccountManager.shared.setToken(token, for: .mal)
            fetchViewer(token: token) { viewer in
                DispatchQueue.main.async {
                    TrackerAccountManager.shared.setViewer(viewer, for: .mal)
                }
            }
        }
    }
}
