// Mirrors: src/routes/app/settings/changelog/+page.svelte (module-scoped request)
import Foundation

struct HayaseChangelogEntry {
    let sha: String
    let date: Date
    let body: String
}

final class SettingsChangelogService {
    static let shared = SettingsChangelogService()

    private var cachedResult: Result<[HayaseChangelogEntry], Error>?
    private var waiters: [(Result<[HayaseChangelogEntry], Error>) -> Void] = []
    private var task: URLSessionDataTask?

    private init() {}

    func load(_ completion: @escaping (Result<[HayaseChangelogEntry], Error>) -> Void) {
        if let cachedResult {
            DispatchQueue.main.async { completion(cachedResult) }
            return
        }
        waiters.append(completion)
        guard task == nil else { return }
        guard let url = URL(string: "https://api.github.com/repos/hayase-app/interface/commits") else {
            complete(.failure(ChangelogError.invalidResponse))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result: Result<[HayaseChangelogEntry], Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(ChangelogError.http(http.statusCode))
            } else if let data,
                      let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let formatter = ISO8601DateFormatter()
                let entries = objects.compactMap { object -> HayaseChangelogEntry? in
                    guard let sha = object["sha"] as? String,
                          let commit = object["commit"] as? [String: Any],
                          let body = commit["message"] as? String,
                          let author = commit["author"] as? [String: Any],
                          let rawDate = author["date"] as? String,
                          let date = formatter.date(from: rawDate) else { return nil }
                    return HayaseChangelogEntry(sha: sha, date: date, body: body)
                }
                result = .success(entries)
            } else {
                result = .failure(ChangelogError.invalidResponse)
            }
            DispatchQueue.main.async { self?.complete(result) }
        }
        task?.resume()
    }

    private func complete(_ result: Result<[HayaseChangelogEntry], Error>) {
        task = nil
        cachedResult = result
        let completions = waiters
        waiters.removeAll()
        completions.forEach { $0(result) }
    }

    private enum ChangelogError: LocalizedError {
        case invalidResponse
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "The changelog response could not be decoded."
            case .http(let status): return "GitHub returned HTTP \(status)."
            }
        }
    }
}
