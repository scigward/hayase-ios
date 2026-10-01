//
//  AniListOfflineQueue.swift
//  Hayase
//
//  Mirrors: interface lib/modules/anilist/exchanges/offline.ts (`failedQueue`, persisted with
//  `writeMetadata` and replayed by `flushQueue` when the device is back online).
//

import Foundation

final class AniListOfflineQueue {
    static let shared = AniListOfflineQueue()

    private let defaultsKey = "anilistOfflineMutations"
    private let lock = NSLock()
    private var queue: [[String: Any]]
    private var isFlushing = false

    private init() {
        queue = UserDefaults.standard.array(forKey: defaultsKey) as? [[String: Any]] ?? []
        NotificationCenter.default.addObserver(self, selector: #selector(flush),
                                               name: AniListConnectionStatus.didComeOnline, object: nil)
        // `storage.readData()` hydrates the failed mutations, then `flushQueue()`
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    /// `isOfflineError`: a network error without a response while the device is offline. A mutation
    /// that fails like that is kept here instead of being retried.
    static func isOfflineError(_ error: AniListRequestError) -> Bool {
        if case .network = error { return !AniListConnectionStatus.shared.isOnline }
        return false
    }

    func enqueue(query: String, variables: [String: Any]) {
        lock.lock()
        queue.append(["query": query, "variables": variables])
        UserDefaults.standard.set(queue, forKey: defaultsKey)
        lock.unlock()
    }

    @objc func flush() {
        lock.lock()
        guard !isFlushing, !queue.isEmpty, AniListConnectionStatus.shared.isOnline,
              TrackerAccountManager.shared.token(for: .anilist) != nil else {
            lock.unlock()
            return
        }
        isFlushing = true
        lock.unlock()
        sendNext()
    }

    private func sendNext() {
        lock.lock()
        guard let next = queue.first,
              let query = next["query"] as? String,
              let variables = next["variables"] as? [String: Any],
              let token = TrackerAccountManager.shared.token(for: .anilist),
              let url = URL(string: "https://graphql.anilist.co") else {
            isFlushing = false
            lock.unlock()
            return
        }
        lock.unlock()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        AniListRequestExecutor.shared.perform(request, context: "AniListOfflineQueue", optimistic: true) { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result, AniListOfflineQueue.isOfflineError(error) {
                // still offline: it stays queued for the next `online`
                self.lock.lock()
                self.isFlushing = false
                self.lock.unlock()
                return
            }
            self.lock.lock()
            if !self.queue.isEmpty { self.queue.removeFirst() }
            UserDefaults.standard.set(self.queue, forKey: self.defaultsKey)
            let done = self.queue.isEmpty
            self.lock.unlock()
            if done {
                self.lock.lock()
                self.isFlushing = false
                self.lock.unlock()
                // the optimistic entries get their real ids
                DispatchQueue.main.async {
                    AniListTracking.shared.fetchUserLists(forceRefresh: true) { _ in }
                    NotificationCenter.default.post(name: LocalTracking.didChange, object: nil)
                }
            } else {
                self.sendNext()
            }
        }
    }
}
