<!--
  Search.svelte — mirrors Hayase's src/routes/app/search/+page.svelte.
  Text search with filter chips, 2-column grid, infinite scroll.
-->
<script lang="ts">
  import { onMount, onDestroy, tick } from 'svelte';
  import { navigate } from '../lib/store';
  import { searchMedia, type AniListMedia, type SearchVariables } from '../lib/anilist';
  import { debounce, cn } from '../lib/util';
  import AnimeCard from '../components/AnimeCard.svelte';

  export let initialQuery: string = '';

  // Filter state
  let searchText = initialQuery;
  let selectedGenre = '';
  let selectedFormat = '';
  let selectedStatus = '';
  let selectedSort = 'TRENDING_DESC';
  let showFilters = false;

  // Results
  let allMedia: AniListMedia[] = [];
  let loading = false;
  let hasNextPage = true;
  let pageNum = 1;
  let error = '';

  const genres = ['Action','Adventure','Comedy','Drama','Fantasy','Horror','Mystery',
    'Psychological','Romance','Sci-Fi','Slice of Life','Sports','Supernatural','Thriller'];
  const formats = [['TV','TV'], ['MOVIE','Movie'], ['OVA','OVA'], ['ONA','ONA']];
  const statuses = [['RELEASING','Airing'], ['FINISHED','Finished'], ['NOT_YET_RELEASED','Upcoming']];
  const sorts = [
    ['TRENDING_DESC','Trending'], ['POPULARITY_DESC','Popularity'],
    ['SCORE_DESC','Score'], ['START_DATE_DESC','Latest'], ['TITLE_ROMAJI_DESC','Name'],
  ];

  async function doSearch(reset = true) {
    if (loading) return;
    if (reset) { allMedia = []; pageNum = 1; hasNextPage = true; }
    loading = true; error = '';
    try {
      const vars: SearchVariables = {
        page: pageNum, perPage: 20,
        search: searchText.trim() || undefined,
        genre: selectedGenre ? [selectedGenre] : undefined,
        format: selectedFormat ? [selectedFormat] : undefined,
        status: selectedStatus ? [selectedStatus] : undefined,
        sort: [selectedSort],
      };
      const res = await searchMedia(vars);
      allMedia = reset ? res.media : [...allMedia, ...res.media];
      hasNextPage = res.hasNextPage;
      pageNum++;
    } catch (e: any) {
      error = e?.message ?? 'Search failed';
    }
    loading = false;
  }

  const debouncedSearch = debounce(() => doSearch(true), 300);

  $: searchText, selectedGenre, selectedFormat, selectedStatus, selectedSort, debouncedSearch();

  onMount(() => doSearch(true));

  // Infinite scroll
  let scrollEl: HTMLElement;
  function onScroll(e: Event) {
    const el = e.currentTarget as HTMLElement;
    const remaining = el.scrollHeight - el.scrollTop - el.clientHeight;
    if (remaining < 600 && hasNextPage && !loading) doSearch(false);
  }

  function clearFilter(which: 'genre' | 'format' | 'status') {
    if (which === 'genre') selectedGenre = '';
    else if (which === 'format') selectedFormat = '';
    else selectedStatus = '';
  }
</script>

