<script lang="ts">
  import { settings } from '../lib/store';
  import SettingCard from '../components/SettingCard.svelte';
  import Extensions from './extensions/Extensions.svelte';

  const qualities = ['480','720','1080','1440','2160'];
  const prefs = [['quality','Quality'],['size','Size'],['seeders','Seeders']];

  // Sub-page within Settings — matches Hayase's sidebar nav
  type SettingsPage = 'general' | 'extensions';
  let page: SettingsPage = 'general';
</script>

<div class="flex flex-col h-full overflow-y-auto" style="-webkit-overflow-scrolling:touch;">

  <!-- ── Top nav tabs (General / Extensions) ───────────────────────────── -->
  <div class="sticky top-0 z-10 bg-background border-b border-border px-4">
    <div class="flex gap-1 py-3">
      {#each [['general','General'],['extensions','Extensions']] as [key, label]}
        <button
          class="flex-1 py-1.5 rounded-lg text-sm font-bold transition-colors
            {page === key ? 'bg-foreground text-background' : 'text-muted-foreground'}"
          on:click={() => { page = key as SettingsPage; }}
        >{label}</button>
      {/each}
    </div>
  </div>

  <div class="flex flex-col gap-4 p-4">

    {#if page === 'general'}
      <!-- ── General Settings ───────────────────────────────────────────── -->
      <div class="pt-1">
        <h1 class="text-2xl font-black">Settings</h1>
        <p class="text-sm text-muted-foreground mt-0.5">Customize your experience</p>
      </div>

      <!-- Playback section -->
      <div class="font-weight-bold text-xl font-bold">Playback Settings</div>

      <SettingCard title="Auto-Play Next Episode" description="Automatically play the next episode when one finishes.">
        <label class="relative inline-flex items-center cursor-pointer">
          <input type="checkbox" class="sr-only peer" bind:checked={$settings.playerAutoplay} />
          <div class="w-11 h-6 bg-muted rounded-full peer peer-checked:bg-[rgb(61,180,242)] transition-colors" />
          <div class="absolute left-0.5 top-0.5 bg-white w-5 h-5 rounded-full transition-transform peer-checked:translate-x-5" />
        </label>
      </SettingCard>

      <SettingCard title="Auto-Complete Episodes" description="Mark episode as watched at 85% progress. Requires AniList login.">
        <label class="relative inline-flex items-center cursor-pointer">
          <input type="checkbox" class="sr-only peer" bind:checked={$settings.playerAutocomplete} />
          <div class="w-11 h-6 bg-muted rounded-full peer peer-checked:bg-[rgb(61,180,242)] transition-colors" />
          <div class="absolute left-0.5 top-0.5 bg-white w-5 h-5 rounded-full transition-transform peer-checked:translate-x-5" />
        </label>
      </SettingCard>

      <!-- Search section -->
      <div class="font-weight-bold text-xl font-bold">Search Settings</div>

      <SettingCard title="Default Quality" description="Preferred torrent resolution when auto-selecting.">
        <select
          class="bg-neutral-800 text-foreground text-sm font-bold rounded-lg px-3 py-1.5 border border-border outline-none"
          bind:value={$settings.searchQuality}
        >
          {#each qualities as q}
            <option value={q}>{q}p</option>
          {/each}
        </select>
      </SettingCard>

      <SettingCard title="Auto-Select Torrent" description="Automatically picks the best result based on quality and seeders.">
        <label class="relative inline-flex items-center cursor-pointer">
          <input type="checkbox" class="sr-only peer" bind:checked={$settings.searchAutoSelect} />
          <div class="w-11 h-6 bg-muted rounded-full peer peer-checked:bg-[rgb(61,180,242)] transition-colors" />
          <div class="absolute left-0.5 top-0.5 bg-white w-5 h-5 rounded-full transition-transform peer-checked:translate-x-5" />
        </label>
      </SettingCard>

      <SettingCard title="Lookup Preference" description="What to prioritize when ranking torrent results — Quality, Size, or Availability (seeders).">
        <select
          class="bg-neutral-800 text-foreground text-sm font-bold rounded-lg px-3 py-1.5 border border-border outline-none"
          bind:value={$settings.lookupPreference}
        >
          {#each prefs as [val, label]}
            <option value={val}>{label}</option>
          {/each}
        </select>
      </SettingCard>

      <!-- Interface section -->
      <div class="font-weight-bold text-xl font-bold">Interface Settings</div>

      <SettingCard title="Hide Spoilers" description="Blur episode thumbnails and summaries until you have watched the episode.">
        <label class="relative inline-flex items-center cursor-pointer">
          <input type="checkbox" class="sr-only peer" bind:checked={$settings.hideSpoilers} />
          <div class="w-11 h-6 bg-muted rounded-full peer peer-checked:bg-[rgb(61,180,242)] transition-colors" />
          <div class="absolute left-0.5 top-0.5 bg-white w-5 h-5 rounded-full transition-transform peer-checked:translate-x-5" />
        </label>
      </SettingCard>

    {:else}
      <!-- ── Extensions ─────────────────────────────────────────────────── -->
      <div class="pt-1">
        <h1 class="text-2xl font-black">Extensions</h1>
        <p class="text-sm text-muted-foreground mt-0.5">Manage torrent source extensions</p>
      </div>
      <Extensions />
    {/if}

    <div class="h-4" />
  </div>
</div>
