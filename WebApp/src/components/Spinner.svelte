<!--
  Spinner.svelte — Loading spinner matching Hayase's usage pattern.
-->
<script lang="ts">
  export let size: number = 24;
  export let strokeWidth: number = 2;
</script>

<svg
  xmlns="http://www.w3.org/2000/svg"
  width={size}
  height={size}
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width={strokeWidth}
  stroke-linecap="round"
  stroke-linejoin="round"
  class="animate-spin"
>
  <path d="M21 12a9 9 0 1 1-6.219-8.56" />
</svg>
