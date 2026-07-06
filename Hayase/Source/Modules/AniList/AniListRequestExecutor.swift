//
//  AniListRequestExecutor.swift
//  Hayase
//
//  Centralized AniList GraphQL transport.
//  Mirrors the interface urql stack's auth + retry exchange behavior.
//

import Foundation

final class AniListRequestToken {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    fileprivate func attach(_ task: URLSessionDataTask) {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            task.cancel()
        } else {
            self.task = task
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        self.task = nil
        lock.unlock()
        task?.cancel()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum AniListRequestError: Error, CustomStringConvertible {
    case invalidEndpoint
    case unauthenticated
    case encodingFailed(Error?)
    case emptyData
    case cancelled
    case network(Error)
    case httpStatus(Int, retryAfter: TimeInterval?)
    case graphQLErrors([String])
    case invalidJSON

    var isInvalidToken: Bool {
        switch self {
        case .httpStatus(let status, _):
            return status == 401
        case .graphQLErrors(let messages):
            return messages.contains { $0.caseInsensitiveCompare("Invalid token") == .orderedSame }
        default:
            return false
        }
    }

    var isRateLimitLike: Bool {
        switch self {
        case .httpStatus(let status, _):
            return status == 429 || status == 500
        case .network:
            return true
        case .graphQLErrors(let messages):
            return messages.contains { message in
                let lowercased = message.lowercased()
                return lowercased.contains("429") || lowercased.contains("rate") || lowercased.contains("500")
            }
        default:
            return false
        }
    }

    var description: String {
        switch self {
        case .invalidEndpoint:
            return "Invalid AniList endpoint."
        case .unauthenticated:
            return "AniList authentication is required."
        case .encodingFailed(let error):
            return "Could not encode AniList request body: \(error?.localizedDescription ?? "unknown error")"
        case .emptyData:
            return "AniList returned an empty response."
        case .cancelled:
            return "AniList request was cancelled."
        case .network(let error):
            return "AniList network error: \(error.localizedDescription)"
        case .httpStatus(let status, let retryAfter):
            if let retryAfter {
                return "AniList HTTP \(status), retry after \(retryAfter)s."
            }
            return "AniList HTTP \(status)."
        case .graphQLErrors(let messages):
            return "AniList GraphQL errors: \(messages.joined(separator: ", "))"
        case .invalidJSON:
            return "AniList returned invalid JSON."
        }
    }
}

struct AniListGraphQLResult {
    let data: Data
    let json: [String: Any]
    let response: HTTPURLResponse?
    let graphQLErrors: [String]

    init(data: Data,
         json: [String: Any],
         response: HTTPURLResponse?,
         graphQLErrors: [String] = []) {
        self.data = data
        self.json = json
        self.response = response
        self.graphQLErrors = graphQLErrors
    }

    var hasInvalidTokenError: Bool {
        graphQLErrors.contains { $0.caseInsensitiveCompare("Invalid token") == .orderedSame }
    }
}

final class AniListRequestExecutor {
    static let shared = AniListRequestExecutor()

    private let endpoint = URL(string: "https://graphql.anilist.co")!
    private let session: URLSession
    private let lockQueue = DispatchQueue(label: "com.hayase.anilist.requestExecutor")
    private let retryQueue = DispatchQueue(label: "com.hayase.anilist.retryDelay")

    private var inFlight: [String: [CompletionBox]] = [:]
    private var lastRetryTime = Date(timeIntervalSince1970: 0)

    private struct CompletionBox {
        let token: AniListRequestToken
        let callback: (Result<AniListGraphQLResult, AniListRequestError>) -> Void
    }

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func cancelAll() {
        lockQueue.async { [weak self] in
            guard let self else { return }
            let callbacks = self.inFlight.values.flatMap { $0 }
            self.inFlight.removeAll()
            callbacks.forEach { $0.token.cancel() }
        }
    }

    @discardableResult
    func execute(query: String,
                 variables: [String: Any]? = nil,
                 authorized: Bool = true,
                 dedupeKey: String? = nil,
                 completion: @escaping (Result<AniListGraphQLResult, AniListRequestError>) -> Void) -> AniListRequestToken {
        let token = AniListRequestToken()
        let key = dedupeKey ?? makeDedupeKey(query: query, variables: variables, authorized: authorized)

        lockQueue.async { [weak self] in
            guard let self else { return }
            if self.inFlight[key] != nil {
                self.inFlight[key, default: []].append(CompletionBox(token: token, callback: completion))
                return
            }
            self.inFlight[key] = [CompletionBox(token: token, callback: completion)]
            self.perform(query: query, variables: variables, authorized: authorized, key: key, attempt: 1)
        }

        return token
    }

    @discardableResult
    func perform(_ request: URLRequest,
                 context: String,
                 completion: @escaping (Result<Data, AniListRequestError>) -> Void) -> AniListRequestToken {
        let token = AniListRequestToken()
        let key = makeDedupeKey(request: request, context: context)

        lockQueue.async { [weak self] in
            guard let self else { return }
            if self.inFlight[key] != nil {
                self.inFlight[key, default: []].append(CompletionBox(token: token) { result in
                    completion(result.map { $0.data })
                })
                return
            }
            self.inFlight[key] = [CompletionBox(token: token) { result in
                completion(result.map { $0.data })
            }]
            self.perform(request, key: key, attempt: 1)
        }

        return token
    }

    private func perform(_ request: URLRequest, key: String, attempt: Int) {
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let httpResponse = response as? HTTPURLResponse
            let result = self.validate(data: data, response: httpResponse, error: error)
            self.clearAuthIfNeeded(for: result)

            if self.hasOnlyCancelledCallbacks(for: key) {
                self.finish(key: key, result: .failure(.cancelled))
                return
            }

            if case .failure(let requestError) = result,
               self.shouldRetry(requestError) {
                self.scheduleRetry(request: request, key: key, attempt: attempt, error: requestError)
                return
            }

            self.finish(key: key, result: result)
        }

        lockQueue.async { [weak self] in
            guard let callbacks = self?.inFlight[key] else { return }
            callbacks.forEach { $0.token.attach(task) }
        }
        task.resume()
    }

    private func perform(query: String,
                         variables: [String: Any]?,
                         authorized: Bool,
                         key: String,
                         attempt: Int) {
        guard let request = makeRequest(query: query, variables: variables, authorized: authorized) else {
            finish(key: key, result: .failure(.encodingFailed(nil)))
            return
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let httpResponse = response as? HTTPURLResponse
            let result = self.validate(data: data, response: httpResponse, error: error)
            self.clearAuthIfNeeded(for: result)

            if self.hasOnlyCancelledCallbacks(for: key) {
                self.finish(key: key, result: .failure(.cancelled))
                return
            }

            let cacheable = self.isCacheableQuery(query)
            if case .failure = result,
               cacheable,
               let cached = self.cachedGraphQLResult(for: key) {
                self.finish(key: key, result: .success(cached))
                return
            }

            if case .failure(let requestError) = result,
               self.shouldRetry(requestError) {
                self.scheduleRetry(query: query,
                                   variables: variables,
                                   authorized: authorized,
                                   key: key,
                                   attempt: attempt,
                                   error: requestError)
                return
            }

            if case .success(let graphQLResult) = result, cacheable {
                AniListOperationCache.shared.store(data: graphQLResult.data, for: key)
                AniListOperationCache.shared.purgeStaleEntries()
            }

            self.finish(key: key, result: result)
        }

        lockQueue.async { [weak self] in
            guard let callbacks = self?.inFlight[key] else { return }
            callbacks.forEach { $0.token.attach(task) }
        }
        task.resume()
    }

    private func isCacheableQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("query") || trimmed.hasPrefix("{")
    }

