<!--
  AnimeDetail.svelte — mirrors Hayase's src/routes/app/anime/[id]/ layout + page.
  Banner → cover + title + badges + description + Watch Now → tabs (Episodes/Relations/Chars).
  --custom CSS variable driven by coverImage.color.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { goBack, openSearch, navigate } from '../lib/store';
  import { getMedia, type AniListMedia } from '../lib/anilist';
  import { episodes as getEpisodes, type AniZipResponse } from '../lib/anizip';
  import {
    banner, cover, mediaTitle, mediaStatus, mediaFormat,
    mediaSeason, mediaDesc, mediaDuration, getBGColorForRating,
    colors, cn
  } from '../lib/util';
  import LoadImg from '../components/LoadImg.svelte';
  import EpisodeList from '../components/EpisodeList.svelte';
  import CharacterGrid from '../components/CharacterGrid.svelte';

  export let id: number;

  let media: AniListMedia | null = null;
  let zipData: AniZipResponse | null = null;
  let loading = true;
  let error = '';
  let activeTab: 'episodes' | 'relations' | 'chars' = 'episodes';

  onMount(async () => {
    try {
      [media, zipData] = await Promise.all([
        getMedia(id),
        getEpisodes(id),
      ]);
    } catch (e: any) {
      error = e?.message ?? 'Failed to load';
    }
    loading = false;
  });

  $: customColor = media?.coverImage?.color ?? '#3d82f2';
  $: rgb = colors(customColor);

  function watchNow() {
    if (!media) return;
    openSearch({
      animeTitle: mediaTitle(media),
      anilistID: media.id,
      episode: (media.mediaListEntry?.progress ?? 0) + 1,
    });
  }
</script>

<div
  class="flex flex-col h-full overflow-y-auto"
  style="-webkit-overflow-scrolling: touch; --custom: {customColor}; --red: {rgb.r}; --green: {rgb.g}; --blue: {rgb.b};"
