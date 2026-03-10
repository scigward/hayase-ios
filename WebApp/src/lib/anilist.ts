/**
 * anilist.ts — AniList GraphQL client.
 * Mirrors Hayase's src/lib/modules/anilist/client.ts + queries.ts
 * Calls graphql.anilist.co directly from the browser (no native bridge needed).
 */

const ANILIST_API = 'https://graphql.anilist.co';

// ── Types ─────────────────────────────────────────────────────────────────

export interface AniListMedia {
  id: number;
  idMal: number | null;
  title: {
    romaji: string | null;
    english: string | null;
    native: string | null;
    userPreferred: string | null;
  };
  description: string | null;
  season: string | null;
  seasonYear: number | null;
  format: string | null;
  status: string | null;
  episodes: number | null;
  duration: number | null;
  averageScore: number | null;
  genres: string[] | null;
  isFavourite: boolean;
  coverImage: {
    extraLarge: string | null;
    medium: string | null;
    color: string | null;
  } | null;
  bannerImage: string | null;
  synonyms: string[] | null;
  source: string | null;
  countryOfOrigin: string | null;
  isAdult: boolean;
  trailer: { id: string | null; site: string | null } | null;
  nextAiringEpisode: { id: number; timeUntilAiring: number; episode: number } | null;
  startDate: { year: number | null; month: number | null; day: number | null } | null;
  mediaListEntry: {
    id: number;
    status: string;
    progress: number;
    repeat: number;
    score: number;
  } | null;
  studios: { nodes: { id: number; name: string }[] } | null;
  relations: {
    edges: Array<{
      relationType: string | null;
      node: {
        id: number;
        status: string | null;
        format: string | null;
        episodes: number | null;
        title: { userPreferred: string | null };
        coverImage: { extraLarge: string | null } | null;
        type: string | null;
      } | null;
    } | null> | null;
  } | null;
}

export interface PageInfo { hasNextPage: boolean; }
export interface Page { pageInfo: PageInfo; media: AniListMedia[] | null; }

// ── Core fragment (mirrors Hayase's FullMedia) ────────────────────────────

const FULL_MEDIA_FRAGMENT = `
  fragment FullMedia on Media {
    id idMal
    title { romaji english native userPreferred }
    description(asHtml: false)
    season seasonYear format status
    episodes duration averageScore
    genres isFavourite
    coverImage { extraLarge medium color }
    source countryOfOrigin isAdult
    bannerImage synonyms
    nextAiringEpisode { id timeUntilAiring episode }
    startDate { year month day }
    trailer { id site }
    mediaListEntry {
      id status progress repeat
      score(format: POINT_10)
    }
    studios(isMain: true) { nodes { id name } }
    relations {
      edges {
        relationType(version: 2)
        node {
          id status format episodes
          title { userPreferred }
          coverImage { extraLarge }
          type
        }
      }
    }
  }
`;

// ── gql helper ────────────────────────────────────────────────────────────

async function gql<T>(query: string, variables?: Record<string, unknown>): Promise<T> {
  const resp = await fetch(ANILIST_API, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ query, variables: variables ?? {} }),
  });
  if (!resp.ok) throw new Error(`AniList HTTP ${resp.status}`);
  const json = await resp.json() as { data: T; errors?: Array<{ message: string }> };
  if (json.errors?.length) throw new Error(json.errors.map(e => e.message).join(', '));
  return json.data;
}

// ── Search (mirrors Hayase's Search query) ────────────────────────────────

export interface SearchVariables {
  page?: number;
  perPage?: number;
  search?: string;
  genre?: string[] | null;
  format?: string[] | null;
  status?: string[] | null;
  statusNot?: string[] | null;
  season?: string | null;
  seasonYear?: number | null;
  sort?: string[] | null;
  isAdult?: boolean;
  ids?: number[] | null;
  nsfw?: string[] | null;
}

