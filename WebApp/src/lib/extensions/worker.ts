/**
 * extensions/worker.ts — Mirrors Hayase's src/lib/modules/extensions/worker.ts
 *
 * Each extension is loaded in a sandboxed Web Worker (blob URL). The worker
 * exposes a thin async API: single/batch/movie/query/test/url.
 */

import type { TorrentResult, SearchOptions, TorrentQuery, TorrentSource, NZBSource } from './types';

// ─── Worker bootstrap script ────────────────────────────────────────────────
// This string is compiled into a Blob and launched as a Worker. It mirrors
// Hayase's worker.ts (expose/finalizer from 'abslink') but without the abslink
// dependency — we use a simple postMessage RPC instead.

const WORKER_BOOTSTRAP = /* js */`
let mod = null;

self.onmessage = async (e) => {
  const { id, method, args } = e.data;
  try {
    let result;
    switch (method) {
      case 'construct': {
        const code = args[0];
        const url = URL.createObjectURL(new Blob([code], { type: 'application/javascript' }));
        mod = (await import(url)).default;
        URL.revokeObjectURL(url);
        result = null;
        break;
      }
      case 'single':
        result = await mod.single({ ...args[0], fetch }, args[1]);
        break;
      case 'batch':
        result = await mod.batch({ ...args[0], fetch }, args[1]);
        break;
      case 'movie':
        result = await mod.movie({ ...args[0], fetch }, args[1]);
        break;
      case 'query':
        result = await mod.query(args[0], args[1], fetch);
        break;
      case 'test':
        result = await mod.test();
        break;
      case 'url':
        result = mod.url ?? null;
        break;
      default:
        throw new Error('Unknown method: ' + method);
    }
    self.postMessage({ id, result });
  } catch (err) {
    self.postMessage({ id, error: err instanceof Error ? err.message : String(err) });
  }
};
`;

// ─── ExtensionWorker ────────────────────────────────────────────────────────

export class ExtensionWorker {
  private worker: Worker;
  private pending = new Map<string, { resolve: (v: unknown) => void; reject: (e: Error) => void }>();
  private seq = 0;

  constructor(name: string) {
    const blob = new Blob([WORKER_BOOTSTRAP], { type: 'application/javascript' });
    const url = URL.createObjectURL(blob);
    this.worker = new Worker(url, { type: 'module', name });
    URL.revokeObjectURL(url);

    this.worker.onmessage = (e) => {
      const { id, result, error } = e.data;
      const cb = this.pending.get(id);
      if (!cb) return;
      this.pending.delete(id);
      if (error) cb.reject(new Error(error));
      else cb.resolve(result);
    };
  }

  private call<T>(method: string, ...args: unknown[]): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const id = `w_${++this.seq}`;
      this.pending.set(id, { resolve: resolve as (v: unknown) => void, reject });
      this.worker.postMessage({ id, method, args });
    });
  }

  construct(code: string): Promise<null> {
    return this.call('construct', code);
  }

  test(): Promise<boolean> {
    return this.call('test');
  }

  url(): Promise<string | null> {
    return this.call('url');
  }

  single(query: TorrentQuery, options?: SearchOptions): Promise<TorrentResult[]> {
    return this.call('single', query, options);
  }

  batch(query: TorrentQuery, options?: SearchOptions): Promise<TorrentResult[]> {
    return this.call('batch', query, options);
  }

  movie(query: TorrentQuery, options?: SearchOptions): Promise<TorrentResult[]> {
    return this.call('movie', query, options);
  }

  query(hash: string, options?: SearchOptions): Promise<string> {
    return this.call('query', hash, options);
  }

  destroy() {
    this.worker.terminate();
    this.pending.clear();
  }
}
