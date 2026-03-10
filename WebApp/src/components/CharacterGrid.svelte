<script lang="ts">
  import { onMount } from 'svelte';
  import { getCharacters, type Character } from '../lib/anilist';
  import LoadImg from './LoadImg.svelte';

  export let mediaId: number;

  let chars: Character[] = [];
  let loading = true;

  onMount(async () => {
    try { chars = await getCharacters(mediaId); } catch {}
    loading = false;
  });
</script>

{#if loading}
  <div class="grid grid-cols-3 gap-3 mt-2">
    {#each Array(9) as _}
      <div class="flex flex-col items-center gap-1">
        <div class="w-16 h-16 rounded-full bg-neutral-800 shimmer" />
        <div class="h-3 w-14 bg-neutral-800 rounded shimmer" />
      </div>
    {/each}
  </div>
{:else if chars.length === 0}
  <div class="py-12 text-center text-muted-foreground text-sm">No character data</div>
{:else}
  <div class="grid grid-cols-3 gap-3 mt-2">
    {#each chars as char (char.id)}
      <div class="flex flex-col items-center gap-1 text-center">
        <div class="w-16 h-16 rounded-full overflow-hidden">
          <LoadImg src={char.image?.large} alt={char.name.full ?? ''} class="w-full h-full" />
        </div>
        <span class="text-xs font-bold line-clamp-2 leading-tight">{char.name.full ?? ''}</span>
      </div>
    {/each}
  </div>
{/if}
