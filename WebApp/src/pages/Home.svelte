<!--
  Home.svelte — mirrors Hayase's src/routes/app/home/+page.svelte.
  Hero banner + 7 horizontal-scroll sections.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { navigate, hideBanner } from '../lib/store';
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
    // Load sections in parallel (first 3 priority, rest deferred)
    const loadSection = async (s: Section) => {
      try {
        const res = await searchMedia(s.vars);
        s.media = res.media;
      } catch (e: any) {
        s.error = e?.message ?? 'Failed to load';
      }
      s.loading = false;
      sections = sections; // trigger reactivity
    };

    // Load first 3 immediately
    await Promise.all(sections.slice(0, 3).map(loadSection));
    // Load rest after a tick
    await Promise.all(sections.slice(3).map(loadSection));
  });

  function handleScroll(e: Event) {
    const el = e.currentTarget as HTMLElement;
    hideBanner.set(el.scrollTop > 100);
  }

  function goSearch(vars: SearchVariables) {
    navigate({ page: 'search' });
  }
</script>

<div
  class="flex-1 overflow-y-auto overflow-x-hidden"
  style="-webkit-overflow-scrolling: touch; will-change: scroll-position;"
  on:scroll={handleScroll}
>
  <!-- Hero banner -->
  <FeaturedBanner />

  <!-- Sections -->
  {#each sections as section (section.title)}
    <section class="mt-1">
      <!-- Header -->
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

      <!-- Horizontal scroll -->
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
