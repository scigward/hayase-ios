/**
 * util.ts — Mirrors Hayase's src/lib/utils.ts and src/lib/modules/anilist/util.ts
 */
import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

// ── Class merger (same as Hayase) ──────────────────────────────────────────

export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

// ── Color utilities ────────────────────────────────────────────────────────

/** Extract RGB from hex color — used for --custom CSS variable RGB channels */
export function colors(hex = '#ffffff'): { r: number; g: number; b: number } {
  const bigint = parseInt(hex.slice(1), 16);
  const r = (bigint >> 16) & 255;
  const g = (bigint >> 8)  & 255;
  const b = bigint          & 255;
  return { r, g, b };
}

// ── Size/time formatting ───────────────────────────────────────────────────

const byteSuffixes = [' B', ' kB', ' MB', ' GB', ' TB'];
export function fastPrettyBytes(num: number): string {
  if (isNaN(num)) return '0 B';
  if (num < 1) return num + ' B';
  const exp = Math.min(Math.floor(Math.log(num) / Math.log(1000)), byteSuffixes.length - 1);
  return Number((num / Math.pow(1000, exp)).toFixed(1)) + byteSuffixes[exp]!;
}

const bitSuffixes = [' b', ' kb', ' Mb', ' Gb', ' Tb'];
export function fastPrettyBits(num: number): string {
  if (isNaN(num)) return '0 b';
  if (num < 1) return num + ' b';
  const exp = Math.min(Math.floor(Math.log(num) / Math.log(1000)), bitSuffixes.length - 1);
  return Number((num / Math.pow(1000, exp)).toFixed(1)) + bitSuffixes[exp]!;
}

export function eta(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return '0s';
  const units = [
    { label: 'y', secs: 31536000 },
    { label: 'mo', secs: 2592000 },
    { label: 'd', secs: 86400 },
    { label: 'h', secs: 3600 },
    { label: 'm', secs: 60 },
    { label: 's', secs: 1 },
  ];
  let remaining = Math.floor(seconds);
  const parts: string[] = [];
  for (const { label, secs } of units) {
    if (remaining >= secs) {
      parts.push(`${Math.floor(remaining / secs)}${label}`);
      remaining %= secs;
      if (parts.length === 2) break;
    }
  }
  return parts.length ? parts.join(' ') : '0s';
}

export function toTS(sec: number): string {
  if (isNaN(sec) || sec < 0) return '0:00';
  const h = Math.floor(sec / 3600);
  let m: string | number = Math.floor(sec / 60) - h * 60;
  let s: string | number = Math.floor(sec % 60);
  if (s < 10) s = '0' + s;
  if (h > 0) {
    if (m < 10) m = '0' + m;
    return `${h}:${m}:${s}`;
  }
  return `${m}:${s}`;
}

const relFmt = new Intl.RelativeTimeFormat('en');
const ranges: Partial<Record<Intl.RelativeTimeFormatUnit, number>> = {
  years: 3600 * 24 * 365, months: 3600 * 24 * 30, weeks: 3600 * 24 * 7,
  days: 3600 * 24, hours: 3600, minutes: 60, seconds: 1,
};
export function since(date: Date): string {
  const elapsed = (date.getTime() - Date.now()) / 1000;
  for (const _k in ranges) {
    const k = _k as Intl.RelativeTimeFormatUnit;
    if ((ranges[k] ?? 0) < Math.abs(elapsed)) {
      return relFmt.format(Math.round(elapsed / (ranges[k] ?? 1)), k);
    }
  }
  return 'now';
}

export const sleep = (t: number) => new Promise<void>(r => setTimeout(r, t));

export function debounce<T extends (...args: any[]) => unknown>(cb: T, wait: number) {
  let timeout: ReturnType<typeof setTimeout>;
  return (...args: Parameters<T>) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => cb(...args), wait);
  };
}

export function safeLocalStorage<T>(key: string): T | undefined {
  try {
    const v = localStorage.getItem(key);
    if (v) return JSON.parse(v) as T;
  } catch {}
}

// ── AniList media utilities (mirrors anilist/util.ts) ─────────────────────

