//
//  Queries.swift
//  Hayase
//
//  AniList GraphQL query and mutation definitions.
//  Mirrors: src/lib/modules/anilist/queries.ts
//

import Foundation

// MARK: - Query constants

enum AniListQueries {

    // MARK: - Shared media selection

    /// Interface `FullMedia` fragment equivalent. Keep Search/Home/Banner/ID
    /// surfaces on the same media shape so native cache behavior stays aligned
    /// with `client.search(...)`.
    static let fullMediaFields = """
          id
          idMal
          title { romaji english native userPreferred }
          description(asHtml: false)
          season
          seasonYear
          format
          status
          episodes
          duration
          averageScore
          genres
          isFavourite
          coverImage { extraLarge medium color }
          source
          countryOfOrigin
          isAdult
          bannerImage
          synonyms
          nextAiringEpisode { id timeUntilAiring episode }
          startDate { year month day }
          trailer { id site }
          tags { id name isMediaSpoiler isGeneralSpoiler rank isAdult }
          mediaListEntry { id status progress repeat score(format: POINT_10) customLists(asArray: true) }
          studios(isMain: true) { nodes { id name } }
          notaired: airingSchedule(page: 1, perPage: 50, notYetAired: true) { n: nodes { a: airingAt e: episode } }
          aired: airingSchedule(page: 1, perPage: 50, notYetAired: false) { n: nodes { a: airingAt e: episode } }
          relations {
            edges {
              relationType(version: 2)
              node {
                id
                status
                format
                episodes
                title { userPreferred }
                coverImage { extraLarge }
                type
                synonyms
                season
                seasonYear
                relations {
                  edges {
                    relationType(version: 2)
                    node {
                      id
                      status
                      format
                      episodes
                      title { userPreferred }
                      type
                      coverImage { extraLarge }
                    }
                  }
                }
                startDate { year month day }
                endDate { year month day }
              }
            }
          }
    """

    static let userFields = """
          id
          bannerImage
          about
          isFollowing
          isFollower
          donatorBadge
          options { profileColor }
          createdAt
          name
          avatar { large }
          statistics {
            anime {
              count
              minutesWatched
              episodesWatched
              genres(limit: 3, sort: COUNT_DESC) { genre count }
            }
          }
    """

    static let threadFields = """
          id
          title
          body
          userId
          replyCount
          viewCount
          isLocked
          isSubscribed
          isLiked
          likeCount
          repliedAt
          createdAt
          user { \(userFields) }
          categories { id name }
    """

    static let scheduleMediaFields = """
          id
          coverImage { extraLarge large color }
          title { userPreferred romaji english native }
          mediaListEntry { status progress id }
          aired: airingSchedule(page: 1, perPage: 50, notYetAired: false) {
            n: nodes { a: airingAt e: episode }
          }
          notaired: airingSchedule(page: 1, perPage: 50, notYetAired: true) {
            n: nodes { a: airingAt e: episode }
          }
    """

    // MARK: - Airing anime (legacy CoreData flow)

    static let airingAnime = """
    query ($nsfw: [String]) {
      Page(page: 1, perPage: 50) {
        media(status: RELEASING, type: ANIME, format_not: MUSIC, sort: POPULARITY_DESC, genre_not_in: $nsfw) {
          id
          title { romaji english native userPreferred }
          coverImage { extraLarge large medium color }
          bannerImage
          averageScore
          popularity
          episodes
          duration
          description(asHtml: false)
          nextAiringEpisode { episode timeUntilAiring }
          status
          synonyms
        }
      }
    }
    """

    // MARK: - Search

    static let search = """
    query ($ids: [Int], $search: String, $genre: [String], $tag: [String], $format: [MediaFormat], $status: [MediaStatus], $statusNot: [MediaStatus], $season: MediaSeason, $seasonYear: Int, $isAdult: Boolean, $sort: [MediaSort], $onList: Boolean, $page: Int, $perPage: Int, $nsfw: [String]) {
      Page(page: $page, perPage: $perPage) {
        pageInfo { hasNextPage }
        media(type: ANIME, format_not: MUSIC, id_in: $ids, search: $search, genre_in: $genre, tag_in: $tag, format_in: $format, status_in: $status, status_not_in: $statusNot, season: $season, seasonYear: $seasonYear, isAdult: $isAdult, sort: $sort, onList: $onList, genre_not_in: $nsfw) {
          \(fullMediaFields)
        }
      }
    }
    """

    // MARK: - Legacy text search (CoreData flow)

    static let searchLegacy = """
    query ($search: String, $nsfw: [String]) {
      Page(page: 1, perPage: 50) {
        media(search: $search, type: ANIME, format_not: MUSIC, sort: POPULARITY_DESC, genre_not_in: $nsfw) {
          id
          title { romaji english native userPreferred }
          coverImage { extraLarge large medium color }
          bannerImage
          averageScore
          popularity
          episodes
          duration
          description(asHtml: false)
          nextAiringEpisode { episode timeUntilAiring }
          status
          synonyms
        }
      }
    }
    """