    private func cachedGraphQLResult(for key: String) -> AniListGraphQLResult? {
        guard let data = AniListOperationCache.shared.cachedData(for: key),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return AniListGraphQLResult(data: data, json: json, response: nil)
    }

    private func makeRequest(query: String, variables: [String: Any]?, authorized: Bool) -> URLRequest? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized, let token = TrackerAccountManager.shared.token(for: .anilist) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = ["query": query]
        if let variables { body["variables"] = variables }
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            return request
        } catch {
            NSLog("[AniListRequestExecutor] encode error: %@", error.localizedDescription)
            return nil
        }
    }

    private func validate(data: Data?,
                          response: HTTPURLResponse?,
                          error: Error?) -> Result<AniListGraphQLResult, AniListRequestError> {
        if let error = error as NSError?, error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            return .failure(.cancelled)
        }
        if let error { return .failure(.network(error)) }
        if let response, response.statusCode < 200 || response.statusCode >= 300 {
            return .failure(.httpStatus(response.statusCode, retryAfter: retryAfter(from: response)))
        }
        guard let data, !data.isEmpty else { return .failure(.emptyData) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.invalidJSON)
        }
        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.compactMap { $0["message"] as? String }
            let graphQLErrors = messages.isEmpty ? ["Unknown GraphQL error"] : messages
            if hasUsableGraphQLData(json) {
                return .success(AniListGraphQLResult(data: data,
                                                     json: json,
                                                     response: response,
                                                     graphQLErrors: graphQLErrors))
            }
            return .failure(.graphQLErrors(graphQLErrors))
        }
        return .success(AniListGraphQLResult(data: data, json: json, response: response))
    }


    private func hasUsableGraphQLData(_ json: [String: Any]) -> Bool {
        guard let data = json["data"] as? [String: Any] else { return false }
        return data.values.contains { value in
            !(value is NSNull)
        }
    }

    private func scheduleRetry(query: String,
                               variables: [String: Any]?,
                               authorized: Bool,
                               key: String,
                               attempt: Int,
                               error: AniListRequestError) {
        let delay = retryDelay(for: error, attempt: attempt)
        retryQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if self.hasOnlyCancelledCallbacks(for: key) {
                self.finish(key: key, result: .failure(.cancelled))
                return
            }
            self.perform(query: query,
                         variables: variables,
                         authorized: authorized,
                         key: key,
                         attempt: attempt + 1)
        }
    }

    private func scheduleRetry(request: URLRequest,
                               key: String,
                               attempt: Int,
                               error: AniListRequestError) {
        let delay = retryDelay(for: error, attempt: attempt)
        retryQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if self.hasOnlyCancelledCallbacks(for: key) {
                self.finish(key: key, result: .failure(.cancelled))
                return
            }
            self.perform(request, key: key, attempt: attempt + 1)
        }
    }

    private func shouldRetry(_ error: AniListRequestError) -> Bool {
        switch error {
        case .cancelled, .encodingFailed, .invalidEndpoint, .unauthenticated:
            return false
        case .network, .emptyData, .invalidJSON:
            return true
        case .httpStatus(let status, _):
            return status == 429 || status >= 500
        case .graphQLErrors(let messages):
            if error.isInvalidToken { return false }
            return messages.contains { message in
                let lowercased = message.lowercased()
                return lowercased.contains("429") || lowercased.contains("rate") || lowercased.contains("500")
            }
        }
    }

    private func clearAuthIfNeeded(for result: Result<AniListGraphQLResult, AniListRequestError>) {
        switch result {
        case .failure(let error) where error.isInvalidToken:
            TrackerAccountManager.shared.clearAniListSessionForAuthFailure()
        case .success(let response) where response.hasInvalidTokenError:
            TrackerAccountManager.shared.clearAniListSessionForAuthFailure()
        default:
            return
        }
    }

    private func retryDelay(for error: AniListRequestError, attempt: Int) -> TimeInterval {
        if case .httpStatus(_, let retryAfter?) = error {
            return retryAfter + 1
        }

        // Interface retryExchange starts at 100ms and caps at 60s. For
        // rate-limit-like failures, keep the native AniList-safe spacing that
        // prevents immediate retry storms.
        let baseDelay = min(0.1 * Double(attempt), 60)
        guard error.isRateLimitLike else { return baseDelay }

        let minimumSpacing: TimeInterval = 11
        return lockQueue.sync {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastRetryTime)
            let spacingDelay = max(0, minimumSpacing - elapsed)
            lastRetryTime = now.addingTimeInterval(max(minimumSpacing, spacingDelay))
            return min(max(baseDelay, minimumSpacing, spacingDelay), 60)
        }
    }

    private func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(header) { return seconds }
        if let date = HTTPDateFormatter.shared.date(from: header) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    private func finish(key: String, result: Result<AniListGraphQLResult, AniListRequestError>) {
        lockQueue.async { [weak self] in
            guard let self else { return }
            let callbacks = self.inFlight.removeValue(forKey: key) ?? []
            callbacks
                .filter { !$0.token.isCancelled }
                .forEach { $0.callback(result) }
        }
    }

    private func hasOnlyCancelledCallbacks(for key: String) -> Bool {
        lockQueue.sync {
            guard let callbacks = inFlight[key], !callbacks.isEmpty else { return true }
            return callbacks.allSatisfy { $0.token.isCancelled }
        }
    }

    private func makeDedupeKey(request: URLRequest, context: String) -> String {
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let auth = request.value(forHTTPHeaderField: "Authorization") ?? "public"
        return "\(context)|\(request.httpMethod ?? "POST")|\(request.url?.absoluteString ?? "")|\(auth)|\(body)"
    }

    private func makeDedupeKey(query: String, variables: [String: Any]?, authorized: Bool) -> String {
        let variableData = (try? JSONSerialization.data(withJSONObject: variables ?? [:], options: [.sortedKeys])) ?? Data()
        let variablesString = String(data: variableData, encoding: .utf8) ?? "{}"
        let authKey: String
        if authorized, let token = TrackerAccountManager.shared.token(for: .anilist) {
            authKey = "token:\(token.hashValue)"
        } else {
            authKey = "public"
        }
        return "\(authKey)|\(query.hashValue)|\(variablesString)"
    }
}

private final class HTTPDateFormatter {
    static let shared = HTTPDateFormatter()

    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}
