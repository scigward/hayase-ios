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
    /// A non-2xx response whose body is not GraphQL (a `networkError` for urql).
    case httpStatus(Int, retryAfter: TimeInterval?)
    case graphQLErrors([String])
    /// A non-2xx response whose body still carries GraphQL errors, as AniList's 429 and 404 do.
    case graphQLHTTP([String], status: Int, retryAfter: TimeInterval?)
    case invalidJSON

    private var graphQLMessages: [String]? {
        switch self {
        case .graphQLErrors(let messages), .graphQLHTTP(let messages, _, _):
            return messages
        default:
            return nil
        }
    }

    var isInvalidToken: Bool {
        graphQLMessages?.contains { $0.caseInsensitiveCompare("Invalid token") == .orderedSame } ?? false
    }

    /// urql-client.ts `retryIf`: `e.graphQLErrors[0]?.originalError?.message === 'validation'`
    var isValidation: Bool {
        graphQLMessages?.first == "validation"
    }

    /// retry.ts `isRateLimitError`: any network error, a 429 or 500 response, or an error message
    /// that mentions one of them (case sensitive, like `String.includes`).
    var isRateLimit: Bool {
        switch self {
        case .network, .httpStatus, .emptyData, .invalidJSON:
            return true
        case .graphQLHTTP(let messages, let status, _):
            return status == 429 || status == 500 || Self.mentionsRateLimit(messages)
        case .graphQLErrors(let messages):
            return Self.mentionsRateLimit(messages)
        default:
            return false
        }
    }

    private static func mentionsRateLimit(_ messages: [String]) -> Bool {
        messages.contains { $0.contains("429") || $0.contains("rate") || $0.contains("500") }
    }

    /// retry.ts `getRateLimitDelay`: the `retry-after` header of a GraphQL error plus one second,
    /// the shared eleven second spacing for a network error or a response without one.
    var retryAfterHeader: TimeInterval? {
        if case .graphQLHTTP(_, _, let retryAfter) = self { return retryAfter }
        return nil
    }

    /// `CombinedError.message`, printed by the Online bar after "AniList: ". A failure of the
    /// request itself, not of the response, has no message.
    var combinedMessage: String? {
        switch self {
        case .cancelled, .encodingFailed, .invalidEndpoint, .unauthenticated:
            return nil
        case .network:
            return "[Network] Load failed"
        case .httpStatus, .invalidJSON:
            return "[Network] JSON Parse error: Unrecognized token '<'"
        case .emptyData:
            return "[Network] JSON Parse error: Unexpected EOF"
        case .graphQLErrors(let messages), .graphQLHTTP(let messages, _, _):
            return messages.map { "[GraphQL] \($0)" }.joined(separator: "\n")
        }
    }

    /// What the interface prints for `error.message`; the requests that never went out have their own words.
    var description: String {
        combinedMessage ?? localDescription
    }

    private var localDescription: String {
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
        case .graphQLErrors(let messages), .graphQLHTTP(let messages, _, _):
            return "AniList GraphQL errors: \(messages.joined(separator: ", "))"
        case .invalidJSON:
            return "AniList returned invalid JSON."
        }
    }
}

extension AniListRequestError: LocalizedError {
    var errorDescription: String? { description }
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
    /// Queries whose callers were served from the cache while the network kept failing.
    private var refreshing: Set<String> = []
    /// retry.ts `lastRetryTime = Date.now() - 11_000`
    private var lastRetryTime = Date().addingTimeInterval(-11)

