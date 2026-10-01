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
    /// `coverImage.medium` with `/small/` turned into `/medium/` (util.ts `coverMedium`)
    var coverMediumURL: String? = nil
    var malId: Int? = nil
    var isFavourite: Bool? = nil
    var relations: [AnimeRelation] = []
    var tags: [AnimeTag] = []
    var isAdult: Bool? = nil
    var source: String? = nil
    var countryOfOrigin: String? = nil
    var studioNames: [String] = []
    var airedSchedule: [AiringEpisode] = []
    var notYetAiredSchedule: [AiringEpisode] = []

    struct AiringEpisode {
        let airingAt: Int?
        let episode: Int
    }
    /// Exact AniList FullMedia-shaped object passed to torrent extensions.
    /// Keep this private to extension calls; UI should continue using typed fields above.
    var extensionMediaJSON: [String: Any]? = nil

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


// MARK: - AnimeItem payload quality

extension AnimeItem {
    /// Route-ready media mirrors the interface IDMedia route payload.
    /// Partial card/search payloads must not be used to render /app/anime/:id.
    var isRouteReadyMediaPayload: Bool {
        isAdult != nil
            && (!genres.isEmpty || !tags.isEmpty || !relations.isEmpty || bannerURL != nil || description != nil)
    }

    func mergingRouteMedia(_ newer: AnimeItem) -> AnimeItem {
        guard newer.id == id else { return self }
        var merged = newer

        if merged.relations.isEmpty { merged.relations = relations }
        if merged.tags.isEmpty { merged.tags = tags }
        if merged.mediaListEntry == nil { merged.mediaListEntry = mediaListEntry }
        if merged.airedSchedule.isEmpty { merged.airedSchedule = airedSchedule }
        if merged.notYetAiredSchedule.isEmpty { merged.notYetAiredSchedule = notYetAiredSchedule }
        if merged.isFavourite == nil { merged.isFavourite = isFavourite }
        if merged.trailerYouTubeID == nil { merged.trailerYouTubeID = trailerYouTubeID }
        if merged.malId == nil { merged.malId = malId }

        return merged
    }
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
    let sourceID: Int?

    init(relationType: String, media: AnimeItem, sourceID: Int? = nil) {
        self.relationType = relationType
        self.media = media
        self.sourceID = sourceID
    }
}

struct AnimeRelationGraphEdge {
    let id: String
    let sourceID: Int
    let targetID: Int
    let relationType: String
}

struct AnimeRelationGraph {
    var nodes: [Int: AnimeItem]
    var edges: [String: AnimeRelationGraphEdge]
    var boundaryIDs: Set<Int> = []
    var expandedIDs: Set<Int> = []

    var visibleRelations: [AnimeRelation] {
        edges.values
            .sorted { lhs, rhs in
                if lhs.sourceID != rhs.sourceID { return lhs.sourceID < rhs.sourceID }
                return lhs.targetID < rhs.targetID
            }
            .compactMap { edge in
                guard let item = nodes[edge.targetID] else { return nil }
                return AnimeRelation(relationType: edge.relationType, media: item, sourceID: edge.sourceID)
            }
    }
}

// MARK: - HomeSectionData

struct AniListHomeSectionDefinition {
    let id: String
    let title: String
    let variables: [String: Any]
    let startsPaused: Bool
}

enum HomeSectionContentState {
    case idle
    case paused
    case fetching
    case loaded
    case empty
    case failed(String)

    var showsPlaceholderItems: Bool {
        switch self {
        case .idle, .paused, .fetching:
            return true
        case .loaded, .empty, .failed:
            return false
        }
    }

    var message: String? {
        switch self {
        case .empty:
            return "Looks like there's nothing here."
        case .failed(let message):
            return message
        case .idle, .paused, .fetching, .loaded:
            return nil
        }
    }
}

struct HomeSectionData {
    let title: String
    var items: [AnimeItem]
    var queryID: String? = nil
    var contentState: HomeSectionContentState = .loaded
    var filterGenre: String? = nil
    var filterSort: String? = nil
    var filterIDs: [Int]? = nil
    var filterStatus: [String]? = nil
    var filterOnList: Bool? = nil
    var filterSeason: String? = nil
    var filterYear: String? = nil
    var filterFormats: [String] = []
}

struct AniListSearchPage {
    let items: [AnimeItem]
    let hasNextPage: Bool
    let isCacheResult: Bool

    init(items: [AnimeItem], hasNextPage: Bool, isCacheResult: Bool = false) {
        self.items = items
        self.hasNextPage = hasNextPage
        self.isCacheResult = isCacheResult
    }
}

// MARK: - AniList user summary

struct AniListUserSummary {
    let id: Int
    let name: String
    let avatarURL: String?
    let bannerURL: String?
    let about: String?
    let isFollowing: Bool
    let isFollower: Bool
    let donatorBadge: String?
    let profileColor: String?
    let createdAt: TimeInterval
    let animeCount: Int
    let episodesWatched: Int
    let minutesWatched: Int

    init(id: Int,
         name: String,
         avatarURL: String?,
         bannerURL: String? = nil,
         about: String? = nil,
         isFollowing: Bool = false,
         isFollower: Bool = false,
         donatorBadge: String? = nil,
         profileColor: String? = nil,
         createdAt: TimeInterval = 0,
         animeCount: Int = 0,
         episodesWatched: Int = 0,
         minutesWatched: Int = 0) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.bannerURL = bannerURL
        self.about = about
        self.isFollowing = isFollowing
        self.isFollower = isFollower
        self.donatorBadge = donatorBadge
        self.profileColor = profileColor
        self.createdAt = createdAt
        self.animeCount = animeCount
        self.episodesWatched = episodesWatched
        self.minutesWatched = minutesWatched
    }
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
    let relationGraph: AnimeRelationGraph?
}

