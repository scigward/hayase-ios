<script lang="ts">
  import './app.css';
  import { currentTab, currentRoute, goBack, searchRequest } from './lib/store';
  import TabBar from './components/TabBar.svelte';
  import Toast from './components/Toast.svelte';
  import Home from './pages/Home.svelte';
  import Search from './pages/Search.svelte';
  import AnimeDetail from './pages/AnimeDetail.svelte';
  import Downloads from './pages/Downloads.svelte';
  import Schedule from './pages/Schedule.svelte';
  import Settings from './pages/Settings.svelte';
  import SearchModal from './pages/SearchModal.svelte';

  $: route = $currentRoute;
</script>

<div id="root" class="flex flex-col h-screen bg-black text-white overflow-hidden">
  <div class="flex-1 overflow-hidden relative">
    {#if route.page === 'home'}
      <Home />
    {:else if route.page === 'search'}
      <Search initialQuery={route.query ?? ''} />
    {:else if route.page === 'anime'}
      <AnimeDetail id={route.id} />
    {:else if route.page === 'downloads'}
      <Downloads />
    {:else if route.page === 'schedule'}
      <Schedule />
    {:else if route.page === 'settings'}
      <Settings />
    {/if}
  </div>
  <TabBar />
  <SearchModal />
  <Toast />
</div>
