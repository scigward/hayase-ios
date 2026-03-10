<script lang="ts">
  import { settings } from '../lib/store';
  import SettingCard from '../components/SettingCard.svelte';

  const qualities = ['480','720','1080','1440','2160'];
  const prefs = [['quality','Quality'],['size','Size'],['seeders','Seeders']];
</script>

<div class="flex flex-col h-full overflow-y-auto p-4 gap-4" style="-webkit-overflow-scrolling:touch;">
  <div class="pt-2">
    <h1 class="text-2xl font-black">Settings</h1>
    <p class="text-sm text-muted-foreground mt-0.5">Customize your experience</p>
  </div>

  <h2 class="text-xs font-bold text-muted-foreground uppercase tracking-widest -mb-2">Playback</h2>

  <SettingCard title="Auto-Play Next Episode" description="Automatically play the next episode when one finishes.">
    <label class="relative inline-flex items-center cursor-pointer">
      <input type="checkbox" class="sr-only peer" bind:checked={$settings.playerAutoplay} />
      <div class="w-11 h-6 bg-muted rounded-full peer peer-checked:bg-[rgb(61,180,242)] transition-colors" />
      <div class="absolute left-0.5 top-0.5 bg-white w-5 h-5 rounded-full transition-transform peer-checked:translate-x-5" />
    </label>
  </SettingCard>

  <SettingCard title="Auto-Complete Episodes" description="Mark episode as watched at 85% progress.">
    <label class="relative inline-flex items-center cursor-pointer">
      <input type="checkbox" class="sr-only peer" bind:checked={$settings.playerAutocomplete} />
      <div class="w-11 h-6 bg-muted rounded-full peer peer-checked:bg-[rgb(61,180,242)] transition-colors" />
      <div class="absolute left-0.5 top-0.5 bg-white w-5 h-5 rounded-full transition-transform peer-checked:translate-x-5" />
    </label>
  </SettingCard>

  <h2 class="text-xs font-bold text-muted-foreground uppercase tracking-widest mt-2 -mb-2">Search</h2>

  <SettingCard title="Default Quality" description="Preferred torrent resolution.">
    <select
      class="bg-neutral-800 text-foreground text-sm font-bold rounded-lg px-3 py-1.5 border border-border outline-none"
      bind:value={$settings.searchQuality}
    >
      {#each qualities as q}
        <option value={q}>{q}p</option>
      {/each}
    </select>
  </SettingCard>

  <SettingCard title="Auto-Select Torrent" description="Automatically pick the best result.">
    <label class="relative inline-flex items-center cursor-pointer">
      <input type="checkbox" class="sr-only peer" bind:checked={$settings.searchAutoSelect} />
      <div class="w-11 h-6 bg-muted rounded-full peer peer-checked:bg-[rgb(61,180,242)] transition-colors" />
      <div class="absolute left-0.5 top-0.5 bg-white w-5 h-5 rounded-full transition-transform peer-checked:translate-x-5" />
    </label>
  </SettingCard>

  <SettingCard title="Lookup Preference" description="How to rank search results.">
    <select
      class="bg-neutral-800 text-foreground text-sm font-bold rounded-lg px-3 py-1.5 border border-border outline-none"
      bind:value={$settings.lookupPreference}
    >
      {#each prefs as [val, label]}
        <option value={val}>{label}</option>
      {/each}
    </select>
  </SettingCard>

  <h2 class="text-xs font-bold text-muted-foreground uppercase tracking-widest mt-2 -mb-2">Content</h2>

  <SettingCard title="Hide Spoilers" description="Blur episode thumbnails and summaries until watched.">
    <label class="relative inline-flex items-center cursor-pointer">
      <input type="checkbox" class="sr-only peer" bind:checked={$settings.hideSpoilers} />
      <div class="w-11 h-6 bg-muted rounded-full peer peer-checked:bg-[rgb(61,180,242)] transition-colors" />
      <div class="absolute left-0.5 top-0.5 bg-white w-5 h-5 rounded-full transition-transform peer-checked:translate-x-5" />
    </label>
  </SettingCard>

  <div class="h-4" />
</div>
