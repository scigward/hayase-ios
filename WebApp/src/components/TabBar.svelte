<!--
  TabBar.svelte — iOS bottom navigation bar.
  5 tabs: Home, Search, Downloads, Schedule, Settings.
  Matches the screenshots exactly.
-->
<script lang="ts">
  import { currentTab, currentRoute, navigateTab } from '../lib/store';
  import { cn } from '../lib/util';

  const tabs = [
    {
      id: 'home' as const,
      label: 'Home',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>`,
    },
    {
      id: 'search' as const,
      label: 'Search',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>`,
    },
    {
      id: 'downloads' as const,
      label: 'Downloads',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="8 12 12 16 16 12"/><line x1="12" y1="8" x2="12" y2="16"/></svg>`,
    },
    {
      id: 'schedule' as const,
      label: 'Schedule',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>`,
    },
    {
      id: 'settings' as const,
      label: 'Settings',
      icon: `<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/></svg>`,
    },
  ] as const;

  $: activeTab = $currentTab;
</script>

<nav
  class="flex flex-row shrink-0 z-50"
  style="
    background: rgba(0,0,0,0.85);
    backdrop-filter: blur(20px);
    -webkit-backdrop-filter: blur(20px);
    border-top: 1px solid rgba(255,255,255,0.08);
    padding-bottom: env(safe-area-inset-bottom);
  "
>
  {#each tabs as tab}
    <button
      class={cn(
        'flex-1 flex flex-col items-center justify-center gap-1 py-2 border-none bg-transparent cursor-pointer transition-colors',
        activeTab === tab.id ? 'text-[rgb(61,180,242)]' : 'text-[#737373]'
      )}
      on:click={() => navigateTab(tab.id)}
    >
      {@html tab.icon}
      <span class="text-[10px] font-semibold">{tab.label}</span>
    </button>
  {/each}
</nav>
