//
//  Types.swift
//  Hayase
//
//  AniList type definitions.
//  Mirrors: src/lib/modules/anilist/types.d.ts
//

import Foundation

// MARK: - AnimeItem (FullMedia equivalent)

struct AnimeItem {
    let id: Int
    let titleEnglish: String?
    let titleRomaji: String?
    var titleNative: String? = nil
    var titleUserPreferred: String? = nil
    let coverURL: String?
    let score: Float?
    let status: String?
    let episodes: Int?
    let bannerURL: String?
    let genres: [String]
    let description: String?
    var synonyms: [String] = []
    var year: Int? = nil
    var startYear: Int? = nil
    var season: String? = nil
    var format: String? = nil
    var duration: Int? = nil
    var trailerYouTubeID: String? = nil
    var favourites: Int? = nil
    var coverColor: String? = nil
    var malId: Int? = nil
    var relations: [AnimeRelation] = []
    var tags: [AnimeTag] = []
    var isAdult: Bool? = nil

    struct MediaListEntry {
        let listID: Int
        let status: String?
        let progress: Int
        let score: Int
        let repeatCount: Int
        let customLists: [String]
    }
    var mediaListEntry: MediaListEntry?
}

// MARK: - AnimeTag

struct AnimeTag {
    let id: Int
    let name: String
    let isMediaSpoiler: Bool
    let isGeneralSpoiler: Bool
    let rank: Int
    let isAdult: Bool
}

// MARK: - AnimeRelation

struct AnimeRelation {
    let relationType: String
    let media: AnimeItem
}

// MARK: - HomeSectionData

struct HomeSectionData {
    let title: String
    var items: [AnimeItem]
    var filterGenre: String? = nil
    var filterSort: String? = nil
}

// MARK: - AniList user summary

struct AniListUserSummary {
    let id: Int
    let name: String
    let avatarURL: String?
}

struct AniListFollowingEntry {
    let user: AniListUserSummary
    let progress: Int
}

struct AnimePagePayload {
    let media: AnimeItem?
    let recommendations: [AnimeItem]
    let threads: [AniListThread]
    let threadTotal: Int
    let followingEntries: [AniListFollowingEntry]
}

// MARK: - Staff + Stats models

struct AnimeStaffMember {
    let name: String
    let imageURL: String?
    let role: String
}

struct AnimeScorePoint {
    let score: Int
    let amount: Int
}

struct AnimeStatusCount {
    let status: String
    let amount: Int
}

// MARK: - Airing schedule

struct AiringScheduleEntry {
    let episode: Int
    let airingAt: Date
    let media: AnimeItem
}

// MARK: - Forum thread model

struct AniListThread {
    let id: Int
    let title: String
    let viewCount: Int
    let replyCount: Int
    let likeCount: Int
    let isLocked: Bool
    let createdAt: TimeInterval
    let userName: String?
    let avatarURL: String?
    let categories: [String]

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? Int else { return nil }
        self.id = id
        self.title = dict["title"] as? String ?? "Thread \(id)"
        self.viewCount = dict["viewCount"] as? Int ?? 0
        self.replyCount = dict["replyCount"] as? Int ?? 0
        self.likeCount = dict["likeCount"] as? Int ?? 0
        self.isLocked = dict["isLocked"] as? Bool ?? false
        self.createdAt = dict["createdAt"] as? TimeInterval ?? 0
        let user = dict["user"] as? [String: Any]
        self.userName = user?["name"] as? String
        let avatar = user?["avatar"] as? [String: Any]
        self.avatarURL = avatar?["large"] as? String
        let cats = dict["categories"] as? [[String: Any]] ?? []
        self.categories = cats.compactMap { $0["name"] as? String }.filter { $0 != "Anime" }
    }

    var sinceString: String {
        let diff = Date().timeIntervalSince1970 - createdAt
        switch diff {
        case ..<60:        return "just now"
        case ..<3600:      return "\(Int(diff/60))m ago"
        case ..<86400:     return "\(Int(diff/3600))h ago"
        case ..<2592000:   return "\(Int(diff/86400))d ago"
        default:           return "\(Int(diff/2592000))mo ago"
        }
    }
}

// MARK: - Codable response types (internal to AniList module)

struct AniListResponse: Codable {
    let data: AniListData?
    struct AniListData: Codable {
        let Page: AniListPage?
        struct AniListPage: Codable {
            let pageInfo: PageInfo?
            let media: [AniListMedia]?
            struct PageInfo: Codable {
                let hasNextPage: Bool?
            }
        }
    }
}

struct AniListMedia: Codable {
    let id: Int?
    let idMal: Int?
    let title: Title?
    let coverImage: CoverImage?
    let bannerImage: String?
    let averageScore: Float?
    let popularity: Int?
    let episodes: Int?
    let duration: Int?
    let description: String?
    let nextAiringEpisode: NextAiringEpisode?
    let status: String?
    let genres: [String]?
    let tags: [MediaTag]?
    let isAdult: Bool?
    let favourites: Int?
    let trailer: Trailer?
    let seasonYear: Int?
    let season: String?
    let format: String?
    let synonyms: [String]?
    struct StartDate: Codable { let year: Int? }
    let startDate: StartDate?
    struct Title: Codable {
        let english: String?
        let romaji: String?
        let native: String?
        let userPreferred: String?
    }
    struct CoverImage: Codable {
        let extraLarge: String?
        let large: String?
        let medium: String?
        let color: String?
    }
    struct NextAiringEpisode: Codable {
        let episode: Int?
        let timeUntilAiring: Int?
    }
    struct Trailer: Codable {
        let id: String?
        let site: String?
    }
    struct MediaListEntry: Codable {
        let id: Int?
        let status: String?
        let progress: Int?
        let repeatCount: Int?
        let score: Double?