>
  <!-- Back button overlay (above safe area) -->
  <button
    class="fixed z-50 w-10 h-10 flex items-center justify-center rounded-full bg-black/60 backdrop-blur-sm text-white active:scale-95 transition-transform"
    style="top: max(0.75rem, env(safe-area-inset-top)); left: 0.75rem;"
    on:click={() => goBack()}
  >
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>
  </button>

  {#if loading}
    <div class="h-56 bg-neutral-900 shimmer" />
    <div class="px-4 pt-4 space-y-3">
      <div class="h-6 w-3/4 bg-neutral-800 rounded shimmer" />
      <div class="h-4 w-1/2 bg-neutral-800 rounded shimmer" />
      <div class="h-10 w-full bg-neutral-800 rounded-full shimmer" />
    </div>

  {:else if error}
    <div class="flex-1 flex items-center justify-center text-sm p-8 text-center text-red-400">{error}</div>

  {:else if media}

    <!-- Banner (h-56) -->
    <div class="relative h-56 shrink-0 banner-gr banner-gr-sm overflow-hidden">
      <LoadImg
        src={banner(media) ?? cover(media)}
        alt={mediaTitle(media)}
        color={media.coverImage?.color}
        class="w-full h-full object-cover"
      />
    </div>

    <!-- Content -->
    <div class="px-4 pt-4 pb-2">
      <!-- Cover + Title row -->
      <div class="flex gap-4 mb-4">
        <!-- Cover (pulled up over banner) -->
        <div class="shrink-0 w-28 h-40 rounded-xl overflow-hidden shadow-2xl -mt-16 border-2 border-background">
          <LoadImg
            src={cover(media)}
            alt={mediaTitle(media)}
            color={media.coverImage?.color}
            class="w-full h-full"
          />
        </div>

        <div class="flex flex-col pt-2 min-w-0">
          {#if media.title?.native}
            <p class="text-muted-foreground text-xs font-light line-clamp-1 mb-1">
              {media.title.native}
            </p>
          {/if}
          <h1 class="font-black text-xl text-white line-clamp-2 leading-tight text-shadow-lg">
            {mediaTitle(media)}
          </h1>
          {#if media.averageScore}
            <span class={cn(
              'mt-2 self-start px-2 py-0.5 rounded text-xs font-black text-white',
              getBGColorForRating(media.averageScore)
            )}>
              {media.averageScore}%
            </span>
          {/if}
        </div>
      </div>

      <!-- Badges -->
      <div class="flex flex-wrap gap-2 mb-3">
        {#if media.episodes}
          <span class="bg-custom/10 text-custom text-xs font-bold px-3 h-6 flex items-center rounded-full">
            {media.episodes} eps
          </span>
        {/if}
        {#if media.format}
          <span class="bg-white/10 text-white/80 text-xs font-bold px-3 h-6 flex items-center rounded-full">
            {mediaFormat(media)}
          </span>
        {/if}
        {#if media.status}
          <span class="bg-white/10 text-white/80 text-xs font-bold px-3 h-6 flex items-center rounded-full">
            {mediaStatus(media)}
          </span>
        {/if}
        {#if mediaSeason(media)}
          <span class="bg-white/10 text-white/80 text-xs font-bold px-3 h-6 flex items-center rounded-full capitalize">
            {mediaSeason(media)}
          </span>
        {/if}
        {#if mediaDuration(media)}
          <span class="bg-white/10 text-white/80 text-xs font-bold px-3 h-6 flex items-center rounded-full">
            {mediaDuration(media)}
          </span>
        {/if}
      </div>

      <!-- Description -->
      {#if media.description}
        <p class="text-sm font-light text-muted-foreground line-clamp-4 mb-4">
          {mediaDesc(media)}
        </p>
      {/if}

      <!-- Actions -->
      <div class="flex gap-3 mb-4">
        <button
          class="flex-1 flex items-center justify-center gap-2 bg-white text-black font-black text-sm py-3 rounded-full active:scale-95 transition-transform"
          on:click={watchNow}
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
          Watch Now
        </button>
        <button
          class="w-11 h-11 flex items-center justify-center bg-secondary rounded-full active:scale-95 transition-transform"
          title="Share"
          on:click={() => navigator.share?.({ title: mediaTitle(media!), url: `https://anilist.co/anime/${id}` }).catch(() => {})}
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>
        </button>
        <button
          class="w-11 h-11 flex items-center justify-center bg-secondary rounded-full active:scale-95 transition-transform"
          title="AniList"
          on:click={() => window.open(`https://anilist.co/anime/${id}`, '_blank')}
        >
          <span class="font-black text-xs text-[rgb(61,180,242)]">AL</span>
        </button>
      </div>

      <!-- Genre chips -->
      {#if media.genres?.length}
        <div class="flex flex-wrap gap-2 mb-4">
          {#each media.genres as genre}
            <button
              class="px-3 py-1 rounded-full bg-secondary text-sm font-bold active:opacity-70 transition-opacity"
              on:click={() => navigate({ page: 'search', genre })}
            >
              {genre}
            </button>
          {/each}
        </div>
      {/if}
    </div>

    <!-- Tabs -->
    <div class="px-4 border-b border-border sticky top-0 bg-background z-10">
      <div class="flex gap-6 overflow-x-auto" style="-webkit-overflow-scrolling:touch;">
        {#each [
          { id: 'episodes', label: 'Episodes' },
          { id: 'relations', label: 'Relations' },
          { id: 'chars', label: 'Characters' },
        ] as tab}
          <button
            class={cn(
              'pb-2.5 pt-1 text-sm font-bold shrink-0 border-b-2 transition-colors',
              activeTab === tab.id
                ? 'border-custom text-custom'
                : 'border-transparent text-muted-foreground'
            )}
            on:click={() => activeTab = tab.id as typeof activeTab}
          >
            {tab.label}
          </button>
        {/each}
      </div>
    </div>

    <!-- Tab content -->
    <div class="px-4 pb-8 mt-2">
      {#if activeTab === 'episodes'}
        <EpisodeList {media} {zipData} />

      {:else if activeTab === 'relations'}
        {#if media.relations?.edges?.filter(e => e?.node?.type === 'ANIME').length}
          <div class="flex flex-col gap-3 mt-2">
            {#each (media.relations?.edges ?? []).filter(e => e?.node?.type === 'ANIME') as edge}
              {#if edge?.node}
                {@const rel = edge.node}
                <button
                  class="flex items-center gap-3 p-2 rounded-xl bg-neutral-950 active:bg-neutral-800 text-left transition-colors w-full"
                  on:click={() => navigate({ page: 'anime', id: rel.id })}
                >
                  <div class="w-12 h-16 rounded-lg overflow-hidden shrink-0">
                    <LoadImg src={rel.coverImage?.extraLarge} alt={rel.title?.userPreferred ?? ''} class="w-full h-full" />
                  </div>
                  <div class="flex flex-col min-w-0">
                    <span class="text-xs text-muted-foreground font-bold uppercase tracking-wide">
                      {(edge.relationType ?? 'Related').replace(/_/g, ' ')}
                    </span>
                    <span class="font-bold text-sm line-clamp-1 mt-0.5">{rel.title?.userPreferred ?? 'Unknown'}</span>
                    <span class="text-xs text-muted-foreground">
                      {rel.format?.replace(/_/g,' ') ?? ''} {rel.episodes ? `· ${rel.episodes} eps` : ''}
                    </span>
                  </div>
                  <svg class="ml-auto shrink-0 text-muted-foreground" xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>
                </button>
              {/if}
            {/each}
          </div>
        {:else}
          <div class="py-12 text-center text-muted-foreground text-sm">No relations found</div>
        {/if}

      {:else if activeTab === 'chars'}
        <CharacterGrid mediaId={id} />
      {/if}
    </div>
  {/if}
</div>
