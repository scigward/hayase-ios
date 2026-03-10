<!--
  Pagination.svelte — mirrors Hayase's src/lib/components/Pagination.svelte
  Slot-based pagination with pages/range/hasNext/hasPrev/setPage slot props.
-->
<script lang="ts">
  export let currentPage = 1;
  export let count = 0;
  export let perPage = 15;
  export let siblingCount = 1;

  let pages: Array<{ page: number; type: string }> = [];

  $: {
    const edgeSize = 4 * siblingCount;
    const totalPages = Math.ceil(count / perPage);
    const startPage = Math.max(1, totalPages - currentPage < edgeSize ? totalPages - edgeSize : currentPage - siblingCount);
    const endPage   = Math.min(totalPages, currentPage < edgeSize ? 1 + edgeSize : currentPage + siblingCount);
    const items: typeof pages = [];

    if (startPage > 1) {
      items.push({ page: 1, type: 'page' });
      if (startPage > 2) items.push({ page: startPage - 1, type: 'ellipsis' });
    }
    for (let i = startPage; i <= endPage; i++) items.push({ page: i, type: 'page' });
    if (endPage < totalPages) {
      if (endPage < totalPages - 1) items.push({ page: endPage + 1, type: 'ellipsis' });
      items.push({ page: totalPages, type: 'page' });
    }
    pages = items;
  }

  $: totalPages = Math.ceil(count / perPage);
  $: range = {
    start: (currentPage - 1) * perPage,
    end: Math.min(currentPage * perPage, count),
  };
  $: hasNext = currentPage < totalPages;
  $: hasPrev = currentPage > 1;

  function setPage(page: number) {
    currentPage = Math.min(Math.max(1, page), totalPages);
  }
</script>

<slot {pages} {range} {hasNext} {hasPrev} {setPage} />
