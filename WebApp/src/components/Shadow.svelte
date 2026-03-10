<!--
  Shadow.svelte — mirrors Hayase's src/lib/components/Shadow.svelte
  Renders sanitised AniList HTML descriptions in a Shadow DOM to prevent
  style bleed. Hayase uses DOMPurify + marked; we use a simplified inline
  sanitiser (no extra deps) since WKWebView already sandboxes the page.
-->
<script lang="ts">
  export let html = '';
  let className: string | undefined | null;
  export { className as class };

  const ALLOWED_TAGS = new Set([
    'a','b','blockquote','br','center','del','div','em','font',
    'h1','h2','h3','h4','h5','hr','i','img','li','ol','p','pre',
    'code','span','strike','strong','ul','details','summary',
  ]);
  const ALLOWED_ATTRS = new Set([
    'align','height','href','src','target','width','rel',
  ]);

  const sharedStyle = `
    p, details { margin-block-start:.5em; margin-block-end:.5em; }
    img, video { max-width:100%; -webkit-user-drag:none; }
    summary { font-weight:bold; cursor:pointer; list-style:none;
      background:#0003; display:inline-block; padding:.4em .8em;
      border-radius:.5em; margin-block-end:.5em; }
    * { color: inherit; }
  `;

  function sanitiseNode(node: Node): Node | null {
    if (node.nodeType === Node.TEXT_NODE) return node.cloneNode();
    if (node.nodeType !== Node.ELEMENT_NODE) return null;
    const el = node as Element;
    const tag = el.tagName.toLowerCase();
    if (!ALLOWED_TAGS.has(tag)) {
      // Replace disallowed element with its text content
      const span = document.createElement('span');
      el.childNodes.forEach(c => { const n = sanitiseNode(c); if (n) span.appendChild(n); });
      return span;
    }
    const out = document.createElement(tag);
    for (const attr of el.attributes) {
      if (ALLOWED_ATTRS.has(attr.name)) out.setAttribute(attr.name, attr.value);
    }
    el.childNodes.forEach(c => { const n = sanitiseNode(c); if (n) out.appendChild(n); });
    return out;
  }

  function buildContent(rawHtml: string): string {
    // AniList-specific transforms (mirrors Shadow.svelte)
    let h = rawHtml
      .replace(/~!([^]*?)!~/gm, '<details><summary>Spoiler, click to view</summary>$1</details>')
      .replace(/~{3}([^]*?)~{3}/gm, '<center>$1</center>');
    const wrapper = document.createElement('div');
    wrapper.innerHTML = h;
    const sanitised = document.createElement('div');
    wrapper.childNodes.forEach(n => { const s = sanitiseNode(n); if (s) sanitised.appendChild(s); });
    return sanitised.innerHTML;
  }

  function shadow(node: HTMLDivElement, html: string) {
    const root = node.attachShadow({ mode: 'open' });
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(sharedStyle);
    root.adoptedStyleSheets = [sheet];
    const update = (h: string) => { root.innerHTML = buildContent(h); };
    update(html);
    return { update };
  }
</script>

<div use:shadow={html} class={className ?? ''} />
