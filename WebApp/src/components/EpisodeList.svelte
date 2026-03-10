<!--
  EpisodeList.svelte — mirrors Hayase's EpisodesList.svelte.
  Shows paginated episodes from ani.zip, 16 per page.
  Clicking an episode opens the torrent SearchModal.
-->
<script lang="ts">
  import { openSearch } from '../lib/store';
  import type { AniZipResponse, AniZipEpisode } from '../lib/anizip';
  import type { AniListMedia } from '../lib/anilist';
  import { cn } from '../lib/util';
  import LoadImg from './LoadImg.svelte';

  export let media: AniListMedia;
  export let zipData: AniZipResponse | null = null;

  const PER_PAGE = 16;
  let page = 0;

  $: episodes = Object.entries(zipData?.episodes ?? {})
    .filter(([k]) => !isNaN(Number(k)) && Number(k) > 0)
    .sort((a, b) => Number(a[0]) - Number(b[0]))
    .map(([k, v]) => ({ number: Number(k), ...v }));

  $: totalPages = Math.ceil(episodes.length / PER_PAGE);
  $: pageEps = episodes.slice(page * PER_PAGE, (page + 1) * PER_PAGE);

  function watchEpisode(epNum: number) {
    openSearch({
      animeTitle: media.title?.userPreferred ?? media.title?.romaji ?? '',
      anilistID: media.id,
      episode: epNum,
    });
  }

  function formatAirdate(dateStr?: string): string {
    if (!dateStr) return '';
    try {
      return new Date(dateStr).toLocaleDateString('en-US', {
        year: 'numeric', month: 'short', day: 'numeric',
      });
    } catch { return dateStr; }
  }
</script>

<div class="flex flex-col gap-0">
  <!-- Episode cards -->
  {#if episodes.length === 0}
    <div class="flex flex-col items-center justify-center py-16 text-muted-foreground gap-2">
      <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="7" width="20" height="15" rx="2" ry="2"/><polyline points="17 2 12 7 7 2"/></svg>
      <span class="text-sm">No episodes available yet</span>
    </div>
  {:else}
    {#each pageEps as ep (ep.number)}
      <button
        class="flex items-start gap-3 p-3 active:bg-white/5 rounded-xl text-left w-full transition-colors"
        on:click={() => watchEpisode(ep.number)}
      >
        <!-- Thumbnail -->
        <div class="relative shrink-0 w-36 h-20 rounded-lg overflow-hidden bg-neutral-900">
          {#if ep.image}
            <LoadImg src={ep.image} alt="Episode {ep.number}" class="w-full h-full" />
          {:else}
            <div class="w-full h-full flex items-center justify-center bg-neutral-900">
              <span class="text-muted-foreground text-xs font-bold">EP {ep.number}</span>
            </div>
          {/if}
          <!-- Play icon overlay -->
          <div class="absolute inset-0 flex items-center justify-center opacity-0 hover:opacity-100 transition-opacity bg-black/40">
            <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="white"><circle cx="12" cy="12" r="10"/><polygon points="10 8 16 12 10 16 10 8" fill="black"/></svg>
          </div>
        </div>

        <!-- Text -->
        <div class="flex-1 min-w-0 py-0.5">
          <div class="font-bold text-[12.8px] line-clamp-1 text-foreground">
            {ep.number}. {ep.title?.en ?? ep.title?.['x-jat'] ?? 'Episode ' + ep.number}
          </div>
          {#if ep.summary ?? ep.overview}
            <div class="text-[9.6px] text-muted-foreground line-clamp-2 mt-1">
              {ep.summary ?? ep.overview}
            </div>
          {/if}
          <div class="flex items-center gap-2 mt-2 text-[9px] text-muted-foreground">
            {#if ep.airdate ?? ep.airDate}
              <span>{formatAirdate(ep.airdate ?? ep.airDate)}</span>
            {/if}
            {#if ep.length ?? ep.runtime}
              <span>·</span>
              <span>{ep.length ?? ep.runtime}m</span>
            {/if}
            {#if ep.rating}
              <span>·</span>
              <span>★ {ep.rating}</span>
            {/if}
          </div>
        </div>
      </button>
    {/each}

    <!-- Pagination -->
    {#if totalPages > 1}
      <div class="flex items-center justify-center gap-2 pt-4 pb-2">
        <button
          class="px-3 py-1.5 rounded-md bg-secondary text-sm font-bold disabled:opacity-30"
          disabled={page === 0}
          on:click={() => page--}
        >
          ‹ Prev
        </button>
        <span class="text-xs text-muted-foreground">
          {page + 1} / {totalPages}
        </span>
        <button
          class="px-3 py-1.5 rounded-md bg-secondary text-sm font-bold disabled:opacity-30"
          disabled={page >= totalPages - 1}
          on:click={() => page++}
        >
          Next ›
        </button>
      </div>
    {/if}
  {/if}
</div>
