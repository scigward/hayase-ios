//
//  SimklAuth.swift
//  Hayase
//
//  Mirrors: hayase-app/interface/src/lib/modules/auth/simkl.ts
//

import Foundation

enum SimklAuth {
    static var clientID: String {
        get { UserDefaults.standard.string(forKey: "pref_simklClientID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "pref_simklClientID") }
    }

    static var clientSecret: String {
        get { Keychain.string(forKey: "pref_simklClientSecret") ?? "" }
        set { Keychain.set(newValue, forKey: "pref_simklClientSecret") }
    }

    static let redirectURI = "hayase://authorize/"

    static func authorizeURL(state: String) -> URL? {
        var components = URLComponents(string: "https://simkl.com/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        return components?.url
    }

    /// The second half of `login`, after the authorization has sent the code back.
    static func completeLogin(code: String, completion: @escaping (Result<TrackerViewer, Error>) -> Void) {
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            completion(.failure(AuthError.missingCredentials))
            return
        }
        Task {
            let signedIn = await SimklSync.shared.login(code: code)
            await MainActor.run {
                if signedIn, let viewer = TrackerAccountManager.shared.viewer(for: .simkl) {
                    completion(.success(viewer))
                } else {
                    completion(.failure(AuthError.invalidResponse))
                }
            }
        }
    }

    enum AuthError: LocalizedError {
        case missingCredentials
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Configure a Simkl Client ID and Client Secret before logging in."
            case .invalidResponse:
                return "Simkl returned an invalid authentication response."
            }
        }
    }
}
