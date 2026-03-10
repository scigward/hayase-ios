<!--
  FeaturedBanner.svelte — mirrors Hayase's full-banner.svelte + banner.svelte + banner-image.svelte.
  Fetches top 5 current-season popular anime, auto-rotates every 15s,
  shows progress dots, title, badges and a Watch button.
-->
<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { searchMedia, type AniListMedia } from '../lib/anilist';
  import { navigate, openSearch } from '../lib/store';
  import { currentSeason, currentYear, banner, cover, mediaTitle, mediaStatus, mediaFormat, getBGColorForRating, cn } from '../lib/util';
  import LoadImg from './LoadImg.svelte';

  let mediaList: AniListMedia[] = [];
  let current = 0;
  let loading = true;
  let error = '';
  let interval: ReturnType<typeof setInterval>;
  let progressKey = 0; // re-trigger CSS animation on each rotation

  onMount(async () => {
    try {
      const res = await searchMedia({
        sort: ['SCORE_DESC'],
        perPage: 10,
        season: currentSeason,
        seasonYear: currentYear,
        statusNot: ['NOT_YET_RELEASED'],
      });
      // Keep only those with a banner image or trailer
      mediaList = (res.media ?? [])
        .filter(m => m.bannerImage || m.trailer?.id)
        .slice(0, 5);
    } catch (e: any) {
      error = e?.message ?? 'Failed to load';
    }
    loading = false;

    interval = setInterval(() => {
      current = (current + 1) % Math.max(mediaList.length, 1);
      progressKey++;
    }, 15_000);
  });

  onDestroy(() => clearInterval(interval));

  $: active = mediaList[current];
  $: bgSrc = active ? (banner(active) ?? cover(active)) : undefined;
  $: color = active?.coverImage?.color ?? '#1a1a2e';

  function goToAnime() {
    if (active) navigate({ page: 'anime', id: active.id });
  }

  function watchNow(e: MouseEvent) {
    e.stopPropagation();
    if (!active) return;
    openSearch({
      animeTitle: mediaTitle(active),
      anilistID: active.id,
      episode: (active.mediaListEntry?.progress ?? 0) + 1,
    });
  }

  function dot(i: number) {
    current = i;
    progressKey++;
    clearInterval(interval);
    interval = setInterval(() => {
      current = (current + 1) % Math.max(mediaList.length, 1);
      progressKey++;
    }, 15_000);
  }
</script>

<!-- Full-width banner, height 70vh (matches Hayase) -->
<div class="w-full relative flex flex-col" style="height: 70vh; min-height: 340px;">

  <!-- Background image -->
  {#if bgSrc}
    <div class="absolute inset-0 banner-gr">
      <LoadImg
        src={bgSrc}
        alt=""
        {color}
        class="w-full h-full object-cover"
      />
    </div>
  {:else if loading}
    <div class="absolute inset-0 bg-neutral-900 shimmer" />
  {/if}

  <!-- Content — positioned at bottom -->
  <div class="absolute inset-x-0 bottom-0 p-5 z-10">
    {#if loading}
      <div class="h-8 w-48 rounded shimmer mb-3" />
      <div class="h-4 w-32 rounded shimmer mb-4" />
    {:else if active}
      <!-- Title -->
      <h1 class="font-black text-3xl text-white text-shadow-lg line-clamp-2 mb-2">
        {mediaTitle(active)}
      </h1>

      <!-- Metadata badges -->
      <div class="flex flex-wrap gap-2 mb-3">
        {#if active.episodes}
          <span class="bg-white/10 text-white text-xs font-bold px-3 py-1 rounded-full">
            {active.episodes} eps
          </span>
        {/if}
        {#if active.format}
          <span class="bg-white/10 text-white text-xs font-bold px-3 py-1 rounded-full">
            {mediaFormat(active)}
          </span>
        {/if}
        {#if active.status}
          <span class="bg-white/10 text-white text-xs font-bold px-3 py-1 rounded-full">
            {mediaStatus(active)}
          </span>
        {/if}
        {#if active.averageScore}
          <span class="bg-white/10 text-white text-xs font-bold px-3 py-1 rounded-full">
            {active.averageScore}%
          </span>
        {/if}
      </div>

      <!-- Description (2-line clamp) -->
      {#if active.description}
        <p class="text-white/70 text-xs line-clamp-2 mb-4 font-light" style="max-width: 340px;">
          {active.description.replace(/<[^>]+>/g, '')}
        </p>
      {/if}

      <!-- CTA row -->
      <div class="flex items-center gap-3">
        <button
          class="flex items-center gap-2 bg-white text-black font-black text-sm px-6 py-2.5 rounded-full active:scale-95 transition-transform"
          on:click={watchNow}
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
          Watch Now
        </button>
        <button
          class="flex items-center gap-2 bg-white/10 text-white font-bold text-sm px-5 py-2.5 rounded-full active:scale-95 transition-transform"
          on:click={goToAnime}
        >
          More Info
        </button>
      </div>
    {/if}

    <!-- Progress dots -->
    {#if mediaList.length > 1}
      <div class="flex gap-2 mt-4">
        {#each mediaList as _, i}
          <button
            class={cn(
              'h-1 rounded-full transition-all duration-300 overflow-hidden bg-white/20',
              i === current ? 'w-12' : 'w-6'
            )}
            on:click={() => dot(i)}
          >
            {#if i === current}
              <div
                class="h-full bg-white rounded-full"
                style="animation: progress-fill 15s linear {progressKey}; animation-fill-mode: forwards;"
              />
            {/if}
          </button>
        {/each}
      </div>
    {/if}
  </div>
</div>
