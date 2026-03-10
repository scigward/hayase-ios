<script lang="ts">
  import { searchRequest, closeSearch } from '../lib/store';
  import { bridge, type TorrentSearchResult } from '../lib/bridge';
  import { fastPrettyBytes, cn } from '../lib/util';
  import { onMount } from 'svelte';

  let results: TorrentSearchResult[] = [];
  let loading = false;
  let error = '';
  let query = '';
  let adding: string | null = null;

  $: req = $searchRequest;

  $: if (req) {
    query = `${req.animeTitle} ${req.episode > 1 ? req.episode : ''}`.trim();
    doSearch();
  }

  async function doSearch() {
    if (!query.trim()) return;
    loading = true; error = ''; results = [];
    try {
      results = await bridge.torrentSearch(query) ?? [];
    } catch (e: any) {
      error = e?.message ?? 'Search failed';
    }
    loading = false;
  }

  async function addTorrent(r: TorrentSearchResult) {
    if (!req || adding) return;
    adding = r.magnetURL || r.downloadURL;
    try {
      const hash = await bridge.torrentAdd(r.magnetURL || r.downloadURL, req.animeTitle, req.anilistID);
      const files = await bridge.torrentFiles(hash);
      const vid = files?.find(f => /\.(mkv|mp4|avi|webm)$/i.test(f.name));
      if (vid) await bridge.playerOpen(hash, vid.index, req.animeTitle, req.anilistID, req.episode);
      closeSearch();
    } catch (e: any) {
      error = e?.message ?? 'Failed to add torrent';
    }
    adding = null;
  }

  function seederColor(n: number) {
    if (n >= 20) return 'text-green-400';
    if (n >= 5)  return 'text-yellow-400';
    return 'text-red-400';
  }
</script>

{#if req}
  <!-- Backdrop -->
  <button class="fixed inset-0 bg-black/70 z-40 backdrop-blur-sm" on:click={closeSearch} />

  <!-- Sheet (slides up from bottom) -->
  <div class="fixed inset-x-0 bottom-0 z-50 flex flex-col bg-neutral-950 rounded-t-2xl max-h-[85vh]"
       style="padding-bottom: env(safe-area-inset-bottom);">

    <!-- Handle -->
    <div class="flex justify-center pt-3 pb-1">
      <div class="w-10 h-1 rounded-full bg-neutral-700" />
    </div>

    <!-- Header -->
    <div class="px-4 py-3 border-b border-border">
      <h2 class="font-black text-lg">{req.animeTitle}</h2>
      <p class="text-xs text-muted-foreground">Episode {req.episode}</p>
    </div>

    <!-- Search bar -->
    <div class="px-4 py-3 border-b border-border">
      <div class="flex gap-2">
        <input
          class="flex-1 bg-neutral-900 rounded-xl px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground outline-none"
          bind:value={query}
          placeholder="Search torrents…"
          on:keydown={e => e.key === 'Enter' && doSearch()}
        />
        <button
          class="bg-white text-black font-black text-xs px-4 py-2 rounded-xl active:scale-95 transition-transform"
          on:click={doSearch}
        >Search</button>
      </div>
    </div>

    <!-- Results -->
    <div class="flex-1 overflow-y-auto" style="-webkit-overflow-scrolling:touch;">
      {#if loading}
        <div class="flex justify-center py-12">
          <div class="w-8 h-8 border-2 border-neutral-700 border-t-white rounded-full animate-spin-slow" />
        </div>
      {:else if error}
        <div class="text-center py-10 text-sm text-red-400">{error}</div>
      {:else if results.length === 0}
        <div class="text-center py-12 text-muted-foreground text-sm">No results found</div>
      {:else}
        {#each results as r (r.magnetURL || r.downloadURL)}
          <button
            class="flex items-center gap-3 px-4 py-3 w-full text-left border-b border-border/50 active:bg-white/5 transition-colors"
            on:click={() => addTorrent(r)}
            disabled={!!adding}
          >
            <div class="flex flex-col flex-1 min-w-0">
              <span class="text-sm font-bold line-clamp-2 leading-tight">{r.name}</span>
              <div class="flex flex-wrap gap-x-3 gap-y-0.5 mt-1 text-xs text-muted-foreground">
                <span class={seederColor(r.seeders)}>{r.seeders} seeders</span>
                {#if r.sizeMB > 0}
                  <span>{fastPrettyBytes(r.sizeMB * 1024 * 1024)}</span>
                {/if}
                {#if r.leechers > 0}
                  <span>{r.leechers} leechers</span>
                {/if}
              </div>
            </div>
            {#if adding === (r.magnetURL || r.downloadURL)}
              <div class="w-5 h-5 border-2 border-neutral-600 border-t-white rounded-full animate-spin-slow shrink-0" />
            {:else}
              <svg class="shrink-0 text-muted-foreground" xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="8 12 12 16 16 12"/><line x1="12" y1="8" x2="12" y2="16"/></svg>
            {/if}
          </button>
        {/each}
      {/if}
      <div class="h-4" />
    </div>
  </div>
{/if}
