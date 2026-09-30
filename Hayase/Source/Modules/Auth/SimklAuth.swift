//
//  SimklAuth.swift
//  Hayase
//
//  Mirrors: hayase-app/interface/src/lib/modules/auth/simkl.ts
//

import Foundation

final class SimklAuth {
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

    static func completeLogin(code: String, completion: @escaping (Result<TrackerViewer, Error>) -> Void) {
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            completion(.failure(AuthError.missingCredentials))
            return
        }
        guard let url = URL(string: "https://api.simkl.com/oauth/token") else {
            completion(.failure(AuthError.invalidResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                TrackerErrorToast.report(provider: "Simkl", data: data, response: response, error: error)
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                TrackerErrorToast.report(provider: "Simkl", data: data, response: response, error: error)
                DispatchQueue.main.async { completion(.failure(AuthError.invalidResponse)) }
                return
            }

            let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue
            let expiry = expiresIn.map { Date().addingTimeInterval($0) }
            TrackerAccountManager.shared.setToken(token, for: .simkl, expiresAt: expiry)
            fetchViewer(token: token) { viewer in
                DispatchQueue.main.async {
                    guard let viewer else {
                        TrackerAccountManager.shared.setToken(nil, for: .simkl)
                        completion(.failure(AuthError.invalidResponse))
                        return
                    }
                    TrackerAccountManager.shared.setViewer(viewer, for: .simkl)
                    completion(.success(viewer))
                }
            }
        }.resume()
    }

    static func fetchViewer(token: String, completion: @escaping (TrackerViewer?) -> Void) {
        guard let url = URL(string: "https://api.simkl.com/users/settings") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "simkl-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = json["account"] as? [String: Any],
                  let id = (account["id"] as? NSNumber)?.stringValue else {
                TrackerErrorToast.report(provider: "Simkl", data: data, response: response, error: error)
                completion(nil)
                return
            }
            let user = json["user"] as? [String: Any]
            let name = user?["name"] as? String ?? "Simkl User"
            let avatar = user?["avatar"] as? String
            completion(TrackerViewer(id: id, name: name, avatarURL: avatar))
        }.resume()
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
