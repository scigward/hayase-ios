/**
 * anizip.ts — Mirrors Hayase's src/lib/modules/anizip/index.ts
 * Base URL: https://api.ani.zip/v1  (public API, no special headers required)
 */

const BASE = 'https://api.ani.zip/v1';

export interface AniZipImage {
  coverType?: 'Banner' | 'Poster' | 'Fanart' | 'Clearlogo';
  url?: string;
}

export interface AniZipMappings {
  anilist_id?: number;
  mal_id?: number;
  kitsu_id?: number;
  anidb_id?: number;
  thetvdb_id?: number;
  themoviedb_id?: string;
}

export interface AniZipEpisode {
  tvdbId?: number;
  seasonNumber?: number;
  episodeNumber?: number;
  absoluteEpisodeNumber?: number;
  title?: Record<string, string>;
  airDate?: string;
  airDateUtc?: string;
  runtime?: number;
  overview?: string;
  image?: string;
  episode: string;
  anidbEid?: number;
  length?: number;
  airdate?: string;
  rating?: string;
  summary?: string;
  finaleType?: string;
}

export interface AniZipResponse {
  titles?: Record<string, string>;
  episodes?: Record<string | number, AniZipEpisode>;
  episodeCount?: number;
  specialCount?: number;
  images?: AniZipImage[];
  mappings?: AniZipMappings;
}

async function safefetch<T>(url: string): Promise<T | null> {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    return await res.json() as T;
  } catch {
    return null;
  }
}

// Single-entry cache (mirrors Hayase's lastEpisodes cache)
let _cache = { id: 0, data: null as Promise<AniZipResponse | null> | null };

export async function episodesCached(id: number): Promise<AniZipResponse | null> {
  if (_cache.id === id && _cache.data) return _cache.data;
  const data = safefetch<AniZipResponse>(`${BASE}/episodes?anilist_id=${id}`);
  _cache = { id, data };
  return data;
}

export function episodes(id: number): Promise<AniZipResponse | null> {
  return safefetch<AniZipResponse>(`${BASE}/episodes?anilist_id=${id}`);
}

export function mappings(id: number): Promise<AniZipMappings | null> {
  return safefetch<AniZipMappings>(`${BASE}/mappings?anilist_id=${id}`);
}

export function mappingsByKitsuId(kitsuId: number): Promise<AniZipMappings | null> {
  return safefetch<AniZipMappings>(`${BASE}/mappings?kitsu_id=${kitsuId}`);
}

export function mappingsByMalId(malId: number): Promise<AniZipMappings | null> {
  return safefetch<AniZipMappings>(`${BASE}/mappings?mal_id=${malId}`);
}
