/**
 * extensions/storage.ts — Mirrors Hayase's src/lib/modules/extensions/storage.ts
 *
 * Manages persisted extension configs and option stores, and the CodeManager
 * which loads each extension's code into a sandboxed Web Worker.
 */

import { writable, get } from 'svelte/store';
import { ExtensionWorker } from './worker';
import type { ExtensionConfig, SearchOptions } from './types';

type ExtensionID = string;

type SavedExtensions = Record<ExtensionID, ExtensionConfig>;

type ExtensionOptions = {
  options: Record<string, unknown>;
  enabled: boolean;
};

// ─── Persisted stores ────────────────────────────────────────────────────────

function loadLS<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key);
    if (raw) return JSON.parse(raw) as T;
  } catch {}
  return fallback;
}

function makePersisted<T>(key: string, initial: T) {
  const store = writable<T>(loadLS(key, initial));
  store.subscribe((v) => {
    try { localStorage.setItem(key, JSON.stringify(v)); } catch {}
  });
  return store;
}

export const savedConfigs = makePersisted<SavedExtensions>('extensions', {});
export const savedOptions = makePersisted<Record<ExtensionID, ExtensionOptions>>('extensionoptions', {});

// ─── URL helpers (mirrors storage.ts jsonurl / jsurl) ─────────────────────

/** Resolve config JSON URL — supports http[s]://, gh:, npm: prefixes */
function jsonurl(url: string): string {
  if (url.startsWith('http')) return url;
  const { pathname, protocol } = new URL(url);
  if (protocol !== 'gh:' && protocol !== 'npm:') throw new Error('Invalid URL');
  const processed = `https://esm.sh${protocol === 'gh:' ? '/gh' : ''}/${pathname}`;
  if (processed.endsWith('.json')) return processed;
  return `${processed}/index.json`;
}

/** Resolve extension JS URL — supports http[s]://, gh:, npm: prefixes */
function jsurl(url: string): string {
  if (url.startsWith('http')) return url;
  const parsedUrl = new URL(url);
  if (parsedUrl.protocol === 'gh:') {
    const [username, repo, ...pathParts] = parsedUrl.pathname.split('/');
    const path = pathParts.join('/');
    return `https://esm.sh/gh/${username}/${repo}/es2022/${path}.mjs`;
  } else if (parsedUrl.protocol === 'npm:') {
    const [pkg, ...pathParts] = parsedUrl.pathname.split('/');
    const path = pathParts.join('/');
    return `https://esm.sh/${pkg}/es2022/${path}.mjs`;
  }
  throw new Error('Invalid URL');
}

async function safejson<T>(url: string): Promise<T | null> {
  try {
    const res = await fetch(jsonurl(url));
    return await res.json() as T;
  } catch { return null; }
}

async function safejs(url: string): Promise<string | null> {
  try {
    const res = await fetch(jsurl(url));
    return await res.text();
  } catch { return null; }
}

// ─── CodeManager ─────────────────────────────────────────────────────────────

class CodeManager {
  extensions: Map<ExtensionID, ExtensionWorker> = new Map();

  async delete(id: ExtensionID) {
    if (this.extensions.has(id)) {
      this.extensions.get(id)!.destroy();
      this.extensions.delete(id);
    }
  }

  async initiate(configs: ExtensionConfig[]) {
    const promises = configs.map(async (c) => {
      // Try to load cached code from localStorage
      const cached = localStorage.getItem(`ext_code_${c.id}`);
      if (cached) {
        try { await this._loadWorker(cached, c.id); } catch {}
      }
    });
    await Promise.allSettled(promises);
  }

  async downloadScripts(configs: ExtensionConfig[], update = false) {
    const invalidIDs: ExtensionID[] = [];
    for (const config of configs) {
      if (this.extensions.has(config.id) && !update) continue;
      const code = await safejs(config.code);
      if (!code) { invalidIDs.push(config.id); continue; }
      try {
        await this._loadWorker(code, config.id);
        localStorage.setItem(`ext_code_${config.id}`, code);
      } catch {
        invalidIDs.push(config.id);
      }
    }
    return invalidIDs;
  }

  async _loadWorker(code: string, id: string) {
    // Tear down any existing worker for this ID
    if (this.extensions.has(id)) {
      this.extensions.get(id)!.destroy();
      this.extensions.delete(id);
    }
    const worker = new ExtensionWorker(id);
    await worker.construct(code);
    this.extensions.set(id, worker);
    // Run test with 5s timeout (non-fatal)
    try {
      await Promise.race([
        worker.test(),
        new Promise<never>((_, reject) => setTimeout(() => reject(new Error('Extension check timed out.')), 5000)),
      ]);
    } catch (e) {
      console.warn(`[extensions] worker test failed for ${id}:`, e);
    }
  }
}

