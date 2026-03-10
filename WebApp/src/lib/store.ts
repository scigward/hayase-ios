/**
 * store.ts — Application state stores + client-side router.
 * Mirrors Hayase's watchProgress.ts, settings/defaults.ts, and writable stores.
 */
import { writable, derived, get } from 'svelte/store';
import { safeLocalStorage } from './util';

// ── Router ─────────────────────────────────────────────────────────────────

export type Tab = 'home' | 'search' | 'downloads' | 'schedule' | 'settings';

export type Route =
  | { page: 'home' }
  | { page: 'search'; query?: string; genre?: string }
  | { page: 'anime'; id: number }
  | { page: 'downloads' }
  | { page: 'schedule' }
  | { page: 'settings' };

export const currentTab  = writable<Tab>('home');
export const currentRoute = writable<Route>({ page: 'home' });

// History stack for back navigation
const _history: Route[] = [];

export function navigate(r: Route) {
  _history.push(get(currentRoute));
  currentRoute.set(r);
  // Keep tab in sync
  if (r.page === 'home') currentTab.set('home');
  else if (r.page === 'search') currentTab.set('search');
  else if (r.page === 'downloads') currentTab.set('downloads');
  else if (r.page === 'settings') currentTab.set('settings');
}

export function navigateTab(tab: Tab) {
  _history.length = 0; // reset history on tab switch
  currentTab.set(tab);
  currentRoute.set({ page: tab } as Route);
}

export function goBack(): boolean {
  const prev = _history.pop();
  if (prev) {
    currentRoute.set(prev);
    return true;
  }
  return false;
}

// ── Torrent search modal ───────────────────────────────────────────────────

export interface SearchRequest {
  animeTitle: string;
  anilistID: number;
  episode: number;
}
export const searchRequest = writable<SearchRequest | null>(null);

export function openSearch(req: SearchRequest) {
  searchRequest.set(req);
}
export function closeSearch() {
  searchRequest.set(null);
}

// ── Watch progress (mirrors Hayase's watchProgress.ts) ────────────────────

export interface WatchProgress {
  episode: number;
  currentTime: number;
  safeduration: number;
}

function loadProgress(): Record<number, WatchProgress> {
  return safeLocalStorage<Record<number, WatchProgress>>('watchProgress') ?? {};
}

const _progressStore = writable<Record<number, WatchProgress>>(loadProgress());

_progressStore.subscribe(v => {
  try { localStorage.setItem('watchProgress', JSON.stringify(v)); } catch {}
});

export function getAnimeProgress(mediaId: number): WatchProgress | undefined {
  return get(_progressStore)[mediaId];
}

export function setAnimeProgress(mediaId: number, progress: WatchProgress) {
  _progressStore.update(d => { d[mediaId] = progress; return d; });
}

export const progressStore = _progressStore;

export function liveProgress(mediaId: number) {
  return derived(_progressStore, d => {
    const e = d[mediaId];
    if (!e) return null;
    return {
      episode: e.episode,
      progress: Math.ceil((e.currentTime / e.safeduration) * 100),
      currentTime: e.currentTime,
    };
  });
}

// ── Settings (matches Hayase's defaults.ts) ────────────────────────────────

export interface Settings {
  playerAutoplay: boolean;
  playerAutocomplete: boolean;
  playerPause: boolean;
  searchQuality: '480' | '720' | '1080' | '1440' | '2160';
  searchAutoSelect: boolean;
  lookupPreference: 'quality' | 'size' | 'seeders';
  showHentai: boolean;
  hideSpoilers: boolean;
  subtitleLanguage: string;
  audioLanguage: string;
}

const SETTINGS_DEFAULTS: Settings = {
  playerAutoplay: true,
  playerAutocomplete: true,
  playerPause: true,
  searchQuality: '1080',
  searchAutoSelect: true,
  lookupPreference: 'quality',
  showHentai: false,
  hideSpoilers: false,
  subtitleLanguage: 'eng',
  audioLanguage: 'jpn',
};

function loadSettings(): Settings {
  const saved = safeLocalStorage<Partial<Settings>>('settings');
  return { ...SETTINGS_DEFAULTS, ...saved };
}

export const settings = writable<Settings>(loadSettings());

settings.subscribe(v => {
  try { localStorage.setItem('settings', JSON.stringify(v)); } catch {}
});

// ── Banner (shared between home banner + anime detail) ────────────────────

export const bannerMedia = writable<any | null>(null);
export const hideBanner  = writable(false);

// ── Continue Watching (persisted) ─────────────────────────────────────────

export interface ContinueEntry {
  mediaId: number;
  episode: number;
  currentTime: number;
  duration: number;
  title: string;
  cover: string;
  updatedAt: number;
}

function loadContinue(): ContinueEntry[] {
  return safeLocalStorage<ContinueEntry[]>('continueWatching') ?? [];
}

export const continueWatching = writable<ContinueEntry[]>(loadContinue());

continueWatching.subscribe(v => {
  try { localStorage.setItem('continueWatching', JSON.stringify(v)); } catch {}
});

export function addContinueEntry(entry: ContinueEntry) {
  continueWatching.update(list => {
    const filtered = list.filter(e => e.mediaId !== entry.mediaId);
    return [entry, ...filtered].slice(0, 20);
  });
}

export function removeContinueEntry(mediaId: number) {
  continueWatching.update(list => list.filter(e => e.mediaId !== mediaId));
}

// ── Toasts ────────────────────────────────────────────────────────────────

export interface Toast {
  id: string;
  message: string;
  type: 'info' | 'success' | 'error';
}

export const toasts = writable<Toast[]>([]);

export function addToast(message: string, type: Toast['type'] = 'info', duration = 3000) {
  const id = Math.random().toString(36).slice(2);
  toasts.update(t => [...t, { id, message, type }]);
  setTimeout(() => toasts.update(t => t.filter(x => x.id !== id)), duration);
}

export function removeToast(id: string) {
  toasts.update(t => t.filter(x => x.id !== id));
}
