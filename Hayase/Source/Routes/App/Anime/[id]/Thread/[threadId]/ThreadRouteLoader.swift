//
//  ThreadRouteLoader.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/routes/app/anime/[id]/thread/[threadId]/+layout.ts
//

import Foundation

// MARK: - ThreadRouteLoader

/// The thread route's `load`: `asyncStore(Thread, { threadId }, { requestPolicy: 'cache-and-network' })`.
enum ThreadRouteLoader {
    /// What the cache has is the thread of the page at once.
    static func cached(threadID: Int) -> AniListThread? {
        Router.shared.cachedThread(for: threadID)
    }

    /// What the network answers; the cache keeps it too.
    static func load(threadID: Int, completion: @escaping (Result<AniListThread?, AniListRequestError>) -> Void) {
        AniListForumClient.shared.threadResult(threadID: threadID) { result in
            if case .success(let answered) = result, let thread = answered {
                Router.shared.cacheThread(thread)
            }
            completion(result)
        }
    }
}