        enum CodingKeys: String, CodingKey {
            case id
            case status
            case progress
            case repeatCount = "repeat"
            case score
        }
    }
    let mediaListEntry: MediaListEntry?
    struct MediaTag: Codable {
        let id: Int?
        let name: String?
        let isMediaSpoiler: Bool?
        let isGeneralSpoiler: Bool?
        let rank: Int?
        let isAdult: Bool?
    }
}

struct AniListDetailResponse: Codable {
    let data: DetailData?
    struct DetailData: Codable { let Media: DetailMedia? }
    struct DetailMedia: Codable { let relations: RelationConnection? }
    struct RelationConnection: Codable { let edges: [RelationEdge]? }
    struct RelationEdge: Codable {
        let relationType: String?
        let node: RelationNode?
    }
    struct RelationNode: Codable {
        let id: Int?
        let title: RelTitle?
        let coverImage: RelCover?
        let averageScore: Float?
        let episodes: Int?
        let status: String?
        let seasonYear: Int?
        let season: String?
        let format: String?
        struct RelTitle: Codable { let english: String?; let romaji: String? }
        struct RelCover: Codable { let large: String?; let color: String? }
    }
}

struct AniListResolverMediaResponse: Codable {
    let data: ResolverData?
    struct ResolverData: Codable { let Media: ResolverMedia? }
    struct ResolverMedia: Codable {
        let id: Int?
        let idMal: Int?
        let title: AniListMedia.Title?
        let coverImage: AniListMedia.CoverImage?
        let bannerImage: String?
        let averageScore: Float?
        let episodes: Int?
        let duration: Int?
        let description: String?
        let status: String?
        let genres: [String]?
        let favourites: Int?
        let trailer: AniListMedia.Trailer?
        let seasonYear: Int?
        let season: String?
        let format: String?
        let synonyms: [String]?
        let startDate: AniListMedia.StartDate?
        let relations: ResolverRelationConnection?
    }
    struct ResolverRelationConnection: Codable { let edges: [ResolverRelationEdge]? }
    struct ResolverRelationEdge: Codable {
        let relationType: String?
        let node: ResolverRelationNode?
    }
    struct ResolverRelationNode: Codable {
        let id: Int?
        let title: AniListMedia.Title?
        let coverImage: AniListMedia.CoverImage?
        let averageScore: Float?
        let episodes: Int?
        let status: String?
        let seasonYear: Int?
        let season: String?
        let format: String?
    }
}

struct AiringScheduleResponse: Codable {
    let data: AiringData?
    struct AiringData: Codable { let Page: AiringPage? }
    struct AiringPage: Codable { let airingSchedules: [AiringSchedule]? }
    struct AiringSchedule: Codable {
        let episode: Int?
        let airingAt: Int?
        let media: AiringMedia?
    }
    struct AiringMedia: Codable {
        let id: Int?
        let title: AiringTitle?
        let coverImage: AiringCover?
        let averageScore: Float?
        let episodes: Int?
        let status: String?
        struct AiringTitle: Codable { let english: String?; let romaji: String? }
        struct AiringCover: Codable { let large: String?; let color: String? }
    }
}

struct AiringSchedulePagedResponse: Codable {
    let data: PPData?
    struct PPData: Codable { let Page: PPPage? }
    struct PPPage: Codable {
        let pageInfo: PPPageInfo?
        let airingSchedules: [PPSchedule]?
        struct PPPageInfo: Codable { let hasNextPage: Bool? }
        struct PPSchedule: Codable {
            let episode: Int?
            let airingAt: Int?
            let media: PPMedia?
            struct PPMedia: Codable {
                let id: Int?
                let title: PPTitle?
                let coverImage: PPCover?
                let averageScore: Float?
                let episodes: Int?
                let status: String?
                struct PPTitle: Codable { let english: String?; let romaji: String? }
                struct PPCover: Codable { let large: String?; let color: String? }
            }
        }
    }
}

struct StaffStatsResponse: Codable {
    let data: SSData?
    struct SSData: Codable { let Media: SSMedia? }
    struct SSMedia: Codable {
        let staff: StaffConn?
        let stats: MediaStats?
    }
    struct StaffConn: Codable { let edges: [StaffEdge]? }
    struct StaffEdge: Codable {
        let role: String?
        let node: StaffNode?
    }
    struct StaffNode: Codable {
        let name: StaffName?
        let image: StaffImage?
        struct StaffName: Codable { let full: String? }
        struct StaffImage: Codable { let medium: String? }
    }
    struct MediaStats: Codable {
        let scoreDistribution: [ScoreDist]?
        let statusDistribution: [StatusDist]?
        struct ScoreDist: Codable { let score: Int?; let amount: Int? }
        struct StatusDist: Codable { let status: String?; let amount: Int? }
    }
}

struct MediaScheduleResponse: Codable {
    let data: MSData?
    struct MSData: Codable { let Media: MSMedia? }
    struct MSMedia: Codable {
        let episodes: Int?
        let startDate: MSStartDate?
        let aired: MSSchedule?
        let notaired: MSSchedule?
    }
    struct MSStartDate: Codable {
        let year: Int?
        let month: Int?
        let day: Int?
    }
    struct MSSchedule: Codable { let n: [MSNode]? }
    struct MSNode: Codable {
        let a: Int?
        let e: Int?
    }
}

/// Result of fetching per-media airing schedule.
struct MediaScheduleResult {
    let schedule: [Int: Date]
    let startDate: (year: Int?, month: Int?, day: Int?)?
    let episodeCount: Int?
}