export interface MediaTitle {
  romaji?: string | null;
  english?: string | null;
  native?: string | null;
  userPreferred?: string | null;
}
export interface CoverImage {
  extraLarge?: string | null;
  large?: string | null;
  medium?: string | null;
  color?: string | null;
}
export interface Trailer { id?: string | null; site?: string | null; }
export interface BaseMedia {
  bannerImage?: string | null;
  coverImage?: CoverImage | null;
  trailer?: Trailer | null;
  title?: MediaTitle | null;
  status?: string | null;
  format?: string | null;
  episodes?: number | null;
  duration?: number | null;
  averageScore?: number | null;
  season?: string | null;
  seasonYear?: number | null;
  startDate?: { year?: number | null; month?: number | null; day?: number | null } | null;
  description?: string | null;
  genres?: string[] | null;
}

export function banner(media: BaseMedia): string | undefined {
  if (media.bannerImage) return media.bannerImage;
  if (media.trailer?.id) return `https://i.ytimg.com/vi/${media.trailer.id}/maxresdefault.jpg`;
  return media.coverImage?.extraLarge ?? undefined;
}

export function cover(media: BaseMedia): string | undefined {
  return media.coverImage?.extraLarge ?? banner(media);
}

export function coverMedium(media: BaseMedia): string | undefined {
  return media.coverImage?.medium?.replace('/small/', '/medium/') ?? banner(media);
}

export function mediaTitle(media: BaseMedia): string {
  return media.title?.userPreferred ?? media.title?.english ?? media.title?.romaji ?? 'TBA';
}

const STATUS_MAP: Record<string, string> = {
  RELEASING: 'Airing', NOT_YET_RELEASED: 'Not Yet Released',
  FINISHED: 'Finished', CANCELLED: 'Cancelled', HIATUS: 'Hiatus',
};
export function mediaStatus(media: BaseMedia): string {
  return media.status ? (STATUS_MAP[media.status] ?? 'N/A') : 'N/A';
}

const FORMAT_MAP: Record<string, string> = {
  TV: 'TV Series', TV_SHORT: 'TV Short', MOVIE: 'Movie',
  SPECIAL: 'Special', OVA: 'OVA', ONA: 'ONA', MUSIC: 'Music',
};
export function mediaFormat(media: BaseMedia): string {
  return media.format ? (FORMAT_MAP[media.format] ?? media.format) : 'N/A';
}

function getSeasonForMonth(month: number): string {
  return (['WINTER', 'SPRING', 'SUMMER', 'FALL'] as const)[Math.floor((month / 12) * 4) % 4]!;
}

export function mediaSeason(media: BaseMedia): string {
  const s = media.season?.toLowerCase() ??
    (media.startDate?.month ? getSeasonForMonth(media.startDate.month).toLowerCase() : null);
  const y = media.seasonYear ?? media.startDate?.year;
  return [s, y].filter(Boolean).join(' ');
}

export function mediaDuration(media: BaseMedia): string | undefined {
  if (!media.duration) return undefined;
  return `${media.duration} min${media.duration > 1 ? 's' : ''}`;
}

export function mediaDesc(media: BaseMedia): string {
  const raw = media.description?.replace(/<[^>]+>/g, '').replace(/\n+/g, '\n') ?? 'No description available.';
  return raw.replace(/\n?\(?Source: [^)]+\)?\n?/m, '').replace(/\n?Notes?:[ |\n][^\n]+\n?/m, '');
}

export function getBGColorForRating(rating: number): string {
  if (rating >= 75) return 'bg-green-700';
  if (rating >= 65) return 'bg-orange-400';
  return 'bg-red-400';
}

export function getTextColorForRating(rating: number): string {
  if (rating >= 75) return 'text-green-500';
  if (rating >= 65) return 'text-orange-400';
  return 'text-red-500';
}

// ── Current season ─────────────────────────────────────────────────────────

const _now = new Date();
const _m = _now.getMonth();
export const currentSeason = getSeasonForMonth(_m) as 'WINTER' | 'SPRING' | 'SUMMER' | 'FALL';
export const currentYear = _now.getFullYear();
export const nextSeason = getSeasonForMonth(_m + 3) as 'WINTER' | 'SPRING' | 'SUMMER' | 'FALL';
export const nextYear = currentYear + (nextSeason === 'WINTER' ? 1 : 0);

