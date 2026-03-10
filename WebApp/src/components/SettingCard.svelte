<!--
  SettingCard.svelte — mirrors Hayase's SettingCard.svelte.
  bg-neutral-950, rounded-md, flex row on desktop. Title + optional description + slot control.
-->
<script lang="ts">
  export let title: string;
  export let description: string = '';
</script>

<div class="bg-neutral-950 rounded-md px-6 py-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 w-full">
  <div class="flex flex-col gap-0.5">
    <span class="font-bold text-sm text-foreground">{title}</span>
    {#if description}
      <span class="text-xs text-muted-foreground">{description}</span>
    {/if}
  </div>
  <div class="shrink-0">
    <slot />
  </div>
</div>
