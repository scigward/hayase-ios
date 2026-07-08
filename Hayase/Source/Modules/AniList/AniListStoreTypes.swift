//
//  AniListStoreTypes.swift
//  Hayase
//
//  Shared AniList store payloads.
//  Mirrors: src/lib/modules/anilist/client.ts query-store payloads.
//

import Foundation

struct AniListSingleTitle {
    let id: Int
    let userPreferred: String?
}

struct AniListThreadComment {
    let id: Int
    let comment: String
    let isLiked: Bool?
    let likeCount: Int
    let createdAt: TimeInterval
    let user: AniListUserSummary?
    let childComments: Any?
    let childCommentItems: [AniListThreadComment]
    let isLocked: Bool

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? Int else { return nil }
        self.id = id
        self.comment = dict["comment"] as? String ?? ""
        self.isLiked = dict["isLiked"] as? Bool
        self.likeCount = dict["likeCount"] as? Int ?? 0
        if let number = dict["createdAt"] as? NSNumber {
            self.createdAt = number.doubleValue
        } else {
            self.createdAt = dict["createdAt"] as? TimeInterval ?? 0
        }
        self.user = (dict["user"] as? [String: Any]).flatMap { AniListUserSummary(dict: $0) }
        self.childComments = dict["childComments"]
        if let children = dict["childComments"] as? [[String: Any]] {
            self.childCommentItems = children.compactMap { AniListThreadComment(dict: $0) }
        } else if let children = dict["childComments"] as? [Any] {
            self.childCommentItems = children.compactMap { ($0 as? [String: Any]).flatMap(AniListThreadComment.init) }
        } else {
            self.childCommentItems = []
        }
        self.isLocked = dict["isLocked"] as? Bool ?? false
    }

    var sinceString: String {
        AniListUtil.since(Date(timeIntervalSince1970: createdAt))
    }
}

struct AniListCommentPage {
    let comments: [AniListThreadComment]
    let hasNextPage: Bool
    let total: Int
}

struct AniListThreadDetailPayload {
    let thread: AniListThread?
    let comments: AniListCommentPage
}

extension AniListUserSummary {
    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? Int,
              let name = dict["name"] as? String else { return nil }
        let avatar = dict["avatar"] as? [String: Any]
        let options = dict["options"] as? [String: Any]
        let statistics = dict["statistics"] as? [String: Any]
        let anime = statistics?["anime"] as? [String: Any]
        let createdAt: TimeInterval
        if let number = dict["createdAt"] as? NSNumber {
            createdAt = number.doubleValue
        } else {
            createdAt = dict["createdAt"] as? TimeInterval ?? 0
        }
        self.init(
            id: id,
            name: name,
            avatarURL: avatar?["large"] as? String,
            bannerURL: dict["bannerImage"] as? String,
            about: dict["about"] as? String,
            isFollowing: dict["isFollowing"] as? Bool ?? false,
            isFollower: dict["isFollower"] as? Bool ?? false,
            donatorBadge: dict["donatorBadge"] as? String,
            profileColor: options?["profileColor"] as? String,
            createdAt: createdAt,
            animeCount: anime?["count"] as? Int ?? 0,
            episodesWatched: anime?["episodesWatched"] as? Int ?? 0,
            minutesWatched: anime?["minutesWatched"] as? Int ?? 0)
    }
}