// ─── ConfigManager (exported as `storage`) ───────────────────────────────────

class ConfigManager {
  codeManager = new CodeManager();
  ready: Promise<void>;

  constructor() {
    this.ready = this.codeManager.initiate(Object.values(get(savedConfigs)));
    this.update(); // check for updates in background
  }

  private _validateConfig(config: Partial<ExtensionConfig> | null): boolean {
    return !!config && ['name', 'version', 'id', 'type', 'accuracy', 'icon', 'update', 'code'].every(p => p in (config ?? {}));
  }

  private _ensureOptions(ids: ExtensionID[], enabled = true) {
    savedOptions.update(opts => {
      for (const id of ids) {
        if (!(id in opts)) opts[id] = { options: {}, enabled };
      }
      return opts;
    });
  }

  private _updateSaved(configs: ExtensionConfig[]) {
    savedConfigs.update(value => {
      const next = { ...value };
      for (const c of configs) next[c.id] = c;
      return next;
    });
  }

  configs(): SavedExtensions {
    return get(savedConfigs);
  }

  /** Import extensions from a JSON config URL. Mirrors ConfigManager.import(). */
  async import(url: string): Promise<void> {
    await this.ready;
    const config = await safejson<ExtensionConfig[]>(url);
    if (!config) throw new Error('Make sure the link you provided is a valid JSON config for Hayase', { cause: 'Invalid extension URI' });

    const attemptedOverrides: string[] = [];
    const validConfigs: ExtensionConfig[] = [];
    for (const c of config) {
      if (!this._validateConfig(c)) throw new Error('Make sure the link you provided is a valid extension config for Hayase', { cause: 'Invalid extension config' });
      if (c.id in this.configs()) {
        attemptedOverrides.push(c.id);
      } else {
        validConfigs.push(c);
      }
    }

    const invalidExtensions = await this.codeManager.downloadScripts(validConfigs);
    const validExtensions = validConfigs.filter(c => !invalidExtensions.includes(c.id));
    this._ensureOptions(validExtensions.map(c => c.id));
    this._updateSaved(validExtensions);

    if (attemptedOverrides.length) {
      throw new Error(
        `The following extensions already exist and were not imported:\n\n${attemptedOverrides.join(', ')}\n\nDelete them first to re-import.`,
        { cause: 'Extension Already Exists!' }
      );
    }
  }

  /** Delete a single extension by ID. */
  async delete(id: ExtensionID): Promise<void> {
    await this.ready;
    await this.codeManager.delete(id);
    localStorage.removeItem(`ext_code_${id}`);
    savedConfigs.update(c => { const n = { ...c }; delete n[id]; return n; });
    savedOptions.update(o => { const n = { ...o }; delete n[id]; return n; });
  }

  /** Update all extensions that have an `update` URL and a newer version. */
  async update(): Promise<void> {
    await this.ready;
    const currentConfigs = this.configs();
    const updateURLs = new Set(
      Object.values(currentConfigs).map(({ update }) => update).filter((u): u is string => !!u)
    );
    const newConfigs = (await Promise.all([...updateURLs].map(u => safejson<ExtensionConfig[]>(u))))
      .filter(Boolean).flat() as ExtensionConfig[];

    const safeToUpdate = newConfigs.filter(
      f => this._validateConfig(f) && (
        (currentConfigs[f.id]?.update === f.update && f.version !== currentConfigs[f.id]?.version) ||
        !currentConfigs[f.id]
      )
    );

    const invalidExtensions = await this.codeManager.downloadScripts(safeToUpdate, true);
    const validExtensions = safeToUpdate.filter(c => !invalidExtensions.includes(c.id));
    this._ensureOptions(validExtensions.map(c => c.id), true);
    this._updateSaved(validExtensions);
  }

  /** Toggle a single extension's enabled state. */
  setEnabled(id: ExtensionID, enabled: boolean): void {
    savedOptions.update(opts => {
      if (opts[id]) opts[id]!.enabled = enabled;
      return opts;
    });
  }

  /** Update a single option value for an extension. */
  setOption(id: ExtensionID, key: string, value: unknown): void {
    savedOptions.update(opts => {
      if (opts[id]) (opts[id]!.options as Record<string, unknown>)[key] = value;
      return opts;
    });
  }
}

export const storage = new ConfigManager();
