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
              relationType(version: 3)
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
                    relationType(version: 3)
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

    static let viewer = """
    query Viewer {
      Viewer {
        \(userFields)
        mediaListOptions { animeList { customLists } }
        options { titleLanguage displayAdultContent }
      }
    }
    """

    /// A standalone single-user fetch, reusing `userFields` (previously only
    /// ever nested inside other queries — following lists, thread comments).
    static let user = """
    query User($id: Int!) {
      User(id: $id) {
        \(userFields)
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
          coverImage { extraLarge color }
          title { userPreferred }
          mediaListEntry { status progress id }
          aired: airingSchedule(page: 1, perPage: 50, notYetAired: false) {
            n: nodes { a: airingAt e: episode }
          }
          notaired: airingSchedule(page: 1, perPage: 50, notYetAired: true) {
            n: nodes { a: airingAt e: episode }
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


    // MARK: - Following many (full-banner.svelte)

    // MARK: - Following (EpisodesList.svelte's `client.following`)

    static let following = """
    query Following($id: Int!) {
      following: Page {
        mediaList(mediaId: $id, isFollowing: true, sort: UPDATED_TIME_DESC) {
          id
          status
          score
          progress
          user { \(userFields) }
        }
      }
    }
    """

    static let followingMany = """
    query FollowingMany($ids: [Int]!) {
      Page {
        mediaList(mediaId_in: $ids, isFollowing: true, sort: UPDATED_TIME_DESC) {
          id
          status
          score
          progress
          media { id }
          user { \(userFields) }
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

    // MARK: - Detail (relations)


    static let resolverMediaById = """
    query ($id: Int) {
      Media(id: $id, type: ANIME) {
        \(fullMediaFields)
      }
    }
    """

    // MARK: - Staff + Stats


    // MARK: - Anime page (anime/[id]/+layout.svelte + +page.svelte)

    /// The interface asks for `EdgeMedia` per recommendation, because its recommendation cards have
    /// `hover={false}`. Here the cards open the hover card, which needs the description, score,
    /// banner, trailer and the rest of the media, so a recommendation is asked for in full.
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
          title { userPreferred }
          relations {
            edges {
              relationType
              node {
                type
                id
                status
                format
                episodes
                title { userPreferred }
                relations {
                  edges {
                    relationType
                    node {
                      type
                      id
                      status
                      format
                      episodes
                      title { userPreferred }
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
    query IDTitle($id: Int!) {
      Media(id: $id, type: ANIME) {
        id
        title { userPreferred }
      }
    }
    """

    static let updateUser = """
    mutation UpdateUser($lists: [String], $adult: Boolean, $language: UserTitleLanguage) {
      UpdateUser(animeListOptions: { customLists: $lists }, displayAdultContent: $adult, titleLanguage: $language) {
        \(userFields)
        mediaListOptions { animeList { customLists } }
        options { titleLanguage displayAdultContent }
      }
    }
    """

    static let userLists = """
    query UserLists($id: Int) {
      MediaListCollection(userId: $id, type: ANIME, forceSingleCompletedList: true, sort: UPDATED_TIME_DESC) {
        user { id }
        lists {
          status
          entries {
            id
            media {
              title { userPreferred }
              id
              status
              episodes
              mediaListEntry {
                id
                status
                progress
                score(format: POINT_10)
                repeat
                customLists(asArray: true)
              }
              nextAiringEpisode { episode }
              relations {
                edges {
                  relationType(version: 3)
                  node { id }
                }
              }
            }
          }
        }
      }
    }
    """

    static let saveEntry = """
    mutation Entry($lists: [String], $id: Int!, $status: MediaListStatus, $progress: Int, $repeat: Int, $score: Int) {
      SaveMediaListEntry(mediaId: $id, status: $status, progress: $progress, repeat: $repeat, scoreRaw: $score, customLists: $lists) {
        id
        mediaId
        status
        progress
        score(format: POINT_10)
        repeat
        customLists(asArray: true)
        media { id }
      }
    }
    """

    static let deleteEntry = """
    mutation DeleteEntry($id: Int!) {
      DeleteMediaListEntry(id: $id) {
        deleted
      }
    }
    """

    static let trackingSingleMedia = """
    query TrackingSingleMedia($id: Int!) {
      Media(id: $id, type: ANIME) {
        id
        status
        episodes
        format
        duration
        title { romaji english native userPreferred }
        synonyms
        notaired: airingSchedule(page: 1, perPage: 50, notYetAired: true) { n: nodes { a: airingAt e: episode } }
        aired: airingSchedule(page: 1, perPage: 50, notYetAired: false) { n: nodes { a: airingAt e: episode } }
        mediaListEntry {
          id
          status
          progress
          score(format: POINT_10)
          repeat
          customLists(asArray: true)
        }
      }
    }
    """

    static let toggleFavourite = """
    mutation ToggleFavourite($id: Int!) {
      ToggleFavourite(animeId: $id) {
        anime { nodes { id } }
      }
    }
    """

    static let isFavourite = """
    query IsFavourite($id: Int) {
      Media(id: $id) {
        isFavourite
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
        media(type: ANIME, season: $seasonLast, seasonYear: $seasonYearLast, status_in: [RELEASING, HIATUS], format_not: $formatNot, onList: $onList, id_in: $ids, genre_not_in: $nsfw) {
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



    // MARK: - Per-media airing schedule

}
