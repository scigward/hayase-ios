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
          title { english romaji }
          coverImage { large medium color }
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
    query ($search: String, $genre_in: [String], $format_in: [MediaFormat], $status_in: [MediaStatus], $sort: [MediaSort], $page: Int, $seasonYear: Int, $season: MediaSeason, $nsfw: [String]) {
      Page(page: $page, perPage: 20) {
        pageInfo { hasNextPage }
        media(type: ANIME, search: $search, genre_in: $genre_in, format_in: $format_in, status_in: $status_in, sort: $sort, seasonYear: $seasonYear, season: $season, genre_not_in: $nsfw) {
          id
          idMal
          title { english romaji }
          coverImage { large medium color }
          bannerImage
          averageScore
          genres
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
          mediaListEntry { status }
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
          title { english romaji }
          coverImage { large medium color }
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
    query ($status: MediaStatus, $sort: [MediaSort], $genre: String, $season: MediaSeason, $seasonYear: Int, $nsfw: [String]) {
      Page(page: 1, perPage: 20) {
        media(type: ANIME, status: $status, sort: $sort, genre: $genre, season: $season, seasonYear: $seasonYear, genre_not_in: $nsfw) {
          id
          idMal
          title { english romaji }
          coverImage { large medium color }
          bannerImage
          averageScore
          genres
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
          mediaListEntry { status }
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
          title { english romaji }
          coverImage { large medium color }
          bannerImage
          averageScore
          genres
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
          title { english romaji }
          coverImage { large medium color }
          bannerImage
          averageScore
          genres
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
          mediaListEntry { status }
        }
      }
    }
    """

    static let idInFiltered = """
    query ($idIn: [Int], $status: [MediaStatus], $onList: Boolean) {
      Page(page: 1, perPage: 50) {
        media(type: ANIME, id_in: $idIn, status_in: $status, onList: $onList) {
          id
          idMal
          title { english romaji }
          coverImage { large medium color }
          bannerImage
          averageScore
          genres
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
          mediaListEntry { status }
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
          title { english romaji }
          coverImage { large medium color }
          bannerImage
          averageScore
          genres
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
          mediaListEntry { status }
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
            relationType
            node {
              id
              title { english romaji }
              coverImage { large color }
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
        title { english romaji }
        coverImage { large medium color }
        bannerImage
        averageScore
        genres
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
        relations {
          edges {
            relationType
            node {
              id
              title { english romaji }
              coverImage { large medium color }
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

    // MARK: - Trailer + Genres

    static let trailerGenres = """
    query($id:Int){Media(id:$id,type:ANIME){idMal genres trailer{id site}}}
    """

    // MARK: - Forum threads

    static let threads = """
    query($id:Int){Page(perPage:20){threads(mediaCategoryId:$id,sort:CREATED_AT_DESC){id title viewCount replyCount likeCount isLocked createdAt user{name avatar{large}} categories{id name}}}}
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
            title { english romaji }
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
            title { english romaji }
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
