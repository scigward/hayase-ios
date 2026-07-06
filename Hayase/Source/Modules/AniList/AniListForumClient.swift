//
//  AniListForumClient.swift
//  Hayase
//
//  AniList forum API surface.
//  Mirrors: client.ts thread/comment/like methods.
//

import Foundation

final class AniListForumClient {
    static let shared = AniListForumClient()

    private let requestExecutor = AniListRequestExecutor.shared
    private let queue = DispatchQueue(label: "com.hayase.anilist.forums")
    private var commentPageCache: [String: AniListCommentPage] = [:]

    private init() {}

    func threadDetailResult(threadID: Int,
                            page: Int = 1,
                            completion: @escaping (Result<AniListThreadDetailPayload, AniListRequestError>) -> Void) {
        var threadResult: Result<AniListThread?, AniListRequestError>?
        var commentsResult: Result<AniListCommentPage, AniListRequestError>?

        func finishIfReady() {
            guard let threadResult, let commentsResult else { return }
            switch (threadResult, commentsResult) {
            case (.success(let thread), .success(let comments)):
                completion(.success(AniListThreadDetailPayload(thread: thread, comments: comments)))
            case (.failure(let error), _), (_, .failure(let error)):
                completion(.failure(error))
            }
        }

        threadResult(threadID: threadID) { result in
            threadResult = result
            finishIfReady()
        }
        commentsResult(threadID: threadID, page: page) { result in
            commentsResult = result
            finishIfReady()
        }
    }

    @discardableResult
    func threadResult(threadID: Int,
                      completion: @escaping (Result<AniListThread?, AniListRequestError>) -> Void) -> AniListRequestToken {
        return requestExecutor.execute(query: AniListQueries.thread,
                                       variables: ["threadId": threadID],
                                       authorized: true,
                                       dedupeKey: "thread|\(threadID)") { result in
            switch result {
            case .success(let graphQLResult):
                let thread = ((graphQLResult.json["data"] as? [String: Any])?["Thread"] as? [String: Any])
                    .flatMap { AniListThread(dict: $0) }
                DispatchQueue.main.async { completion(.success(thread)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    @discardableResult
    func commentsResult(threadID: Int,
                        page: Int = 1,
                        completion: @escaping (Result<AniListCommentPage, AniListRequestError>) -> Void) -> AniListRequestToken? {
        let key = "comments|\(threadID)|\(page)"
        if let cached = queue.sync(execute: { commentPageCache[key] }) {
            DispatchQueue.main.async { completion(.success(cached)) }
        }

        return requestExecutor.execute(query: AniListQueries.comments,
                                       variables: ["threadId": threadID, "page": page],
                                       authorized: true,
                                       dedupeKey: key) { [weak self] result in
            switch result {
            case .success(let graphQLResult):
                guard let pageObject = (graphQLResult.json["data"] as? [String: Any])?["Page"] as? [String: Any] else {
                    DispatchQueue.main.async { completion(.failure(.emptyData)) }
                    return
                }
                let pageInfo = pageObject["pageInfo"] as? [String: Any]
                let comments = (pageObject["threadComments"] as? [[String: Any]] ?? [])
                    .compactMap { AniListThreadComment(dict: $0) }
                let page = AniListCommentPage(
                    comments: comments,
                    hasNextPage: pageInfo?["hasNextPage"] as? Bool ?? false,
                    total: pageInfo?["total"] as? Int ?? comments.count)
                self?.queue.async { [weak self] in
                    self?.commentPageCache[key] = page
                }
                DispatchQueue.main.async { completion(.success(page)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func toggleLikeResult(id: Int,
                          type: String,
                          wasLiked: Bool,
                          completion: @escaping (Result<(isLiked: Bool, likeCount: Int), AniListRequestError>) -> Void) {
        requestExecutor.execute(query: AniListQueries.toggleLike,
                                variables: ["id": id, "type": type],
                                authorized: true,
                                dedupeKey: "toggleLike|\(type)|\(id)|\(wasLiked)") { result in
            switch result {
            case .success(let graphQLResult):
                guard let payload = (graphQLResult.json["data"] as? [String: Any])?["ToggleLikeV2"] as? [String: Any] else {
                    DispatchQueue.main.async { completion(.failure(.emptyData)) }
                    return
                }
                let isLiked = payload["isLiked"] as? Bool ?? !wasLiked
                let likeCount = payload["likeCount"] as? Int ?? 0
                DispatchQueue.main.async { completion(.success((isLiked, likeCount))) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func commentResult(id: Int? = nil,
                       threadID: Int? = nil,
                       parentCommentID: Int? = nil,
                       comment: String,
                       rootCommentID: Int? = nil,
                       completion: @escaping (Result<AniListThreadComment, AniListRequestError>) -> Void) {
        var variables: [String: Any] = ["comment": comment]
        if let id { variables["id"] = id }
        if let threadID { variables["threadId"] = threadID }
        if let parentCommentID { variables["parentCommentId"] = parentCommentID }

        requestExecutor.execute(query: AniListQueries.saveThreadComment,
                                variables: variables,
                                authorized: true,
                                dedupeKey: "saveComment|\(id ?? 0)|\(threadID ?? 0)|\(parentCommentID ?? 0)") { [weak self] result in
            switch result {
            case .success(let graphQLResult):
                guard let payload = (graphQLResult.json["data"] as? [String: Any])?["SaveThreadComment"] as? [String: Any],
                      let comment = AniListThreadComment(dict: payload) else {
                    DispatchQueue.main.async { completion(.failure(.emptyData)) }
                    return
                }
                self?.invalidateComments(rootCommentID ?? threadID)
                DispatchQueue.main.async { completion(.success(comment)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func deleteCommentResult(id: Int,
                             rootCommentID: Int,
                             completion: @escaping (Result<Bool, AniListRequestError>) -> Void) {
        requestExecutor.execute(query: AniListQueries.deleteThreadComment,
                                variables: ["id": id],
                                authorized: true,
                                dedupeKey: "deleteComment|\(id)") { [weak self] result in
            switch result {
            case .success(let graphQLResult):
                let deleted = ((graphQLResult.json["data"] as? [String: Any])?["DeleteThreadComment"] as? [String: Any])?["deleted"] as? Bool ?? false
                self?.invalidateComments(rootCommentID)
                DispatchQueue.main.async { completion(.success(deleted)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func invalidateComments(_ rootID: Int?) {
        guard let rootID else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.commentPageCache = self.commentPageCache.filter {
                !$0.key.hasPrefix("comments|\(rootID)|")
            }
        }
    }
}
