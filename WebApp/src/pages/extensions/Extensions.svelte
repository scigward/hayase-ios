<script lang="ts">
  /**
   * Extensions.svelte — Port of Hayase's settings/extensions/+page.svelte
   *
   * Shows installed extensions with enable/disable toggle and delete button.
   * Provides an "Add Extension" input to import from a URL (gh:, npm:, https://).
   * Mirrors the Hayase Extensions component (src/lib/components/ui/extensions).
   */
  import { storage, savedConfigs, savedOptions } from '../../lib/extensions/storage';
  import SettingCard from '../../components/SettingCard.svelte';

  let importURL = '';
  let importError = '';
  let importLoading = false;

  const qualities = ['', '480', '720', '1080', '2160'] as const;
  const qualityLabels: Record<string, string> = { '': 'Any', '480': '480p', '720': '720p', '1080': '1080p', '2160': '4K' };

  async function handleImport() {
    if (!importURL.trim()) return;
    importError = '';
    importLoading = true;
    try {
      await storage.import(importURL.trim());
      importURL = '';
    } catch (e) {
      importError = (e as Error).message;
    } finally {
      importLoading = false;
    }
  }

  async function handleDelete(id: string) {
    await storage.delete(id);
  }

  function toggleEnabled(id: string, enabled: boolean) {
    storage.setEnabled(id, enabled);
  }
</script>