    /// retry.ts `RetryState`
    private struct RetryState {
        var count = 0
        var delay: TimeInterval?
        var isRateLimit = false
        /// offline.ts: a mutation with an optimistic result that fails offline is queued, not retried
        var optimistic = false
        /// the authorization has been run again for this request once
        var reauthenticated = false
    }

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
            self.refreshing.removeAll()
            callbacks.forEach { $0.token.cancel() }
        }
    }

    @discardableResult
    func execute(query: String,
                 variables: [String: Any]? = nil,
                 authorized: Bool = true,
                 dedupeKey: String? = nil,
                 optimistic: Bool = false,
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
            self.perform(query: query, variables: variables, authorized: authorized, key: key,
                         retry: RetryState(optimistic: optimistic))
        }

        return token
    }

    @discardableResult
    func perform(_ request: URLRequest,
                 context: String,
                 optimistic: Bool = false,
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
            self.perform(request, key: key, retry: RetryState(optimistic: optimistic))
        }

        return token
    }

    private func perform(_ request: URLRequest, key: String, retry: RetryState) {
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let httpResponse = response as? HTTPURLResponse
            let result = self.validate(data: data, response: httpResponse, error: error)
            self.report(result)

            if self.needsReauthentication(result, retry: retry) {
                self.reauthenticate(key: key, result: result) { [weak self] in
                    var again = retry
                    again.reauthenticated = true
                    var retried = request
                    if retried.value(forHTTPHeaderField: "Authorization") != nil,
                       let token = TrackerAccountManager.shared.token(for: .anilist) {
                        retried.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    self?.perform(retried, key: key, retry: again)
                }
                return
            }
            self.clearAuthIfNeeded(for: result)

            if self.hasOnlyCancelledCallbacks(for: key) {
                self.finish(key: key, result: .failure(.cancelled))
                return
            }

            if case .failure(let requestError) = result,
               retry.optimistic,
               AniListOfflineQueue.isOfflineError(requestError) {
                self.finish(key: key, result: result)
                return
            }

            if case .failure(let requestError) = result,
               self.shouldRetry(requestError) {
                self.scheduleRetry(request: request, key: key, retry: retry, error: requestError)
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
                         retry: RetryState) {
        guard let request = makeRequest(query: query, variables: variables, authorized: authorized) else {
            finish(key: key, result: .failure(.encodingFailed(nil)))
            return
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let httpResponse = response as? HTTPURLResponse
            let result = self.validate(data: data, response: httpResponse, error: error)
            self.report(result)

            if self.needsReauthentication(result, retry: retry) {
                self.reauthenticate(key: key, result: result) { [weak self] in
                    var again = retry
                    again.reauthenticated = true
                    self?.perform(query: query, variables: variables, authorized: authorized, key: key, retry: again)
                }
                return
            }
            self.clearAuthIfNeeded(for: result)

            if self.hasOnlyCancelledCallbacks(for: key) {
                self.finish(key: key, result: .failure(.cancelled))
                return
            }

            if case .failure(let requestError) = result,
               retry.optimistic,
               AniListOfflineQueue.isOfflineError(requestError) {
                self.finish(key: key, result: result)
                return
            }

            let cacheable = self.isCacheableQuery(query)
            if case .failure(let requestError) = result,
               cacheable,
               let cached = self.cachedGraphQLResult(for: key) {
                self.finish(key: key, result: .success(cached))
                // cache-and-network: the callers have their data, the request keeps retrying
                if self.shouldRetry(requestError) {
                    self.keepRefreshing(query: query, variables: variables, authorized: authorized,
                                        key: key, retry: retry, error: requestError)
                }
                return
            }

            if case .failure(let requestError) = result,
               self.shouldRetry(requestError) {
                self.scheduleRetry(query: query,
                                   variables: variables,
                                   authorized: authorized,
                                   key: key,
                                   retry: retry,
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

    /// The query is retried after its callers were served from the cache, until one attempt works.
    private func keepRefreshing(query: String,
                                variables: [String: Any]?,
                                authorized: Bool,
                                key: String,
                                retry: RetryState,
                                error: AniListRequestError) {
        let inserted = lockQueue.sync { refreshing.insert(key).inserted }
        guard inserted else { return }
        let (delay, next) = nextRetry(after: error, state: retry)
        scheduleRefresh(query: query, variables: variables, authorized: authorized, key: key, retry: next, delay: delay)
    }

    private func scheduleRefresh(query: String,
                                 variables: [String: Any]?,
                                 authorized: Bool,
                                 key: String,
                                 retry: RetryState,
                                 delay: TimeInterval) {
        retryQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            // stopped, or a caller asked again and its own request took over
            let proceed = self.lockQueue.sync { self.refreshing.contains(key) && self.inFlight[key] == nil }
            guard proceed, let request = self.makeRequest(query: query, variables: variables, authorized: authorized) else {
                self.lockQueue.async { self.refreshing.remove(key) }
                return
            }
            self.session.dataTask(with: request) { [weak self] data, response, error in
                guard let self else { return }
                let result = self.validate(data: data, response: response as? HTTPURLResponse, error: error)
                self.clearAuthIfNeeded(for: result)
                self.report(result)
                switch result {
                case .success(let graphQLResult):
                    AniListOperationCache.shared.store(data: graphQLResult.data, for: key)
                    AniListOperationCache.shared.purgeStaleEntries()
                    self.lockQueue.async { self.refreshing.remove(key) }
                case .failure(let requestError):
                    guard self.shouldRetry(requestError) else {
                        self.lockQueue.async { self.refreshing.remove(key) }
                        return
                    }
                    let (nextDelay, next) = self.nextRetry(after: requestError, state: retry)
                    self.scheduleRefresh(query: query, variables: variables, authorized: authorized,
                                         key: key, retry: next, delay: nextDelay)
                }
            }.resume()
        }
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

    /// urql-client.ts `tap`: `this.error.set(error)` for every result the network gives back.
    private func report(_ result: Result<AniListGraphQLResult, AniListRequestError>) {
        switch result {
        case .success(let graphQLResult):
            let messages = graphQLResult.graphQLErrors
            AniListConnectionStatus.shared.report(messages.isEmpty ? nil : messages.map { "[GraphQL] \($0)" }.joined(separator: "\n"))
        case .failure(let error):
            guard let message = error.combinedMessage else { return }
            AniListConnectionStatus.shared.report(message)
        }
    }

    private func validate(data: Data?,
                          response: HTTPURLResponse?,
                          error: Error?) -> Result<AniListGraphQLResult, AniListRequestError> {
        if let error = error as NSError?, error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            return .failure(.cancelled)
        }
        if let error { return .failure(.network(error)) }
        let status = response?.statusCode ?? 200
        let isOK = status >= 200 && status < 300
        let retryAfter = response.flatMap { retryAfter(from: $0) }
        guard let data, !data.isEmpty else {
            return .failure(isOK ? .emptyData : .httpStatus(status, retryAfter: retryAfter))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(isOK ? .invalidJSON : .httpStatus(status, retryAfter: retryAfter))
        }
        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.compactMap { $0["message"] as? String }
            let graphQLErrors = messages.isEmpty ? ["Unknown GraphQL error"] : messages
            if isOK, hasUsableGraphQLData(json) {
                return .success(AniListGraphQLResult(data: data,
                                                     json: json,
                                                     response: response,
                                                     graphQLErrors: graphQLErrors))
            }
            return .failure(isOK ? .graphQLErrors(graphQLErrors)
                                 : .graphQLHTTP(graphQLErrors, status: status, retryAfter: retryAfter))
        }
        if !isOK, json["data"] == nil {
            return .failure(.httpStatus(status, retryAfter: retryAfter))
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
                               retry: RetryState,
                               error: AniListRequestError) {
        let (delay, next) = nextRetry(after: error, state: retry)
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
                         retry: next)
        }
    }

    private func scheduleRetry(request: URLRequest,
                               key: String,
                               retry: RetryState,
                               error: AniListRequestError) {
        let (delay, next) = nextRetry(after: error, state: retry)
        retryQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if self.hasOnlyCancelledCallbacks(for: key) {
                self.finish(key: key, result: .failure(.cancelled))
                return
            }
            self.perform(request, key: key, retry: next)
        }
    }

    /// urql-client.ts `retryIf`: everything but a `validation` error is retried, forever. What
    /// cannot be retried at all (nothing was sent, or the token is bad) is not an urql result.
    private func shouldRetry(_ error: AniListRequestError) -> Bool {
        switch error {
        case .cancelled, .encodingFailed, .invalidEndpoint, .unauthenticated:
            return false
        default:
            return !error.isInvalidToken && !error.isValidation
        }
    }

    /// authExchange `didAuthError`: a response that says "Invalid token", once per request.
    private func needsReauthentication(_ result: Result<AniListGraphQLResult, AniListRequestError>,
                                       retry: RetryState) -> Bool {
        guard !retry.reauthenticated, TrackerAccountManager.shared.token(for: .anilist) != nil else { return false }
        switch result {
        case .failure(let error): return error.isInvalidToken
        case .success(let response): return response.hasInvalidTokenError
        }
    }

    /// `refreshAuth`: the authorization runs again, then the request goes out with the new token.
    private func reauthenticate(key: String,
                                result: Result<AniListGraphQLResult, AniListRequestError>,
                                resume: @escaping () -> Void) {
        AniListReauth.shared.refresh { [weak self] refreshed in
            guard let self else { return }
            if refreshed, !self.hasOnlyCancelledCallbacks(for: key) {
                resume()
            } else {
                self.clearAuthIfNeeded(for: result)
                self.finish(key: key, result: result)
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

    /// retry.ts: a rate limit waits for `retry-after` (plus a second) or the shared eleven seconds
    /// and starts counting again; anything else waits `count * 100ms` up to 60s
    /// (`initialDelayMs: 100, maxDelayMs: 60_000, randomDelay: false`), or the rate limit's
    /// delay again once there has been one.
    private func nextRetry(after error: AniListRequestError, state: RetryState) -> (TimeInterval, RetryState) {
        if error.isRateLimit {
            let delay = error.retryAfterHeader.map { $0 + 1 } ?? initialRetryDelay()
            var limited = state
            limited.count = 0
            limited.delay = delay
            limited.isRateLimit = true
            return (delay, limited)
        }
        var next = state
        next.count += 1
        var delay = next.delay ?? 0.1
        if !next.isRateLimit { delay = min(Double(next.count) * 0.1, 60) }
        next.delay = delay
        return (delay, next)
    }

    /// retry.ts `getInitialRetryDelay`
    private func initialRetryDelay() -> TimeInterval {
        lockQueue.sync {
            let now = Date()
            let sinceLastRetry = now.timeIntervalSince(lastRetryTime)
            if sinceLastRetry < 11 { return 11 - sinceLastRetry }
            lastRetryTime = now
            return 11
        }
    }

    /// `parseInt(headers.get('retry-after'))`
    private func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return Int(header.trimmingCharacters(in: .whitespaces).prefix(while: { $0.isNumber })).map { TimeInterval($0) }
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
