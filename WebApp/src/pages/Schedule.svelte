<!--
  Schedule.svelte — monthly airing calendar.
  Mirrors Hayase's src/routes/app/schedule/+page.svelte exactly.
  Grid: Mon–Sun columns, today highlighted rgb(61,180,242), up to 3 entries per day.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { navigate } from '../lib/store';
  import Spinner from '../components/Spinner.svelte';
  import LoadImg from '../components/LoadImg.svelte';

  // AniList airingSchedules query
  interface AiringEntry {
    id: number;
    episode: number;
    airingAt: number;
    media: {
      id: number;
      title: { userPreferred: string };
      coverImage: { medium: string; color?: string };
    };
  }

  const AIRING_QUERY = `
    query($start: Int, $end: Int, $page: Int) {
      Page(page: $page, perPage: 50) {
        pageInfo { hasNextPage }
        airingSchedules(airingAt_greater: $start, airingAt_lesser: $end, sort: TIME) {
          id episode airingAt
          media {
            id
            title { userPreferred }
            coverImage { medium color }
          }
        }
      }
    }
  `;

  async function fetchAiring(start: number, end: number): Promise<AiringEntry[]> {
    const all: AiringEntry[] = [];
    let page = 1;
    let hasNext = true;
    while (hasNext) {
      const res = await fetch('https://graphql.anilist.co', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query: AIRING_QUERY, variables: { start, end, page } }),
      });
      const json = await res.json();
      const pageData = json.data?.Page;
      all.push(...(pageData?.airingSchedules ?? []));
      hasNext = pageData?.pageInfo?.hasNextPage && page < 5;
      page++;
    }
    return all;
  }

  // Calendar state
  let today = new Date();
  let viewYear = today.getFullYear();
  let viewMonth = today.getMonth(); // 0-based

  let loading = false;
  let entries: AiringEntry[] = [];
  // Map from "YYYY-MM-DD" → AiringEntry[]
  let dayMap: Record<string, AiringEntry[]> = {};

  // Expanded day for "show more"
  let expandedDay: string | null = null;

  async function loadMonth() {
    loading = true;
    dayMap = {};
    entries = [];
    try {
      const first = new Date(viewYear, viewMonth, 1);
      const last  = new Date(viewYear, viewMonth + 1, 0, 23, 59, 59);
      const start = Math.floor(first.getTime() / 1000);
      const end   = Math.floor(last.getTime()  / 1000);
      entries = await fetchAiring(start, end);
      const map: Record<string, AiringEntry[]> = {};
      for (const e of entries) {
        const d = new Date(e.airingAt * 1000);
        const key = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
        if (!map[key]) map[key] = [];
        map[key].push(e);
      }
      dayMap = map;
    } catch {}
    loading = false;
  }

  onMount(loadMonth);

  function prevMonth() {
    if (viewMonth === 0) { viewYear--; viewMonth = 11; }
    else viewMonth--;
    expandedDay = null;
    loadMonth();
  }

  function nextMonth() {
    if (viewMonth === 11) { viewYear++; viewMonth = 0; }
    else viewMonth++;
    expandedDay = null;
    loadMonth();
  }

  const MONTH_NAMES = ['January','February','March','April','May','June','July','August','September','October','November','December'];
  const DAY_LABELS  = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  // Build calendar grid — ISO week: Mon=0 … Sun=6
  $: calDays = buildCalendar(viewYear, viewMonth);

  function buildCalendar(y: number, m: number): (number | null)[] {
    const first = new Date(y, m, 1);
    // getDay(): 0=Sun, 1=Mon … convert to Mon-first: (0→6), (1→0), …
    let startDow = (first.getDay() + 6) % 7;
    const daysInMonth = new Date(y, m + 1, 0).getDate();
    const cells: (number | null)[] = [];
    for (let i = 0; i < startDow; i++) cells.push(null);
    for (let d = 1; d <= daysInMonth; d++) cells.push(d);
    // pad to full weeks
    while (cells.length % 7 !== 0) cells.push(null);
    return cells;
  }

  function dayKey(d: number): string {
    return `${viewYear}-${String(viewMonth+1).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
  }

  function isToday(d: number): boolean {
    return d === today.getDate() && viewMonth === today.getMonth() && viewYear === today.getFullYear();
  }
</script>

<div class="flex flex-col h-full overflow-y-auto" style="-webkit-overflow-scrolling:touch;">

  <!-- Header -->
  <div class="flex items-center justify-between px-4 pt-safe-top pb-3 bg-background sticky top-0 z-10">
    <div>
      <h1 class="text-xl font-black">Airing Calendar</h1>
      <p class="text-xs text-muted-foreground">{MONTH_NAMES[viewMonth]} {viewYear}</p>
    </div>
    <div class="flex gap-2">
      <button
        class="w-9 h-9 rounded-full bg-neutral-800 flex items-center justify-center active:scale-90 transition-transform"
        on:click={prevMonth}
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>
      </button>
      <button
        class="w-9 h-9 rounded-full bg-neutral-800 flex items-center justify-center active:scale-90 transition-transform"
        on:click={nextMonth}
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>
      </button>
    </div>
  </div>

  {#if loading}
    <div class="flex-1 flex items-center justify-center">
      <Spinner size={32} />
    </div>
  {:else}

    <!-- Day-of-week header -->
    <div class="grid grid-cols-7 px-2 border-b border-border">
      {#each DAY_LABELS as day}
        <div class="py-1.5 text-center text-[10px] font-bold text-muted-foreground">{day}</div>
      {/each}
    </div>

    <!-- Calendar grid -->
    <div class="grid grid-cols-7 flex-1">
      {#each calDays as cell}
        {#if cell === null}
          <div class="min-h-[5.5rem] border-b border-r border-border/30 bg-neutral-950/50" />
        {:else}
          {@const key = dayKey(cell)}
          {@const entries = dayMap[key] ?? []}
          {@const shown = entries.slice(0, 3)}
          {@const more  = entries.length - shown.length}
          <div
            class="min-h-[5.5rem] border-b border-r border-border/30 p-1 flex flex-col gap-0.5 cursor-pointer active:bg-white/5"
            on:click={() => expandedDay = expandedDay === key ? null : key}
            role="button"
            tabindex="0"
            on:keydown={e => e.key === 'Enter' && (expandedDay = expandedDay === key ? null : key)}
          >
            <!-- Day number -->
            <div class="flex items-center justify-center mb-0.5">
              <span
                class="w-6 h-6 flex items-center justify-center text-xs font-bold rounded-full
                  {isToday(cell) ? 'bg-[rgb(61,180,242)] text-black' : 'text-foreground'}"
              >{cell}</span>
            </div>

            <!-- Up to 3 entries -->
            {#each shown as e}
              <button
                class="w-full text-left rounded overflow-hidden flex items-center gap-0.5 bg-neutral-800/60 px-1 py-0.5 active:opacity-70"
                on:click|stopPropagation={() => navigate({ page: 'anime', id: e.media.id })}
              >
                <img
                  src={e.media.coverImage.medium}
                  alt=""
                  class="w-4 h-4 rounded object-cover shrink-0"
                  loading="lazy"
                />
                <span class="text-[9px] font-bold line-clamp-1 text-foreground leading-none">{e.media.title.userPreferred}</span>
              </button>
            {/each}

            {#if more > 0}
              <span class="text-[9px] text-muted-foreground text-center">+{more} more</span>
            {/if}
          </div>
        {/if}
      {/each}
    </div>

    <!-- Expanded day sheet -->
    {#if expandedDay && (dayMap[expandedDay]?.length ?? 0) > 0}
      <div class="fixed inset-0 z-50 flex flex-col-reverse">
        <button class="absolute inset-0 bg-black/60" on:click={() => expandedDay = null} />
        <div class="relative bg-neutral-950 rounded-t-2xl max-h-[70vh] flex flex-col z-10"
             style="padding-bottom: env(safe-area-inset-bottom);">
          <div class="flex justify-center pt-3 pb-1">
            <div class="w-10 h-1 rounded-full bg-neutral-700" />
          </div>
          <div class="px-4 py-2 border-b border-border">
            <h3 class="font-black text-base">{expandedDay?.split('-').slice(1).join('/')} — {dayMap[expandedDay].length} episode{dayMap[expandedDay].length !== 1 ? 's' : ''} airing</h3>
          </div>
          <div class="flex-1 overflow-y-auto">
            {#each dayMap[expandedDay] as e}
              <button
                class="flex items-center gap-3 px-4 py-3 w-full text-left border-b border-border/40 active:bg-white/5"
                on:click={() => { expandedDay = null; navigate({ page: 'anime', id: e.media.id }); }}
              >
                <img
                  src={e.media.coverImage.medium}
                  alt=""
                  class="w-10 h-14 rounded object-cover shrink-0"
                  loading="lazy"
                />
                <div class="flex flex-col gap-0.5">
                  <span class="text-sm font-bold line-clamp-2">{e.media.title.userPreferred}</span>
                  <span class="text-xs text-muted-foreground">Episode {e.episode}</span>
                  <span class="text-xs text-muted-foreground">{new Date(e.airingAt * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
                </div>
              </button>
            {/each}
          </div>
        </div>
      </div>
    {/if}

  {/if}
</div>