// ── File extension lists (mirrors Hayase utils.ts) ─────────────────────────

export const subtitleExtensions = ['srt', 'vtt', 'ass', 'ssa', 'sub', 'txt'];
export const subRx = new RegExp(`\\.(${subtitleExtensions.join('|')})$`, 'i');

export const videoExtensions = [
  '3g2','3gp','asf','avi','dv','flv','gxf','m2ts','m4a','m4b','m4p','m4r','m4v',
  'mkv','mov','mp4','mpd','mpeg','mpg','mxf','nut','ogm','ogv','swf','ts','vob',
  'webm','wmv','wtv',
];
export const videoRx = new RegExp(`\\.(${videoExtensions.join('|')})$`, 'i');

export const fontExtensions = [
  'ttf','ttc','woff','woff2','otf','cff','otc','pfa','pfb','pcf','fnt','bdf','pfr','eot',
];
export const fontRx = new RegExp(`\\.(${fontExtensions.join('|')})$`, 'i');

// ── Misc utilities (mirrors Hayase utils.ts) ────────────────────────────────

export async function safefetch<T>(
  _fetch: typeof fetch,
  ...args: Parameters<typeof fetch>
): Promise<T | null> {
  try {
    const res = await _fetch(...args);
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

export function arrayEqual<T>(a: T[], b: T[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

export function nextTick(): Promise<void> {
  return new Promise<void>(resolve => queueMicrotask(resolve));
}

/** Converts a country code to its flag emoji (mirrors Hayase's codeToEmoji) */
export function codeToEmoji(c: string): string {
  if (c === 'ALL') return '🌎';
  return c.replace(/./g, ch => String.fromCodePoint(0x1f1a5 + ch.charCodeAt(0)));
}

/** Key-by-object HashMap (mirrors Hayase's HashMap class) */
export class HashMap<K extends object, T> {
  private map = new Map<string, T>();

  private _id(k: K): string {
    return JSON.stringify(k, Object.keys(k).sort());
  }

  has(k: K): boolean { return this.map.has(this._id(k)); }
  add(k: K, o: T): this { this.map.set(this._id(k), o); return this; }
  delete(k: K): boolean { return this.map.delete(this._id(k)); }
  clear(): void { this.map.clear(); }
  get size(): number { return this.map.size; }
  values(): IterableIterator<T> { return this.map.values(); }
  [Symbol.iterator](): IterableIterator<T> { return this.values(); }
}

/** trace.moe anime lookup (mirrors Hayase's traceAnime) */
export interface TraceAnime {
  anilist: number;
  filename: string;
  episode: number;
  from: number;
  to: number;
  similarity: number;
  video: string;
  image: string;
}

export async function traceAnime(image: File | string): Promise<TraceAnime[]> {
  let res: Response;
  if (image instanceof File) {
    res = await fetch('https://api.trace.moe/search?cutBorders', {
      method: 'POST',
      body: image,
      headers: { 'Content-type': image.type },
    });
  } else {
    res = await fetch(`https://api.trace.moe/search?cutBorders&url=${encodeURIComponent(image)}`);
  }
  const { result } = (await res.json()) as { result: TraceAnime[] };
  if (result.length) return result;
  throw new Error("Search Failed\nCouldn't find anime for specified image!");
}

/** toTS — mirrors Hayase's toTS exactly (full param support) */
export function toTSFull(sec: number, full?: number): string {
  if (isNaN(sec) || sec < 0) {
    switch (full) {
      case 1: return '0:00:00.00';
      case 2: return '0:00:00';
      case 3: return '00:00';
      default: return '0:00';
    }
  }
  const hours = Math.floor(sec / 3600);
  let minutes: string | number = Math.floor(sec / 60) - hours * 60;
  let seconds: string | number = full === 1 ? (sec % 60).toFixed(2) : Math.floor(sec % 60);
  if (minutes < 10 && (hours > 0 || full)) minutes = '0' + minutes;
  if (Number(seconds) < 10) seconds = '0' + seconds;
  return (hours > 0 || full === 1 || full === 2)
    ? `${hours}:${minutes}:${seconds}`
    : `${minutes}:${seconds}`;
}
