/**
 * extensions/types.ts — Mirrors Hayase's src/lib/modules/extensions/types.d.ts
 */

export type Accuracy = 'high' | 'medium' | 'low';

export interface SearchOptions {
  [key: string]: {
    type: 'string' | 'number' | 'boolean' | 'select';
    description: string;
    values?: unknown[];
    default: unknown;
  };
}

export interface ExtensionConfig {
  name: string;
  version: string;
  description: string;
  id: string;
  type: 'torrent' | 'nzb' | 'url';
  accuracy: Accuracy;
  ratio?: 'perma' | number;
  icon: string;
  media: 'sub' | 'dub' | 'both';
  url?: string;
  languages: string[];
  update?: string;
  code: string;
  options?: SearchOptions;
}

export interface TorrentResult {
  title: string;
  link: string;
  id?: number;
  seeders: number;
  leechers: number;
  downloads: number;
  accuracy: Accuracy;
  hash: string;
  size: number;
  date: Date;
  type?: 'batch' | 'best' | 'alt';
}

export interface TorrentQuery {
  media: unknown;
  anilistId: number;
  anidbAid?: number;
  anidbEid?: number;
  tvdbId?: number;
  tvdbEId?: number;
  imdbId?: string;
  tmdbId?: string;
  titles: string[];
  episode: number;
  episodeCount?: number;
  absoluteEpisodeNumber?: number;
  resolution: '2160' | '1080' | '720' | '540' | '480' | '';
  exclusions: string[];
  type?: 'sub' | 'dub';
}

export type TorrentQueryWithFetch = TorrentQuery & { fetch: typeof fetch };

export type SearchFunction = (
  query: TorrentQueryWithFetch,
  options?: SearchOptions
) => Promise<TorrentResult[]>;

export interface TorrentSource {
  test: () => Promise<boolean>;
  single: SearchFunction;
  batch: SearchFunction;
  movie: SearchFunction;
}

export interface NZBSource {
  test: () => Promise<boolean>;
  query: (
    hash: string,
    options?: SearchOptions,
    fetch?: typeof globalThis.fetch
  ) => Promise<string>;
}