    // MARK: - Following many (full-banner.svelte)

    static let followingMany = """
    query FollowingMany($ids: [Int]!) {
      Page {
        mediaList(mediaId_in: $ids, isFollowing: true, sort: UPDATED_TIME_DESC) {
          id
          status
          score
          progress
          media { id }
          user {
            id
            name
            avatar { large }
          }
        }
      }
    }
    """

    // MARK: - ID-based fetch

    static let idIn = """
    query ($idIn: [Int], $nsfw: [String]) {
      Page(page: 1, perPage: 50) {
        media(type: ANIME, format_not: MUSIC, id_in: $idIn, genre_not_in: $nsfw) {
          \(fullMediaFields)
        }
      }
    }
    """

    static let idInFiltered = """
    query ($idIn: [Int], $status: [MediaStatus], $onList: Boolean, $sort: [MediaSort], $nsfw: [String]) {
      Page(page: 1, perPage: 50) {
        media(type: ANIME, format_not: MUSIC, id_in: $idIn, status_in: $status, onList: $onList, sort: $sort, genre_not_in: $nsfw) {
          \(fullMediaFields)
        }
      }
    }
    """

    static let byIds = """
    query ($ids: [Int], $nsfw: [String]) {
      Page(page: 1, perPage: 50) {
        media(type: ANIME, format_not: MUSIC, id_in: $ids, sort: POPULARITY_DESC, genre_not_in: $nsfw) {
          \(fullMediaFields)
        }
      }
    }
    """

    // MARK: - Detail (relations)

    static let detail = """
    query ($id: Int) {
      Media(id: $id, type: ANIME) {
        relations {
          edges {
            relationType(version: 2)
            node {
              id
              title { userPreferred romaji english native }
              coverImage { extraLarge large medium color }
              type
              averageScore
              episodes
              status
              seasonYear
              season
              format
            }
          }
        }
      }
    }
    """

    static let resolverMediaById = """
    query ($id: Int) {
      Media(id: $id, type: ANIME) {
        \(fullMediaFields)
      }
    }
    """

    // MARK: - Staff + Stats

    static let staffStats = """
    query ($id: Int) {
      Media(id: $id, type: ANIME) {
        staff(sort: [RELEVANCE], page: 1, perPage: 12) {
          edges {
            role
            node {
              name { full }
              image { medium }
            }
          }
        }
        stats {
          scoreDistribution { score amount }
          statusDistribution { status amount }
        }
      }
    }
    """

    // MARK: - Anime page (anime/[id]/+layout.svelte + +page.svelte)

    static let animePage = """
    query AnimePage($id: Int!) {
      Media(id: $id, type: ANIME) {
        \(fullMediaFields)
        recommendations(sort: [RATING_DESC, ID], perPage: 24) {
          nodes {
            id
            rating
            mediaRecommendation {
              \(fullMediaFields)
            }
          }
        }
      }
      following: Page {
        mediaList(mediaId: $id, isFollowing: true, sort: UPDATED_TIME_DESC) {
          id
          status
          score
          progress
          user { \(userFields) }
        }
      }
      threads: Page(perPage: 16) {
        pageInfo { hasNextPage total }
        threads(mediaCategoryId: $id, sort: ID_DESC) {
          \(threadFields)
        }
      }
    }
    """

    // MARK: - Recursive relations (ui/relations + client.relationsTree)

