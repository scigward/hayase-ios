import Foundation

/// Preserve the provider's error text rather than replacing it with a login alert.
/// Mirrors auth/{kitsu,mal,simkl}.ts; safe to call from URLSession callbacks.
enum TrackerErrorToast {
    static func report(provider: String, data: Data?, response: URLResponse?, error: Error?) {
        if let error = error as? URLError, error.code == .cancelled { return }
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        var messages: [String] = []
        if let error {
            messages = [error.localizedDescription]
        } else if provider == "Simkl" || provider == "MAL", let http = response as? HTTPURLResponse,
                  !(200..<300).contains(http.statusCode) {
            messages = ["HTTP \(http.statusCode): \(data.flatMap { String(data: $0, encoding: .utf8) } ?? "")"]
        } else if let description = json?["error_description"] as? String {
            messages = [description]
        } else if let errors = json?["errors"] as? [[String: Any]] {
            messages = errors.compactMap { $0["detail"] as? String }
        } else if let message = json?["message"] as? String ?? json?["error"] as? String {
            messages = [message]
        }
        if messages.isEmpty { messages = ["The server returned an invalid response."] }
        let descriptions = messages
        DispatchQueue.main.async {
            for message in descriptions { AppErrorToast.show(message, title: "\(provider) Error") }
        }
    }
}
