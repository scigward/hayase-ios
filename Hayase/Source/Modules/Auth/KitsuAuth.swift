//
//  KitsuAuth.swift
//  Hayase
//
//  Kitsu email/password authentication provider.
//  Mirrors: src/lib/modules/auth/kitsu.ts
//

import Foundation

// MARK: - Kitsu Auth

final class KitsuAuth {

    static func login(email: String, password: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://kitsu.app/api/oauth/token") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=password&username=\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&password=\(password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                TrackerErrorToast.report(provider: "Kitsu", data: data, response: response, error: error)
                DispatchQueue.main.async { completion(false) }
                return
            }
            TrackerAccountManager.shared.setToken(token, for: .kitsu)
            fetchViewer(token: token) { viewer in
                DispatchQueue.main.async {
                    TrackerAccountManager.shared.setViewer(viewer, for: .kitsu)
                    completion(viewer != nil)
                }
            }
        }.resume()
    }

    static func fetchViewer(token: String, completion: @escaping (TrackerViewer?) -> Void) {
        guard let url = URL(string: "https://kitsu.app/api/edge/users?filter[self]=true&fields[users]=name,avatar") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]],
                  let user = dataArray.first,
                  let id = user["id"] as? String,
                  let attributes = user["attributes"] as? [String: Any],
                  let name = attributes["name"] as? String else {
                TrackerErrorToast.report(provider: "Kitsu", data: data, response: response, error: error)
                completion(nil)
                return
            }
            let avatar = (attributes["avatar"] as? [String: Any])?["large"] as? String
            completion(TrackerViewer(id: id, name: name, avatarURL: avatar))
        }.resume()
    }
}