    static let recursiveRelations = """
    query RecrusiveRelations($ids: [Int]!) {
      Page {
        pageInfo { hasNextPage }
        media(id_in: $ids, type: ANIME) {
          id
          status
          format
          episodes
          title { userPreferred romaji english native }
          type
          coverImage { extraLarge medium color }
          season
          seasonYear
          relations {
            edges {
              relationType
              node {
                id
                status
                format
                episodes
                title { userPreferred romaji english native }
                type
                coverImage { extraLarge medium color }
                season
                seasonYear
                relations {
                  edges {
                    relationType
                    node {
                      id
                      status
                      format
                      episodes
                      title { userPreferred romaji english native }
                      type
                      coverImage { extraLarge medium color }
                      season
                      seasonYear
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    // MARK: - Trailer + Genres

    static let trailerGenres = """
    query($id:Int){Media(id:$id,type:ANIME){idMal genres trailer{id site}}}
    """

    // MARK: - Forum threads

    static let threads = """
    query Threads($id: Int!, $page: Int, $perPage: Int) {
      threads: Page(page: $page, perPage: $perPage) {
        pageInfo { hasNextPage total }
        threads(mediaCategoryId: $id, sort: ID_DESC) {
          \(threadFields)
        }
      }
    }
    """

    static let thread = """
    query Thread($threadId: Int!) {
      Thread(id: $threadId) {
        \(threadFields)
      }
    }
    """

    static let comments = """
    query Comments($threadId: Int, $page: Int) {
      Page(page: $page, perPage: 15) {
        pageInfo { hasNextPage total }
        threadComments(threadId: $threadId) {
          id
          comment
          isLiked
          likeCount
          createdAt
          user { \(userFields) }
          childComments
          isLocked
        }
      }
    }
    """

    static let toggleLike = """
    mutation ToggleLike($id: Int!, $type: LikeableType!) {
      ToggleLikeV2(id: $id, type: $type) {
        ... on Thread {
          id
          likeCount
          isLiked
        }
        ... on ThreadComment {
          id
          likeCount
          isLiked
        }
      }
    }
    """

    static let saveThreadComment = """
    mutation SaveThreadComment($id: Int, $threadId: Int, $parentCommentId: Int, $comment: String) {
      SaveThreadComment(id: $id, threadId: $threadId, parentCommentId: $parentCommentId, comment: $comment) {
        id
        comment
        isLiked
        likeCount
        createdAt
        user { \(userFields) }
        childComments
        isLocked
      }
    }
    """

    static let deleteThreadComment = """
    mutation DeleteThreadComment($id: Int) {
      DeleteThreadComment(id: $id) {
        deleted
      }
    }
    """

    static let idTitle = """
    query IDTitle($id: Int) {
      Media(id: $id) {
        id
        title { userPreferred }
      }
    }
    """

    static let updateUser = """
    mutation UpdateUser($lists: [String], $adult: Boolean, $language: UserTitleLanguage) {
      UpdateUser(animeListOptions: { customLists: $lists }, displayAdultContent: $adult, titleLanguage: $language) {
        id
        name
        avatar { large }
        bannerImage
        mediaListOptions { animeList { customLists } }
        options { titleLanguage displayAdultContent profileColor }
      }
    }
    """

    // MARK: - Airing schedule

    static let schedule = """
    query Schedule($seasonCurrent: MediaSeason, $seasonYearCurrent: Int, $seasonLast: MediaSeason, $seasonYearLast: Int, $seasonNext: MediaSeason, $seasonYearNext: Int, $onList: Boolean, $ids: [Int], $formatNot: MediaFormat, $nsfw: [String]) {
      curr1: Page(page: 1) {
        media(type: ANIME, season: $seasonCurrent, seasonYear: $seasonYearCurrent, format_not: $formatNot, onList: $onList, id_in: $ids, genre_not_in: $nsfw) {
          \(scheduleMediaFields)
        }
      }
      curr2: Page(page: 2) {
        media(type: ANIME, season: $seasonCurrent, seasonYear: $seasonYearCurrent, format_not: $formatNot, onList: $onList, id_in: $ids, genre_not_in: $nsfw) {
          \(scheduleMediaFields)
        }
      }
      curr3: Page(page: 3) {
        media(type: ANIME, season: $seasonCurrent, seasonYear: $seasonYearCurrent, format_not: $formatNot, onList: $onList, id_in: $ids, genre_not_in: $nsfw) {
          \(scheduleMediaFields)
        }
      }
      residue: Page(page: 1) {
        media(type: ANIME, season: $seasonLast, seasonYear: $seasonYearLast, episodes_greater: 11, format_not: $formatNot, onList: $onList, id_in: $ids, genre_not_in: $nsfw) {
          \(scheduleMediaFields)
        }
      }
      next1: Page(page: 1) {
        media(type: ANIME, season: $seasonNext, seasonYear: $seasonYearNext, sort: [START_DATE], format_not: $formatNot, onList: $onList, id_in: $ids, genre_not_in: $nsfw) {
          \(scheduleMediaFields)
        }
      }
      next2: Page(page: 2) {
        media(type: ANIME, season: $seasonNext, seasonYear: $seasonYearNext, sort: [START_DATE], format_not: $formatNot, onList: $onList, id_in: $ids, genre_not_in: $nsfw) {
          \(scheduleMediaFields)
        }
      }
    }
    """

    static let airingSchedule = """
    query ($from: Int, $to: Int) {
      Page(page: 1, perPage: 50) {
        airingSchedules(airingAt_greater: $from, airingAt_lesser: $to, sort: TIME) {
          episode
          airingAt
          media {
            id
            title { romaji english native userPreferred }
            coverImage { large color }
            averageScore
            episodes
            status
          }
        }
      }
    }
    """

    static let airingMonth = """
    query ($from: Int, $to: Int, $page: Int) {
      Page(page: $page, perPage: 50) {
        pageInfo { hasNextPage }
        airingSchedules(airingAt_greater: $from, airingAt_lesser: $to, sort: TIME) {
          episode
          airingAt
          media {
            id
            title { romaji english native userPreferred }
            coverImage { large color }
            averageScore
            episodes
            status
          }
        }
      }
    }
    """

    // MARK: - Per-media airing schedule

    static let mediaSchedule = """
    query ($id: Int) {
      Media(id: $id, type: ANIME) {
        episodes
        startDate { year month day }
        aired: airingSchedule(page: 1, perPage: 50, notYetAired: false) {
          n: nodes { a: airingAt e: episode }
        }
        notaired: airingSchedule(page: 1, perPage: 50, notYetAired: true) {
          n: nodes { a: airingAt e: episode }
        }
      }
    }
    """
}
