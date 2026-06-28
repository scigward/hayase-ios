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

    // MARK: - Airing anime (legacy CoreData flow)

    static let airingAnime = """
    query ($nsfw: [String]) {
      Page(page: 1, perPage: 50) {
        media(status: RELEASING, type: ANIME, sort: POPULARITY_DESC, genre_not_in: $nsfw) {
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
          id
          idMal
          title { romaji english native userPreferred }
          coverImage { extraLarge large medium color }
          bannerImage
          averageScore
          genres
          isFavourite
          tags { id name isMediaSpoiler isGeneralSpoiler rank isAdult }
          episodes
          duration
          status
          seasonYear
          season
          format
          startDate { year }
          favourites
          trailer { id site }
          description(asHtml: false)
          synonyms
          mediaListEntry { id status progress repeat score(format: POINT_10) customLists(asArray: true) }
        }
      }
    }
    """

    // MARK: - Legacy text search (CoreData flow)

    static let searchLegacy = """
    query ($search: String, $nsfw: [String]) {
      Page(page: 1, perPage: 50) {
        media(search: $search, type: ANIME, sort: POPULARITY_DESC, genre_not_in: $nsfw) {
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

    // MARK: - Home section

    static let homeSection = """
    query ($status: [MediaStatus], $sort: [MediaSort], $genre: [String], $season: MediaSeason, $seasonYear: Int, $nsfw: [String]) {
      Page(page: 1) {
        media(type: ANIME, format_not: MUSIC, status_in: $status, sort: $sort, genre_in: $genre, season: $season, seasonYear: $seasonYear, genre_not_in: $nsfw) {
          id
          idMal
          title { romaji english native userPreferred }
          coverImage { extraLarge large medium color }
          bannerImage
          averageScore
          genres
          isFavourite
          tags { id name isMediaSpoiler isGeneralSpoiler rank isAdult }
          episodes
          duration
          status
          seasonYear
          season
          format
          startDate { year }
          favourites
          trailer { id site }
          description(asHtml: false)
          synonyms
          mediaListEntry { id status progress repeat score(format: POINT_10) customLists(asArray: true) }
        }
      }
    }
    """

    // MARK: - Banner (banner.svelte)

    static let banner = """
    query ($sort: [MediaSort], $season: MediaSeason, $seasonYear: Int, $statusNot: [MediaStatus], $nsfw: [String]) {
      Page(page: 1, perPage: 15) {
        media(type: ANIME, sort: $sort, season: $season, seasonYear: $seasonYear, status_not_in: $statusNot, genre_not_in: $nsfw) {
          id
          idMal
          title { romaji english native userPreferred }
          coverImage { extraLarge large medium color }
          bannerImage
          averageScore
          genres
          isFavourite
          tags { id name isMediaSpoiler isGeneralSpoiler rank isAdult }
          episodes
          duration
          status
          seasonYear
          season
          format
          startDate { year }
          favourites
          trailer { id site }
          description(asHtml: false)
          synonyms
          mediaListEntry { id status progress repeat score(format: POINT_10) customLists(asArray: true) }
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
    query ($idIn: [Int]) {
      Page(page: 1, perPage: 50) {
        media(type: ANIME, id_in: $idIn) {
          id
          idMal
          title { romaji english native userPreferred }
          coverImage { extraLarge large medium color }
          bannerImage
          averageScore
          genres
          isFavourite
          tags { id name isMediaSpoiler isGeneralSpoiler rank isAdult }
          episodes
          duration
          status
          seasonYear
          season
          format
          startDate { year }
          favourites
          trailer { id site }
          description(asHtml: false)
          synonyms
          mediaListEntry { id status progress repeat score(format: POINT_10) customLists(asArray: true) }
        }
      }
    }
    """

    static let idInFiltered = """
    query ($idIn: [Int], $status: [MediaStatus], $onList: Boolean, $sort: [MediaSort]) {
      Page(page: 1, perPage: 50) {
        media(type: ANIME, id_in: $idIn, status_in: $status, onList: $onList, sort: $sort) {
          id
          idMal
          title { romaji english native userPreferred }
          coverImage { extraLarge large medium color }
          bannerImage
          averageScore
          genres
          isFavourite
          tags { id name isMediaSpoiler isGeneralSpoiler rank isAdult }
          episodes
          duration
          status
          seasonYear
          season
          format
          startDate { year }
          favourites
          trailer { id site }
          description(asHtml: false)
          synonyms
          mediaListEntry { id status progress repeat score(format: POINT_10) customLists(asArray: true) }
        }
      }
    }
    """

    static let byIds = """
    query ($ids: [Int]) {
      Page(page: 1, perPage: 50) {
        media(type: ANIME, id_in: $ids, sort: POPULARITY_DESC) {
          id
          idMal
          title { romaji english native userPreferred }
          coverImage { extraLarge large medium color }
          bannerImage
          averageScore
          genres
          isFavourite
          tags { id name isMediaSpoiler isGeneralSpoiler rank isAdult }
          episodes
          duration
          status
          seasonYear
          season
          format
          startDate { year }
          favourites
          trailer { id site }
          description(asHtml: false)
          synonyms
          mediaListEntry { id status progress repeat score(format: POINT_10) customLists(asArray: true) }
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
        id
        idMal
        title { english romaji native userPreferred }
        coverImage { extraLarge large medium color }
        bannerImage
        averageScore
        genres
        isFavourite
        tags { id name isMediaSpoiler isGeneralSpoiler rank isAdult }
        episodes
        duration
        status
        seasonYear
        season
        format
        startDate { year }
        favourites
        trailer { id site }
        description(asHtml: false)
        synonyms
        isAdult
        mediaListEntry { id status progress repeat score(format: POINT_10) customLists(asArray: true) }
        relations {
          edges {
            relationType(version: 2)
            node {
              id
              title { english romaji native userPreferred }
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
        relations {
          edges {
            relationType(version: 2)
            node {
              id
              title { userPreferred romaji english native }
              coverImage { extraLarge medium color }
              type
              status
              format
              episodes
              synonyms
              season
              seasonYear
              startDate { year month day }
              relations {
                edges {
                  relationType(version: 2)
                  node {
                    id
                    title { userPreferred }
                    type
                    status
                    format
                    episodes
                  }
                }
              }
            }
          }
        }
        recommendations(sort: [RATING_DESC, ID], perPage: 24) {
          nodes {
            id
            rating
            mediaRecommendation {
              id
              title { userPreferred romaji english native }
              coverImage { extraLarge medium color }
              type
              status
              format
              episodes
              synonyms
              season
              seasonYear
              startDate { year month day }
              mediaListEntry { id status progress repeat score(format: POINT_10) customLists(asArray: true) }
            }
          }
        }
      }
      threads: Page(perPage: 16) {
        pageInfo { hasNextPage total }
        threads(mediaCategoryId: $id, sort: ID_DESC) {
          id
          title
          viewCount
          replyCount
          likeCount
          isLocked
          repliedAt
          createdAt
          user { id name avatar { large } }
          categories { id name }
        }
      }
    }
    """

    static let animePageFollowing = """
    query AnimePageFollowing($id: Int!) {
      following: Page {
        mediaList(mediaId: $id, isFollowing: true, sort: UPDATED_TIME_DESC) {
          id
          status
          score
          progress
          user { id name avatar { large } }
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
    query($id:Int){Page(perPage:16){pageInfo{hasNextPage total} threads(mediaCategoryId:$id,sort:ID_DESC){id title viewCount replyCount likeCount isLocked repliedAt createdAt user{id name avatar{large}} categories{id name}}}}
    """

    // MARK: - Airing schedule

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
