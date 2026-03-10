/**
 * extensions/extensions.ts — Mirrors Hayase's src/lib/modules/extensions/extensions.ts
 *
 * Core extension engine: makeEpisodeList, episodeByAirDate, Extensions class.
 * Adapted for iOS WebView — no 'debug' package (uses console.debug instead),
 * no '$app/environment' (no dev build flag check needed), no abslink.
 */

import { get } from 'svelte/store';
import { episodesCached } from '../anizip';
import { storage, savedOptions, savedConfigs } from './storage';

import type { TorrentResult, TorrentQuery, SearchOptions, Accuracy } from './types';
import type { AniZipEpisode, AniZipResponse } from '../anizip';

// ─── Filler data ────────────────────────────────────────────────────────────

export let fillerEpisodes: Record<number, number[] | undefined> = {};

fetch('https://raw.githubusercontent.com/ThaUnknown/filler-scrape/master/filler.json')
  .then(r => r.json())
  .then(data => { fillerEpisodes = data; })
  .catch(() => {});

// ─── Types ───────────────────────────────────────────────────────────────────

export interface SingleEpisode {
  episode: number;
  image?: string;
  summary?: string;
  rating?: string;
  runtime?: number;
  title?: Record<string, string>;
  length?: number;
  airdate?: string;
  airingAt?: Date;
  filler: boolean;
  anidbEid?: number;
  tvdbId?: number;
  tvdbShowId?: number;
  absoluteEpisodeNumber?: number;
}

// ─── Episode helpers ─────────────────────────────────────────────────────────

/**
 * Mirrors Hayase's episodeByAirDate — finds the closest episode to an AniList
 * air date in the ani.zip episode map.
 */
export function episodeByAirDate(
  alDate: Date | undefined,
  episodes: Map<string, AniZipEpisode & { airdatems?: number }>,
  episode: number
): (AniZipEpisode & { airdatems?: number }) | undefined {
  if (!alDate || isNaN(+alDate)) return episodes.get('' + episode);

  const values = [...episodes.values()];
  const closestEpisodes = values.reduce<AniZipEpisode[]>((prev, curr) => {
    if (!prev[0]) return [curr];
    const prevDist = Math.abs(+new Date((prev[0] as any).airdate ?? 0) - +alDate);
    const currDist = Math.abs(+new Date(curr.airdate ?? 0) - +alDate);
    if (prevDist === currDist) { prev.push(curr); return prev; }
    return currDist < prevDist ? [curr] : prev;
  }, []);

  if (!closestEpisodes.length) return episodes.get('' + episode);

  return (closestEpisodes as (AniZipEpisode & { airdatems?: number })[]).reduce((prev, curr) =>
    Math.abs(Number(curr.episode) - episode) < Math.abs(Number(prev.episode) - episode) ? curr : prev
  );
}

/**
 * Builds an ordered SingleEpisode[] from AniList media + ani.zip data.
 * Mirrors Hayase's makeEpisodeList().
 */
export function makeEpisodeList(
  media: { id: number; episodes?: number | null; airingSchedule?: { nodes?: { episode: number; airingAt: number }[] } },
  episodesRes?: AniZipResponse | null
): SingleEpisode[] {
  const count = media.episodes ?? episodesRes?.episodeCount ?? 0;
  const alSchedule: Record<number, Date | undefined> = {};
  for (const node of media.airingSchedule?.nodes ?? []) {
    alSchedule[node.episode] = new Date(node.airingAt * 1000);
  }

  const filtered = new Map<string, AniZipEpisode & { airdatems?: number }>();
  const now = Date.now();
  for (const [key, value] of Object.entries(episodesRes?.episodes ?? {})) {
    filtered.set(key, { ...value, airdatems: value.airdate ? +new Date(value.airdate) : undefined });
  }

  const hasSpecial = !!episodesRes?.specialCount;
  const hasCountMatch = (media.episodes ?? 0) === (episodesRes?.episodeCount ?? 0);

  const list: SingleEpisode[] = [];
  for (let ep = 1; ep <= count; ep++) {
    const airingAt = alSchedule[ep];
    const hasEpisode = episodesRes?.episodes?.[ep];
    const needsValidation = !(!hasSpecial || (hasEpisode && hasCountMatch));
    const resolved = needsValidation
      ? episodeByAirDate(airingAt, filtered, ep)
      : filtered.get('' + ep);

    if (needsValidation && resolved) {
      for (const [key, value] of filtered.entries()) {
        if (
          (value.anidbEid != null && value.anidbEid === (resolved as any).anidbEid) ||
          (value.airdatems != null && value.airdatems < ((resolved as any).airdatems ?? now))
        ) {
          filtered.delete(key);
        }
      }
    }

    const { image, summary, overview, rating, title, length, airdate, anidbEid, runtime, tvdbId, absoluteEpisodeNumber } = resolved ?? {} as Partial<AniZipEpisode>;
    list.push({
      episode: ep,
      image,
      summary: summary ?? overview,
      rating,
      title,
      length,
      airdate,
      airingAt,
      filler: !!fillerEpisodes[media.id]?.includes(ep),
      anidbEid,
      runtime,
      tvdbId,
      absoluteEpisodeNumber,
    });
  }
  return list;
}

// ─── Extensions class ────────────────────────────────────────────────────────