export async function searchMedia(vars: SearchVariables): Promise<{ media: AniListMedia[]; hasNextPage: boolean }> {
  const data = await gql<{ Page: Page }>(`
    ${FULL_MEDIA_FRAGMENT}
    query Search(
      $page: Int $perPage: Int $search: String
      $genre: [String] $format: [MediaFormat]
      $status: [MediaStatus] $statusNot: [MediaStatus]
      $season: MediaSeason $seasonYear: Int
      $isAdult: Boolean $sort: [MediaSort]
      $ids: [Int] $nsfw: [String]
    ) {
      Page(page: $page, perPage: $perPage) {
        pageInfo { hasNextPage }
        media(
          type: ANIME format_not: MUSIC
          id_in: $ids search: $search
          genre_in: $genre format_in: $format
          status_in: $status status_not_in: $statusNot
          season: $season seasonYear: $seasonYear
          isAdult: $isAdult sort: $sort
          genre_not_in: $nsfw
        ) { ...FullMedia }
      }
    }
  `, {
    page:       vars.page ?? 1,
    perPage:    vars.perPage ?? 20,
    search:     vars.search || undefined,
    genre:      vars.genre?.length   ? vars.genre   : undefined,
    format:     vars.format?.length  ? vars.format  : undefined,
    status:     vars.status?.length  ? vars.status  : undefined,
    statusNot:  vars.statusNot?.length ? vars.statusNot : undefined,
    season:     vars.season    || undefined,
    seasonYear: vars.seasonYear || undefined,
    sort:       vars.sort?.length    ? vars.sort    : undefined,
    isAdult:    vars.isAdult ?? false,
    ids:        vars.ids?.length     ? vars.ids     : undefined,
    nsfw:       (!vars.isAdult)      ? ['Hentai']   : undefined,
  });
  return {
    media: data.Page.media ?? [],
    hasNextPage: data.Page.pageInfo.hasNextPage,
  };
}

// ── Single media by ID ────────────────────────────────────────────────────

export async function getMedia(id: number): Promise<AniListMedia> {
  const data = await gql<{ Media: AniListMedia }>(`
    ${FULL_MEDIA_FRAGMENT}
    query IDMedia($id: Int!) {
      Media(id: $id, type: ANIME) { ...FullMedia }
    }
  `, { id });
  return data.Media;
}

// ── Home sections (mirrors Hayase's 7 sections) ──────────────────────────

import { currentSeason, currentYear } from './util';

export const HOME_SECTIONS = [
  {
    title: 'Popular This Season',
    vars: {
      sort: ['POPULARITY_DESC'],
      season: currentSeason,
      seasonYear: currentYear,
      statusNot: ['NOT_YET_RELEASED'],
      perPage: 20,
    } as SearchVariables,
  },
  {
    title: 'Trending Now',
    vars: { sort: ['TRENDING_DESC'], perPage: 20 } as SearchVariables,
  },
  {
    title: 'All Time Popular',
    vars: { sort: ['POPULARITY_DESC'], perPage: 20 } as SearchVariables,
  },
  {
    title: 'Romance',
    vars: { sort: ['POPULARITY_DESC'], genre: ['Romance'], perPage: 20 } as SearchVariables,
  },
  {
    title: 'Action',
    vars: { sort: ['POPULARITY_DESC'], genre: ['Action'], perPage: 20 } as SearchVariables,
  },
  {
    title: 'Adventure',
    vars: { sort: ['POPULARITY_DESC'], genre: ['Adventure'], perPage: 20 } as SearchVariables,
  },
  {
    title: 'Fantasy',
    vars: { sort: ['POPULARITY_DESC'], genre: ['Fantasy'], perPage: 20 } as SearchVariables,
  },
] as const;

// ── Characters (for detail tab) ───────────────────────────────────────────

export interface Character {
  id: number;
  name: { full: string | null };
  image: { large: string | null } | null;
}

export async function getCharacters(mediaId: number): Promise<Character[]> {
  const data = await gql<{
    Media: { characters: { nodes: Character[] } }
  }>(`
    query MediaChars($id: Int!) {
      Media(id: $id, type: ANIME) {
        characters(sort: ROLE, perPage: 20) {
          nodes { id name { full } image { large } }
        }
      }
    }
  `, { id: mediaId });
  return data.Media.characters.nodes ?? [];
}

// ── Staff (for detail tab) ────────────────────────────────────────────────

export interface Staff {
  id: number;
  name: { full: string | null };
  image: { large: string | null } | null;
  primaryOccupations: string[] | null;
}

export async function getStaff(mediaId: number): Promise<Staff[]> {
  const data = await gql<{
    Media: { staff: { nodes: Staff[] } }
  }>(`
    query MediaStaff($id: Int!) {
      Media(id: $id, type: ANIME) {
        staff(sort: RELEVANCE, perPage: 20) {
          nodes { id name { full } image { large } primaryOccupations }
        }
      }
    }
  `, { id: mediaId });
  return data.Media.staff.nodes ?? [];
}
