<!--
  LoadImg.svelte — mirrors Hayase's src/lib/components/ui/img/load.svelte
  Wraps an image in a colored placeholder div, applies blur+fade-in on load.
-->
<script lang="ts">
  import { cn } from '../lib/util';
  export let src: string | null | undefined = '';
  export let alt: string = '';
  export let color: string | null | undefined = 'transparent';
  let className: string = '';
  export { className as class };

  let ready = false;

  async function onLoad(e: Event) {
    const img = e.currentTarget as HTMLImageElement;
    try { await img.decode(); } catch {}
    ready = true;
  }
</script>

<div style:background={color ?? '#1a1a2e'} class={cn('overflow-clip', className)}>
  <img
    {src}
    {alt}
    on:load={onLoad}
    class={cn(
      'w-full h-full object-cover duration-300',
      !ready ? 'opacity-0' : 'img-load-in',
      className
    )}
    decoding="async"
    loading="lazy"
    style:background={color ?? '#1a1a2e'}
  />
</div>