class ExtensionsClass {
  /** Build a de-duplicated title list for extension queries. Mirrors createTitles(). */
  createTitles(media: { title?: Record<string, string | null>; synonyms?: (string | null)[] }): string[] {
    const grouped = [...new Set(
      [...Object.values(media.title ?? {}), ...(media.synonyms ?? [])]
        .filter((t): t is string => t != null && t.length > 3)
    )];
    const titles: string[] = [];
    const append = (t: string) => {
      titles.push(t);
      const m1 = t.match(/(\d)(?:nd|rd|th) Season/i);
      const m2 = t.match(/Season (\d)/i);
      if (m2) titles.push(t.replace(/Season \d/i, `S${m2[1]}`));
      else if (m1) titles.push(t.replace(/(\d)(?:nd|rd|th) Season/i, `S${m1[1]}`));
    };
    for (const t of grouped) {
      append(t);
      if (t.includes('-')) append(t.replaceAll('-', ''));
    }
    return titles;
  }

  /** Fetch ani.zip data + mappings for a media entry. Mirrors ALToAniDB(). */
  async ALToAniDB(media: { id: number }): Promise<AniZipResponse | null | undefined> {
    const json = await episodesCached(media.id);
    if (json?.mappings?.anidb_id) return json;
    return undefined;
  }

  /** Map AniList episode to AniDB episode metadata. Mirrors ALtoAniDBEpisode(). */
  async ALtoAniDBEpisode(
    opts: { media: { id: number; episodes?: number | null }; episode: number },
    episodesRes?: AniZipResponse | null
  ): Promise<SingleEpisode | undefined> {
    return makeEpisodeList(opts.media, episodesRes)[opts.episode - 1];
  }

  /**
   * Query all enabled torrent extensions for a given media + episode.
   * Mirrors Extensions.getResultsFromExtensions().
   */
  async getResultsFromExtensions({
    media,
    episode,
    resolution,
  }: {
    media: {
      id: number;
      episodes?: number | null;
      title?: Record<string, string | null>;
      synonyms?: (string | null)[];
      format?: string | null;
    };
    episode: number;
    resolution: '2160' | '1080' | '720' | '540' | '480' | '';
  }): Promise<{ results: (TorrentResult & { extension: Set<string> })[]; errors: { error: Error; extension: string }[] }> {
    await storage.ready;

    const extensions = storage.codeManager.extensions;
    if (!extensions.size) {
      throw new Error('No torrent sources configured. Add extensions in settings.');
    }

    const isMovie = media.format === 'MOVIE';
    const isSingleEp = (media.episodes ?? 0) <= 1;

    const aniDBMeta = await this.ALToAniDB(media);
    const { anidb_id: anidbAid, mal_id: malId, themoviedb_id: tmdbId, kitsu_id: kitsuId, thetvdb_id: tvdbId } = aniDBMeta?.mappings ?? {};
    const episodeMeta = anidbAid != null
      ? await this.ALtoAniDBEpisode({ media, episode }, aniDBMeta)
      : undefined;
    const { anidbEid, tvdbId: tvdbEId, absoluteEpisodeNumber } = episodeMeta ?? {};

    const options: TorrentQuery = {
      anilistId: media.id,
      episodeCount: media.episodes ?? undefined,
      episode,
      anidbAid,
      anidbEid,
      tvdbId,
      tvdbEId,
      malId,
      tmdbId,
      kitsuId,
      media,
      absoluteEpisodeNumber,
      titles: this.createTitles(media),
      resolution,
      exclusions: [],
    } as TorrentQuery;

    const results: (TorrentResult & { extension: Set<string> })[] = [];
    const errors: { error: Error; extension: string }[] = [];

    const extopts = get(savedOptions);
    const configs = get(savedConfigs);
    const checkMovie = !isSingleEp && isMovie;
    const checkBatch = !isSingleEp && !isMovie;

    for (const [id, worker] of extensions.entries()) {
      const thisOpts = extopts[id];
      if (!thisOpts?.enabled) continue;
      if (configs[id]?.type !== 'torrent') continue;
      try {
        const promises: Promise<TorrentResult[]>[] = [worker.single(options, thisOpts.options as SearchOptions)];
        if (checkMovie) promises.push(worker.movie(options, thisOpts.options as SearchOptions));
        if (checkBatch) promises.push(worker.batch(options, thisOpts.options as SearchOptions));

        for (const settled of await Promise.allSettled(promises)) {
          if (settled.status === 'fulfilled') {
            results.push(...settled.value.map(v => ({ ...v, extension: new Set([id]) })));
          } else {
            errors.push({ error: settled.reason as Error, extension: id });
          }
        }
      } catch (error) {
        errors.push({ error: error as Error, extension: id });
      }
    }

    return { results: this.dedupe(results), errors };
  }

  /** De-duplicate results by hash, merging extension sets. Mirrors dedupe(). */
  dedupe<T extends TorrentResult & { extension: Set<string> }>(entries: T[]): T[] {
    const seen: Record<string, T> = {};
    for (const entry of entries) {
      if (entry.hash in seen) {
        const dupe = seen[entry.hash]!;
        for (const ext of entry.extension) dupe.extension.add(ext);
        const rank = (a: Accuracy) => ['high', 'medium', 'low'].indexOf(a);
        dupe.accuracy = rank(entry.accuracy) <= rank(dupe.accuracy) ? entry.accuracy : dupe.accuracy;
        dupe.title = entry.title.length > dupe.title.length ? entry.title : dupe.title;
        dupe.link ??= entry.link;
        dupe.id ??= entry.id;
        dupe.seeders ||= entry.seeders >= 30000 ? 0 : entry.seeders;
        dupe.leechers ||= entry.leechers >= 30000 ? 0 : entry.leechers;
        dupe.downloads ||= entry.downloads;
        dupe.size ||= entry.size;
        dupe.date ||= entry.date;
        dupe.type ??= entry.type;
      } else {
        seen[entry.hash] = entry;
      }
    }
    return Object.values(seen);
  }
}

export const extensions = new ExtensionsClass();
export { savedConfigs, savedOptions, storage } from './storage';
