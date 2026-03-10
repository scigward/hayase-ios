<!--
  Downloads.svelte — mirrors Hayase's torrent client overview.
  Polls bridge.torrentList() every 2 seconds, shows live progress cards.
-->
<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { bridge, type TorrentStatus } from '../lib/bridge';
  import { openSearch } from '../lib/store';
  import { fastPrettyBytes, fastPrettyBits, eta, cn } from '../lib/util';

  let torrents: TorrentStatus[] = [];
  let interval: ReturnType<typeof setInterval>;
  let loading = true;
  let error = '';

  async function refresh() {
    try {
      torrents = await bridge.torrentList() ?? [];
      error = '';
    } catch (e: any) {
      error = e?.message ?? 'Failed to fetch downloads';
    }
    loading = false;
  }

  onMount(() => {
    refresh();
    interval = setInterval(refresh, 2000);
  });

  onDestroy(() => clearInterval(interval));

  async function togglePause(t: TorrentStatus) {
    if (t.isPaused) await bridge.torrentResume(t.hash);
    else await bridge.torrentPause(t.hash);
    refresh();
  }

  async function deleteTorrent(t: TorrentStatus, deleteFiles: boolean) {
    if (!confirm(`Delete "${t.name}"${deleteFiles ? ' and its files' : ''}?`)) return;
    await bridge.torrentDelete(t.hash, deleteFiles);
    refresh();
  }

  function speedStr(t: TorrentStatus) {
    if (t.isPaused) return 'Paused';
    if (t.isSeed || t.isFinished) return 'Seeding';
    return `↓ ${fastPrettyBits(t.downloadRate * 8)}/s`;
  }
</script>

<div class="flex flex-col h-full overflow-y-auto p-4 gap-4" style="-webkit-overflow-scrolling:touch;">

  <!-- Header -->
  <div class="pt-2">
    <h1 class="text-2xl font-black">Downloads</h1>
    <p class="text-sm text-muted-foreground mt-0.5">Active torrents</p>
  </div>

  {#if loading}
    {#each Array(3) as _}
      <div class="bg-neutral-950 rounded-xl p-4 space-y-3">
        <div class="h-4 w-3/4 bg-neutral-800 rounded shimmer" />
        <div class="h-2 w-full bg-neutral-800 rounded shimmer" />
        <div class="h-3 w-1/2 bg-neutral-800 rounded shimmer" />
      </div>
    {/each}

  {:else if error && torrents.length === 0}
    <div class="flex flex-col items-center justify-center py-16 gap-3 text-muted-foreground">
      <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
      <span class="text-sm">{error}</span>
    </div>

  {:else if torrents.length === 0}
    <div class="flex flex-col items-center justify-center py-16 gap-3 text-muted-foreground">
      <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="8 12 12 16 16 12"/><line x1="12" y1="8" x2="12" y2="16"/></svg>
      <span class="text-sm font-bold">No active downloads</span>
      <span class="text-xs text-center px-8">Search for an anime and tap "Watch Now" to start downloading.</span>
    </div>

  {:else}
    {#each torrents as t (t.hash)}
      {@const pct = Math.round(t.progress * 100)}
      {@const done = t.isFinished || t.isSeed}
      <div class="bg-neutral-950 rounded-xl p-4 space-y-3">

        <!-- Name + status badge -->
        <div class="flex items-start justify-between gap-2">
          <span class="font-bold text-sm line-clamp-2 flex-1">{t.name || 'Unknown'}</span>
          <span class={cn(
            'shrink-0 px-2 py-0.5 rounded-full text-xs font-black',
            done ? 'bg-blue-500/20 text-blue-400' :
            t.isPaused ? 'bg-yellow-500/20 text-yellow-400' :
            'bg-green-500/20 text-green-400'
          )}>
            {done ? 'Done' : t.isPaused ? 'Paused' : 'Downloading'}
          </span>
        </div>

        <!-- Progress bar -->
        <div>
          <div class="flex justify-between text-xs text-muted-foreground mb-1">
            <span>{pct}%</span>
            <span>{fastPrettyBytes(t.totalWantedDone)} / {fastPrettyBytes(t.totalWanted)}</span>
          </div>
          <div class="w-full h-1.5 bg-neutral-800 rounded-full overflow-hidden">
            <div
              class={cn('h-full rounded-full transition-all', done ? 'bg-blue-500' : 'bg-green-500')}
              style:width="{pct}%"
            />
          </div>
        </div>

        <!-- Stats row -->
        <div class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
          <span>{speedStr(t)}</span>
          {#if !done && !t.isPaused && t.downloadRate > 0 && t.totalWanted > t.totalWantedDone}
            <span>ETA: {eta((t.totalWanted - t.totalWantedDone) / t.downloadRate)}</span>
          {/if}
          <span>↑ {fastPrettyBits(t.uploadRate * 8)}/s</span>
          <span>{t.seeders} seeders · {t.leechers} leechers</span>
        </div>

        <!-- Actions -->
        <div class="flex gap-2 pt-1">
          <!-- Play (if has video files) -->
          {#if done}
            <button
              class="flex-1 flex items-center justify-center gap-1.5 bg-white text-black font-black text-xs py-2 rounded-full active:scale-95 transition-transform"
              on:click={async () => {
                const files = await bridge.torrentFiles(t.hash);
                const vid = files.find(f => /\.(mkv|mp4|avi|webm)$/i.test(f.name));
                if (vid) await bridge.playerOpen(t.hash, vid.index, t.name, 0, 0);
              }}
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
              Play
            </button>
          {/if}

          <!-- Pause / Resume -->
          <button
            class="flex items-center justify-center gap-1.5 bg-secondary text-foreground font-bold text-xs px-4 py-2 rounded-full active:scale-95 transition-transform"
            on:click={() => togglePause(t)}
          >
            {#if t.isPaused}
              <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
              Resume
            {:else}
              <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>
              Pause
            {/if}
          </button>

          <!-- Delete -->
          <button
            class="flex items-center justify-center bg-red-500/10 text-red-400 px-3 py-2 rounded-full active:scale-95 transition-transform"
            on:click={() => deleteTorrent(t, true)}
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/></svg>
          </button>
        </div>
      </div>
    {/each}
  {/if}

  <div class="h-2" />
</div>
