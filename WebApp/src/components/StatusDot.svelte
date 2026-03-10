<!--
  StatusDot.svelte — mirrors Hayase's src/lib/components/StatusDot.svelte
  Inline coloured dot indicating AniList list status.
  Variants exactly match Hayase's dotvariants.
-->
<script lang="ts">
  import { cn } from '../lib/util';

  export let variant: 'CURRENT' | 'PLANNING' | 'COMPLETED' | 'PAUSED' | 'REPEATING' | 'DROPPED' | 'PENDING' = 'CURRENT';
  let className: string = '';
  export { className as class };

  const colors: Record<string, string> = {
    CURRENT:   'bg-[rgb(61,180,242)]',
    PLANNING:  'bg-[rgb(247,154,99)]',
    COMPLETED: 'bg-[rgb(123,213,85)]',
    PAUSED:    'bg-[rgb(250,122,122)]',
    REPEATING: 'bg-[#3baeea]',
    DROPPED:   'bg-[rgb(200,80,80)]',
    PENDING:   'bg-[rgb(180,180,180)]',
  };
</script>

<span class={cn('inline-flex size-[0.55rem] me-1 rounded-full', colors[variant] ?? colors.PENDING, className)}>
  <slot />
</span>
