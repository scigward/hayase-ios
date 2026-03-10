<!--
  AnimeCard.svelte — mirrors Hayase's src/lib/components/ui/cards/small.svelte
  Card dimensions: w-[9.5rem] h-[13.5rem] for cover, p-4 outer.
  Animates in with card-load-in (translate3d + scale).
-->
<script lang="ts">
  import { navigate } from '../lib/store';
  import { cn, cover, mediaTitle, mediaFormat, getBGColorForRating } from '../lib/util';
  import type { AniListMedia } from '../lib/anilist';
  import LoadImg from './LoadImg.svelte';

  export let media: AniListMedia;
  export let index: number = 0;

  $: img = cover(media);
  $: title = mediaTitle(media);
  $: fmt = mediaFormat(media);
  $: score = media.averageScore;

  function tap() {
    navigate({ page: 'anime', id: media.id });
  }
</script>

<button
  class="p-3 cursor-pointer shrink-0 pointer-events-auto text-left card-load-in"
  style:animation-delay="{index * 40}ms"
  on:click={tap}
>
  <div class="flex flex-col w-36">
    <!-- Cover image -->
    <div class="relative w-36 h-52 rounded-md overflow-hidden">
      <LoadImg
        src={img}
        alt={title}
        color={media.coverImage?.color}
        class="w-full h-full"
      />
      <!-- Score badge -->
      {#if score}
        <div class={cn(
          'absolute top-1.5 right-1.5 px-1.5 py-0.5 rounded text-xs font-black text-white',
          getBGColorForRating(score)
        )}>
          {score}%
        </div>
      {/if}
      <!-- Status dot -->
      {#if media.mediaListEntry}
        {@const s = media.mediaListEntry.status}
        <div class={cn(
          'absolute top-1.5 left-1.5 w-2 h-2 rounded-full',
          s === 'CURRENT'   ? 'bg-[rgb(61,180,242)]' :
          s === 'PLANNING'  ? 'bg-[rgb(247,154,99)]' :
          s === 'COMPLETED' ? 'bg-[rgb(123,213,85)]' :
          s === 'PAUSED'    ? 'bg-[rgb(250,122,122)]' :
          'bg-[rgb(180,180,180)]'
        )} />
      {/if}
    </div>

    <!-- Title + meta -->
    <div class="mt-2 flex flex-col">
      <span class="font-black text-[0.8rem] line-clamp-2 text-foreground leading-tight">
        {title}
      </span>
      <div class="flex items-center justify-between mt-1 text-muted-foreground text-xs font-medium">
        <span>{media.startDate?.year ?? '—'}</span>
        <span>{fmt}</span>
      </div>
    </div>
  </div>
</button>