<div class="flex flex-col gap-4">
  <!-- ── Lookup Settings ─────────────────────────────────────────────────── -->
  <div class="font-weight-bold text-xl font-bold">Lookup Settings</div>

  <!-- ── Add Extension ──────────────────────────────────────────────────── -->
  <div class="font-weight-bold text-xl font-bold">Extension Settings</div>

  <SettingCard
    title="Add Extension"
    description="Paste a JSON config URL (https://, gh:username/repo, npm:pkg). The URL must point to a valid Hayase extension config."
  >
    <div class="flex gap-2 w-full mt-2">
      <input
        type="url"
        placeholder="https://example.com/extension.json"
        bind:value={importURL}
        class="flex-1 min-w-0 bg-muted rounded-lg px-3 py-1.5 text-sm text-foreground border border-border outline-none focus:ring-1 focus:ring-ring"
        on:keydown={(e) => e.key === 'Enter' && handleImport()}
      />
      <button
        class="shrink-0 bg-foreground text-background text-sm font-bold px-4 py-1.5 rounded-lg disabled:opacity-50"
        disabled={importLoading || !importURL.trim()}
        on:click={handleImport}
      >
        {importLoading ? '…' : 'Add'}
      </button>
    </div>
    {#if importError}
      <p class="text-destructive text-xs mt-1">{importError}</p>
    {/if}
  </SettingCard>

  <!-- ── Installed Extensions ───────────────────────────────────────────── -->
  {#each Object.entries($savedConfigs) as [id, cfg]}
    {@const opt = $savedOptions[id] ?? { enabled: true, options: {} }}
    <div class="bg-card rounded-xl border border-border overflow-hidden">
      <!-- Header row -->
      <div class="flex items-center gap-3 px-4 py-3">
        <!-- Icon -->
        <img
          src={cfg.icon}
          alt={cfg.name}
          class="w-10 h-10 rounded-lg object-cover shrink-0 bg-muted"
          on:error={(e) => { (e.currentTarget as HTMLImageElement).src = ''; }}
        />

        <!-- Name + description -->
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="font-bold text-sm truncate">{cfg.name}</span>
            <span class="text-[10px] text-muted-foreground border border-border rounded px-1">{cfg.version}</span>
            <span class="text-[10px] uppercase font-bold px-1.5 py-0.5 rounded-full
              {cfg.type === 'torrent' ? 'bg-blue-500/20 text-blue-400' : cfg.type === 'nzb' ? 'bg-orange-500/20 text-orange-400' : 'bg-green-500/20 text-green-400'}">
              {cfg.type}
            </span>
          </div>
          <p class="text-xs text-muted-foreground line-clamp-1 mt-0.5">{cfg.description ?? ''}</p>
        </div>

        <!-- Enable toggle -->
        <label class="relative inline-flex items-center cursor-pointer shrink-0">
          <input
            type="checkbox"
            class="sr-only peer"
            checked={opt.enabled}
            on:change={(e) => toggleEnabled(id, (e.currentTarget as HTMLInputElement).checked)}
          />
          <div class="w-10 h-5 bg-muted rounded-full peer peer-checked:bg-[rgb(61,180,242)] transition-colors" />
          <div class="absolute left-0.5 top-0.5 bg-white w-4 h-4 rounded-full transition-transform peer-checked:translate-x-5" />
        </label>
      </div>

      <!-- Per-extension options (if any) -->
      {#if cfg.options && Object.keys(cfg.options).length > 0}
        <div class="border-t border-border px-4 py-3 flex flex-col gap-3">
          {#each Object.entries(cfg.options) as [key, spec]}
            <div class="flex items-start justify-between gap-3">
              <div class="flex-1 min-w-0">
                <div class="text-sm font-semibold">{key}</div>
                <div class="text-xs text-muted-foreground mt-0.5">{spec.description}</div>
              </div>
              {#if spec.type === 'boolean'}
                <label class="relative inline-flex items-center cursor-pointer shrink-0 mt-0.5">
                  <input
                    type="checkbox"
                    class="sr-only peer"
                    checked={!!(opt.options as Record<string, unknown>)[key] ?? spec.default}
                    on:change={(e) => storage.setOption(id, key, (e.currentTarget as HTMLInputElement).checked)}
                  />
                  <div class="w-10 h-5 bg-muted rounded-full peer peer-checked:bg-[rgb(61,180,242)] transition-colors" />
                  <div class="absolute left-0.5 top-0.5 bg-white w-4 h-4 rounded-full transition-transform peer-checked:translate-x-5" />
                </label>
              {:else if spec.type === 'select' && spec.values}
                <select
                  class="bg-neutral-800 text-foreground text-xs font-bold rounded-lg px-2 py-1 border border-border outline-none shrink-0"
                  value={(opt.options as Record<string, unknown>)[key] ?? spec.default}
                  on:change={(e) => storage.setOption(id, key, (e.currentTarget as HTMLSelectElement).value)}
                >
                  {#each spec.values as v}
                    <option value={v}>{String(v)}</option>
                  {/each}
                </select>
              {:else if spec.type === 'number'}
                <input
                  type="number"
                  class="bg-neutral-800 text-foreground text-xs font-bold rounded-lg px-2 py-1 border border-border outline-none w-20 shrink-0 text-right"
                  value={(opt.options as Record<string, unknown>)[key] ?? spec.default}
                  on:change={(e) => storage.setOption(id, key, Number((e.currentTarget as HTMLInputElement).value))}
                />
              {:else}
                <input
                  type="text"
                  class="bg-neutral-800 text-foreground text-xs font-bold rounded-lg px-2 py-1 border border-border outline-none w-28 shrink-0 text-right"
                  value={(opt.options as Record<string, unknown>)[key] ?? spec.default}
                  on:change={(e) => storage.setOption(id, key, (e.currentTarget as HTMLInputElement).value)}
                />
              {/if}
            </div>
          {/each}
        </div>
      {/if}

      <!-- Delete row -->
      <div class="border-t border-border px-4 py-2 flex items-center justify-between">
        <div class="text-xs text-muted-foreground">
          {cfg.accuracy} accuracy · {cfg.media}
          {#if cfg.url}· <span class="font-mono">{new URL(cfg.url).hostname}</span>{/if}
        </div>
        <button
          class="text-destructive text-xs font-bold px-3 py-1 rounded-lg bg-destructive/10 active:opacity-70"
          on:click={() => handleDelete(id)}
        >
          Remove
        </button>
      </div>
    </div>
  {/each}

  {#if Object.keys($savedConfigs).length === 0}
    <div class="text-sm text-muted-foreground text-center py-8 border border-dashed border-border rounded-xl">
      No extensions installed.<br />
      Add one using the form above.
    </div>
  {/if}
</div>
