//
//  MALAuth.swift
//  Hayase
//
//  MyAnimeList OAuth2 PKCE authentication.
//  Mirrors: src/lib/modules/auth/mal.ts (`login`); the rest is in MALSync.
//

import Foundation

// MARK: - MAL Auth

enum MALAuth {

    static let defaultClientID = "6114d00ca681b67b7e37a611c4b054b4"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: "pref_malClientID") ?? defaultClientID }
        set { UserDefaults.standard.set(newValue, forKey: "pref_malClientID") }
    }

    /// iOS: `hayase://authorize/`
    static let redirectURI = "hayase://authorize/"

    /// `(crypto.randomUUID() + crypto.randomUUID()).replaceAll('-', '')`
    static func generateCodeVerifier() -> String {
        (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func authorizeURL(codeChallenge: String) -> URL {
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var components = URLComponents()
        components.scheme = "https"
        components.host = "myanimelist.net"
        components.path = "/v1/oauth2/authorize"
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "plain"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        return components.url ?? URL(string: "https://myanimelist.net/v1/oauth2/authorize")!
    }

    static func completeLogin(code: String, codeVerifier: String) {
        Task { await MALSync.shared.login(code: code, challenge: codeVerifier) }
    }
}