struct AnimeTrailerGenresPayload {
    let trailerYouTubeID: String?
    let genres: [String]
    let malId: Int?
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
    let body: String?
    let userID: Int?
    let viewCount: Int
    let replyCount: Int
    var likeCount: Int
    let isLocked: Bool
    let isSubscribed: Bool?
    var isLiked: Bool?
    let createdAt: TimeInterval
    let user: AniListUserSummary?
    let userName: String?
    let avatarURL: String?
    let categories: [String]

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? Int else { return nil }
        self.id = id
        self.title = dict["title"] as? String ?? "Thread \(id)"
        self.body = dict["body"] as? String
        self.userID = dict["userId"] as? Int
        self.viewCount = dict["viewCount"] as? Int ?? 0
        self.replyCount = dict["replyCount"] as? Int ?? 0
        self.likeCount = dict["likeCount"] as? Int ?? 0
        self.isLocked = dict["isLocked"] as? Bool ?? false
        self.isSubscribed = dict["isSubscribed"] as? Bool
        self.isLiked = dict["isLiked"] as? Bool
        let createdAt = (dict["createdAt"] as? NSNumber)?.doubleValue ?? dict["createdAt"] as? TimeInterval
        self.createdAt = createdAt ?? 0
        let user = dict["user"] as? [String: Any]
        self.user = user.flatMap { AniListUserSummary(dict: $0) }
        self.userName = user?["name"] as? String
        let avatar = user?["avatar"] as? [String: Any]
        self.avatarURL = avatar?["large"] as? String
        let cats = dict["categories"] as? [[String: Any]] ?? []
        self.categories = cats.compactMap { $0["name"] as? String }.filter { $0 != "Anime" }
    }

    var sinceString: String {
        AniListUtil.since(Date(timeIntervalSince1970: createdAt))
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
    let isFavourite: Bool?
    let favourites: Int?
    let trailer: Trailer?
    let seasonYear: Int?
    let season: String?
    let format: String?
    let synonyms: [String]?
    struct StartDate: Codable { let year: Int?; let month: Int?; let day: Int? }
    let startDate: StartDate?
    let source: String?
    let countryOfOrigin: String?
    struct StudioConnection: Codable {
        let nodes: [Studio]?
        struct Studio: Codable { let id: Int?; let name: String? }
    }
    let studios: StudioConnection?
    let relations: RelationConnection?
    let aired: AiringConnection?
    let notaired: AiringConnection?
    struct AiringConnection: Codable {
        let n: [AiringNode]?
        struct AiringNode: Codable { let a: Int?; let e: Int? }
    }
    struct RelationConnection: Codable { let edges: [RelationEdge]? }
    struct RelationEdge: Codable {
        let relationType: String?
        let node: RelationNode?
    }
    struct RelationNode: Codable {
        let id: Int?
        let title: Title?
        let coverImage: CoverImage?
        let type: String?
        let averageScore: Float?
        let episodes: Int?
        let status: String?
        let seasonYear: Int?
        let season: String?
        let format: String?
        let synonyms: [String]?
        let relations: RelationConnection?
        let startDate: StartDate?
        let endDate: StartDate?
    }
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
        let id: Int?
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
        let customLists: [CustomList]?

        struct CustomList: Codable {
            let enabled: Bool?
            let name: String?
        }

        enum CodingKeys: String, CodingKey {
            case id
            case status
            case progress
            case repeatCount = "repeat"
            case score
            case customLists
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(Int.self, forKey: .id)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            progress = try container.decodeIfPresent(Int.self, forKey: .progress)
            repeatCount = try container.decodeIfPresent(Int.self, forKey: .repeatCount)
            score = try container.decodeIfPresent(Double.self, forKey: .score)
            if let objectLists = try? container.decodeIfPresent([CustomList].self, forKey: .customLists) {
                customLists = objectLists
            } else if let nameLists = try? container.decodeIfPresent([String].self, forKey: .customLists) {
                customLists = nameLists.map { CustomList(enabled: true, name: $0) }
            } else {
                customLists = nil
            }
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
        let type: String?
        let averageScore: Float?
        let episodes: Int?
        let status: String?
        let seasonYear: Int?
        let season: String?
        let format: String?
        struct RelTitle: Codable { let userPreferred: String?; let romaji: String?; let english: String?; let native: String? }
        struct RelCover: Codable { let extraLarge: String?; let large: String?; let medium: String?; let color: String? }
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
        let tags: [AniListMedia.MediaTag]?
        let isAdult: Bool?
        let isFavourite: Bool?
        let source: String?
        let countryOfOrigin: String?
        let studios: AniListMedia.StudioConnection?
        let mediaListEntry: AniListMedia.MediaListEntry?
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
        let type: String?
        let averageScore: Float?
        let episodes: Int?
        let status: String?
        let seasonYear: Int?
        let season: String?
        let format: String?
        let synonyms: [String]?
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
        struct AiringTitle: Codable { let english: String?; let romaji: String?; let native: String?; let userPreferred: String? }
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
                struct PPTitle: Codable { let english: String?; let romaji: String?; let native: String?; let userPreferred: String? }
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
