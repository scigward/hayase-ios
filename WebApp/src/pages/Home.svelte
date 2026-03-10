<!--
  Home.svelte — mirrors Hayase's src/routes/app/home/+page.svelte.
  Hero banner + Continue Watching (if any) + 7 horizontal-scroll sections.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { navigate, hideBanner, continueWatching, removeContinueEntry } from '../lib/store';
  import { searchMedia, HOME_SECTIONS, type SearchVariables, type AniListMedia } from '../lib/anilist';
  import FeaturedBanner from '../components/FeaturedBanner.svelte';
  import AnimeCard from '../components/AnimeCard.svelte';

  interface Section {
    title: string;
    vars: SearchVariables;
    media: AniListMedia[];
    loading: boolean;
    error: string;
  }

  let sections: Section[] = HOME_SECTIONS.map(s => ({
    title: s.title,
    vars: { ...s.vars } as SearchVariables,
    media: [],
    loading: true,
    error: '',
  }));

  onMount(async () => {
    const loadSection = async (s: Section) => {
      try {
        const res = await searchMedia(s.vars);
        s.media = res.media;
      } catch (e: any) {
        s.error = e?.message ?? 'Failed to load';
      }
      s.loading = false;
      sections = sections;
    };
    await Promise.all(sections.slice(0, 3).map(loadSection));
    await Promise.all(sections.slice(3).map(loadSection));
  });

  function handleScroll(e: Event) {
    const el = e.currentTarget as HTMLElement;
    hideBanner.set(el.scrollTop > 100);
  }

  function goSearch(vars: SearchVariables) {
    navigate({ page: 'search' });
  }

  $: cwList = $continueWatching;
</script>

<div
  class="flex-1 overflow-y-auto overflow-x-hidden"
  style="-webkit-overflow-scrolling: touch; will-change: scroll-position;"
  on:scroll={handleScroll}
>
  <!-- Hero banner -->
  <FeaturedBanner />

  <!-- Continue Watching (mirrors Hayase's continue-watching.svelte) -->
  {#if cwList.length > 0}
    <section class="mt-1">
      <div class="flex items-end justify-between px-4 pt-5 pb-1">
        <span class="text-lg font-semibold text-muted-foreground">Continue Watching</span>
      </div>
      <div
        class="flex overflow-x-auto gap-3 px-4 pb-2"
        style="-webkit-overflow-scrolling: touch;"
      >
        {#each cwList as entry (entry.mediaId)}
          <div class="flex flex-col shrink-0 w-32 relative">
            <button
              class="relative w-32 h-20 rounded-lg overflow-hidden"
              on:click={() => navigate({ page: 'anime', id: entry.mediaId })}
            >
              <img src={entry.cover} alt={entry.title} class="w-full h-full object-cover" loading="lazy" />
              <!-- Progress bar at bottom -->
              {@const frac = entry.duration > 0 ? entry.currentTime / entry.duration : 0}
              <div class="absolute bottom-0 left-0 right-0 h-[3px] bg-white/20">
                <div class="h-full bg-[rgb(61,180,242)]" style="width:{(frac * 100).toFixed(1)}%" />
              </div>
              <!-- Play overlay -->
              <div class="absolute inset-0 flex items-center justify-center bg-black/20">
                <div class="w-8 h-8 rounded-full bg-black/60 flex items-center justify-center">
                  <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="white"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                </div>
              </div>
            </button>
            <span class="text-[10px] font-bold mt-1 line-clamp-1 text-foreground">{entry.title}</span>
            <span class="text-[9px] text-muted-foreground">Ep {entry.episode}</span>
            <!-- Remove button -->
            <button
              class="absolute -top-1 -right-1 w-5 h-5 rounded-full bg-neutral-700 flex items-center justify-center z-10 active:scale-90"
              on:click|stopPropagation={() => removeContinueEntry(entry.mediaId)}
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
            </button>
          </div>
        {/each}
      </div>
    </section>
  {/if}

  <!-- Regular sections -->
  {#each sections as section (section.title)}
    <section class="mt-1">
      <div class="flex items-end justify-between px-4 pt-5 pb-1">
        <button
          class="text-lg font-semibold text-muted-foreground hover:text-foreground transition-colors text-left"
          on:click={() => goSearch(section.vars)}
        >
          {section.title}
        </button>
        <button
          class="text-xs font-semibold text-muted-foreground hover:text-foreground transition-colors"
          on:click={() => goSearch(section.vars)}
        >
          View More
        </button>
      </div>

      {#if section.loading}
        <div class="flex overflow-x-auto gap-0">
          {#each Array(6) as _, i}
            <div class="p-3 shrink-0">
              <div class="w-36 h-52 rounded-md bg-neutral-900 shimmer" />
              <div class="h-3 w-28 rounded mt-2 bg-neutral-800 shimmer" />
              <div class="h-2 w-20 rounded mt-1.5 bg-neutral-900 shimmer" />
            </div>
          {/each}
        </div>
      {:else if section.error}
        <div class="px-4 py-3 text-xs text-destructive">{section.error}</div>
      {:else}
        <div
          class="flex overflow-x-auto"
          style="-webkit-overflow-scrolling: touch; will-change: scroll-position;"
        >
          {#each section.media as media, i (media.id)}
            <AnimeCard {media} index={i} />
          {/each}
        </div>
      {/if}
    </section>
  {/each}

  <!-- Bottom padding for tab bar -->
  <div class="h-4" />
</div>
