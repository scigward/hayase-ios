/**
 * bridge.ts — JavaScript side of the WKWebView native bridge.
 *
 * Swift side: NativeBridge.swift (WKScriptMessageHandler named "bridge")
 *
 * Usage:
 *   import { bridge } from '$lib/bridge';
 *   const torrents = await bridge.torrentList();
 */

export interface TorrentFile {
  name: string;
  index: number;
  size: number;
  downloaded: number;
}

export interface TorrentStatus {
  hash: string;
  name: string;
  progress: number;          // 0.0–1.0
  downloadRate: number;      // bytes/sec
  uploadRate: number;        // bytes/sec
  totalWanted: number;       // bytes
  totalWantedDone: number;   // bytes
  seeders: number;
  leechers: number;
  connectedPeers: number;
  isPaused: boolean;
  isFinished: boolean;
  isSeed: boolean;
  files: TorrentFile[];
}

export interface TorrentSearchResult {
  name: string;
  magnetURL: string;
  downloadURL: string;
  seeders: number;
  leechers: number;
  downloads: number;
  sizeMB: number;
  nyaaId?: number;
}

export interface WatchProgress {
  currentTime: number;
  duration: number;
  episode: number;
  anilistID: number;
  fraction: number;
}

export interface ContinueWatchingEntry {
  anilistID: number;
  episode: number;
  fraction: number;
  currentTime: number;
  duration: number;
}

// ─── Internal plumbing ──────────────────────────────────────────────────────

type PendingCallback = {
  resolve: (value: unknown) => void;
  reject: (reason: Error) => void;
};

let callbackID = 0;
const pending = new Map<string, PendingCallback>();

/** Called by the Swift bridge to deliver a response. Injected via evaluateJavaScript. */
(window as any).onNativeBridgeResponse = (json: string) => {
  try {
    const msg = JSON.parse(json);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id)!;
      pending.delete(msg.id);
      if (msg.error) {
        reject(new Error(msg.error));
      } else {
        resolve(msg.result ?? null);
      }
    }
  } catch (e) {
    console.warn('[bridge] failed to parse response:', json, e);
  }
};

/** Event listeners for push events (torrent progress, etc.). */
const eventListeners = new Map<string, Set<(data: unknown) => void>>();

/** Called by Swift for push events (no callback ID). */
(window as any).onNativeBridgeEvent = (json: string) => {
  try {
    const msg = JSON.parse(json);
    if (msg.event) {
      const handlers = eventListeners.get(msg.event);
      handlers?.forEach(fn => fn(msg.data));
    }
  } catch (e) {
    console.warn('[bridge] failed to parse event:', json, e);
  }
};

function isNativeBridgeAvailable(): boolean {
  return !!(window as any).webkit?.messageHandlers?.bridge;
}

function call<T>(action: string, payload?: unknown): Promise<T> {
  if (!isNativeBridgeAvailable()) {
    // Running in a browser (dev mode) — return mock/empty data
    console.warn(`[bridge] native bridge not available for action: ${action}`);
    return Promise.resolve(null as unknown as T);
  }
  const id = `cb_${++callbackID}`;
  return new Promise<T>((resolve, reject) => {
    pending.set(id, {
      resolve: resolve as (v: unknown) => void,
      reject,
    });
    (window as any).webkit.messageHandlers.bridge.postMessage(
      JSON.stringify({ id, action, payload })
    );
    // Timeout after 30 seconds
    setTimeout(() => {
      if (pending.has(id)) {
        pending.delete(id);
        reject(new Error(`Bridge call timed out: ${action}`));
      }
    }, 30_000);
  });
}

// ─── Public API ─────────────────────────────────────────────────────────────

export const bridge = {
  /** Whether the native bridge is available (false in browser dev mode). */
  isAvailable: isNativeBridgeAvailable,

  // ── Torrent operations ────────────────────────────────────────────────

  /** Search nyaa.si and return results. */
  torrentSearch(query: string, sortBy = 'id', descending = true): Promise<TorrentSearchResult[]> {
    return call('torrent.search', { query, sortBy, descending });
  },

  /** Add a magnet or .torrent URL to the LibTorrent session. */
  torrentAdd(magnetOrURL: string, animeTitle: string, anilistID: number): Promise<string /* hash */> {
    return call('torrent.add', { magnetOrURL, animeTitle, anilistID });
  },

  /** Get status for all active torrents. */
  torrentList(): Promise<TorrentStatus[]> {
    return call('torrent.list');
  },

  /** Pause a torrent by its hex hash. */
  torrentPause(hash: string): Promise<void> {
    return call('torrent.pause', { hash });
  },

  /** Resume a paused torrent. */
  torrentResume(hash: string): Promise<void> {
    return call('torrent.resume', { hash });
  },

  /** Delete a torrent (optionally also delete files). */
  torrentDelete(hash: string, deleteFiles: boolean): Promise<void> {
    return call('torrent.delete', { hash, deleteFiles });
  },

  /** Get the list of files for a torrent. */
  torrentFiles(hash: string): Promise<TorrentFile[]> {
    return call('torrent.files', { hash });
  },

  // ── Video player ──────────────────────────────────────────────────────

  /** Present the native MPV player for a file in a torrent. */
  playerOpen(hash: string, fileIndex: number, title: string, anilistID: number, episode: number): Promise<void> {
    return call('player.open', { hash, fileIndex, title, anilistID, episode });
  },

  // ── Watch progress ────────────────────────────────────────────────────

  saveProgress(videoPath: string, currentTime: number, duration: number, anilistID: number, episode: number): Promise<void> {
    return call('progress.save', { videoPath, currentTime, duration, anilistID, episode });
  },

  getProgress(anilistID: number, episode: number): Promise<WatchProgress | null> {
    return call('progress.get', { anilistID, episode });
  },

  /** Returns recently-watched anilist IDs for "Continue Watching" section. */
  getContinueWatching(): Promise<ContinueWatchingEntry[]> {
    return call('progress.continueWatching');
  },

  // ── Event subscriptions ───────────────────────────────────────────────

  /** Subscribe to push events from Swift (e.g. torrent progress updates). */
  on<T>(event: string, handler: (data: T) => void): () => void {
    if (!eventListeners.has(event)) {
      eventListeners.set(event, new Set());
    }
    const typed = handler as (data: unknown) => void;
    eventListeners.get(event)!.add(typed);
    return () => eventListeners.get(event)?.delete(typed);
  },
};