<div class="flex flex-col h-full">
  <!-- Search bar -->
  <div class="px-4 pt-4 pb-2 flex flex-col gap-2">
    <div class="flex items-center gap-2 bg-neutral-900 rounded-xl px-3 py-2">
      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" class="text-muted-foreground shrink-0"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>
      <input
        type="search"
        placeholder="Search anime…"
        bind:value={searchText}
        class="flex-1 bg-transparent text-sm text-foreground placeholder:text-muted-foreground outline-none"
        autocomplete="off"
        autocorrect="off"
        spellcheck="false"
      />
      {#if searchText}
        <button class="text-muted-foreground" on:click={() => { searchText = ''; }}>
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M18 6 6 18M6 6l12 12"/></svg>
        </button>
      {/if}
      <button
        class={cn('ml-1 text-xs font-bold px-2 py-1 rounded-md transition-colors', showFilters ? 'bg-white/20 text-white' : 'text-muted-foreground')}
        on:click={() => showFilters = !showFilters}
      >
        Filters
      </button>
    </div>

    <!-- Expandable filters -->
    {#if showFilters}
      <div class="flex flex-col gap-2 pb-1">
        <!-- Genre -->
        <div class="flex gap-1.5 overflow-x-auto pb-1" style="-webkit-overflow-scrolling:touch;">
          {#each genres as g}
            <button
              class={cn(
                'px-3 py-1 rounded-full text-xs font-bold shrink-0 transition-colors',
                selectedGenre === g ? 'bg-white text-black' : 'bg-neutral-800 text-muted-foreground'
              )}
              on:click={() => selectedGenre = selectedGenre === g ? '' : g}
            >{g}</button>
          {/each}
        </div>
        <!-- Format + Status + Sort row -->
        <div class="flex gap-2 overflow-x-auto pb-1" style="-webkit-overflow-scrolling:touch;">
          {#each formats as [val, label]}
            <button
              class={cn('px-3 py-1 rounded-full text-xs font-bold shrink-0 transition-colors',
                selectedFormat === val ? 'bg-white text-black' : 'bg-neutral-800 text-muted-foreground'
              )}
              on:click={() => selectedFormat = selectedFormat === val ? '' : val}
            >{label}</button>
          {/each}
          {#each statuses as [val, label]}
            <button
              class={cn('px-3 py-1 rounded-full text-xs font-bold shrink-0 transition-colors',
                selectedStatus === val ? 'bg-white text-black' : 'bg-neutral-800 text-muted-foreground'
              )}
              on:click={() => selectedStatus = selectedStatus === val ? '' : val}
            >{label}</button>
          {/each}
        </div>
        <!-- Sort row -->
        <div class="flex gap-1.5 overflow-x-auto pb-1" style="-webkit-overflow-scrolling:touch;">
          <span class="text-xs text-muted-foreground self-center shrink-0">Sort:</span>
          {#each sorts as [val, label]}
            <button
              class={cn('px-3 py-1 rounded-full text-xs font-bold shrink-0 transition-colors',
                selectedSort === val ? 'bg-white text-black' : 'bg-neutral-800 text-muted-foreground'
              )}
              on:click={() => selectedSort = val}
            >{label}</button>
          {/each}
        </div>
      </div>
    {/if}

    <!-- Active filter chips -->
    {#if selectedGenre || selectedFormat || selectedStatus}
      <div class="flex gap-1.5 flex-wrap">
        {#if selectedGenre}
          <button
            class="flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-white/10 text-xs font-bold"
            on:click={() => clearFilter('genre')}
          >
            {selectedGenre}
            <span class="opacity-70">✕</span>
          </button>
        {/if}
        {#if selectedFormat}
          <button
            class="flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-white/10 text-xs font-bold"
            on:click={() => clearFilter('format')}
          >
            {formats.find(f => f[0] === selectedFormat)?.[1] ?? selectedFormat}
            <span class="opacity-70">✕</span>
          </button>
        {/if}
        {#if selectedStatus}
          <button
            class="flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-white/10 text-xs font-bold"
            on:click={() => clearFilter('status')}
          >
            {statuses.find(s => s[0] === selectedStatus)?.[1] ?? selectedStatus}
            <span class="opacity-70">✕</span>
          </button>
        {/if}
      </div>
    {/if}
  </div>

  <!-- Results grid -->
  <div
    class="flex-1 overflow-y-auto"
    style="-webkit-overflow-scrolling: touch; will-change: scroll-position;"
    bind:this={scrollEl}
    on:scroll={onScroll}
  >
    {#if error}
      <div class="px-4 py-10 text-center text-sm text-destructive">{error}</div>
    {:else}
      <div class="grid grid-cols-2 px-1">
        {#each allMedia as media, i (media.id)}
          <AnimeCard {media} index={i} />
        {/each}
        <!-- Skeleton placeholders while loading more -->
        {#if loading}
          {#each Array(6) as _, i}
            <div class="p-3">
              <div class="w-full h-52 rounded-md bg-neutral-900 shimmer" />
              <div class="h-3 w-3/4 rounded mt-2 bg-neutral-800 shimmer" />
            </div>
          {/each}
        {/if}
      </div>

      {#if !loading && allMedia.length === 0}
        <div class="flex flex-col items-center justify-center py-20 gap-3 text-muted-foreground">
          <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>
          <span class="text-sm">No results found</span>
          <span class="text-xs">Try a different search term or filters</span>
        </div>
      {/if}
    {/if}
    <div class="h-4" />
  </div>
</div>
