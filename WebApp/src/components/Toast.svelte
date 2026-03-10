<!--
  Toast.svelte — Auto-dismissing toast notifications.
  Mirrors Hayase's toast system (Sonner-style bottom stack).
-->
<script lang="ts">
  import { toasts, removeToast } from '../lib/store';
</script>

{#if $toasts.length > 0}
  <div
    class="fixed bottom-safe-bottom left-0 right-0 flex flex-col-reverse items-center gap-2 z-[200] px-4 pointer-events-none"
    style="bottom: calc(env(safe-area-inset-bottom, 0px) + 5rem);"
  >
    {#each $toasts as t (t.id)}
      <div
        class="pointer-events-auto flex items-center gap-3 px-4 py-3 rounded-xl shadow-xl text-sm font-medium max-w-sm w-full animate-slide-up
          {t.type === 'error'   ? 'bg-red-900/90 text-red-100' :
           t.type === 'success' ? 'bg-green-900/90 text-green-100' :
           'bg-neutral-800/95 text-foreground'}"
      >
        {#if t.type === 'error'}
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
        {:else if t.type === 'success'}
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
        {:else}
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
        {/if}
        <span class="flex-1">{t.message}</span>
        <button class="opacity-60 hover:opacity-100" on:click={() => removeToast(t.id)}>
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
        </button>
      </div>
    {/each}
  </div>
{/if}

<style>
  @keyframes slide-up {
    from { opacity: 0; transform: translateY(1rem); }
    to   { opacity: 1; transform: translateY(0); }
  }
  .animate-slide-up {
    animation: slide-up 0.25s ease-out forwards;
  }
</style>
