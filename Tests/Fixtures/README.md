# AniList rendering regression fixtures

anilist-rich-text.json contains 32 inputs with normalized DOM expectations generated from interface/Shadow.svelte at cde83e26b84d632494c446a45053851c93b593d2, using marked 18.0.6 and DOMPurify 3.4.12 in jsdom. YouTube deliberately fixes the source's invalid self-closing iframe; its source URL was compared separately. Comparison removes iframe style and the iOS-only playsinline attribute, and collapses inter-tag whitespace.

Executed locally: all 32 fixture comparisons, plus slugless AniList-ID routing output and script/event-handler/srcdoc/JavaScript-URL rejection assertions. This does not establish a 99% compatibility rate or prove WKWebView/device behavior.

To repeat, install jsdom in a temporary dependency directory, then run this Node snippet from the repository root (set JSDOM_PATH to that directory's node_modules/jsdom). No test JavaScript files need to be added to the app or repository:

```javascript
const fs = require('fs');
const assert = require('node:assert/strict');
const { JSDOM } = require(process.env.JSDOM_PATH);
const w = new JSDOM('', { runScripts: 'outside-only' }).window;
for (const file of ['marked.umd.js', 'purify.min.js', 'AniListRichText.js'])
  w.eval(fs.readFileSync('Hayase/Resources/RichText/' + file, 'utf8'));
for (const fixture of JSON.parse(fs.readFileSync('Tests/Fixtures/anilist-rich-text.json', 'utf8'))) {
  const div = w.document.createElement('div');
  div.innerHTML = w.HayaseRichText.render(fixture.input);
  div.querySelectorAll('iframe').forEach(el => el.removeAttribute('style'));
  div.querySelectorAll('video').forEach(el => el.removeAttribute('playsinline'));
  assert.equal(div.innerHTML.replace(/\s+(?=>)/g, '').replace(/>\s+</g, '><'), fixture.expectedHTML, fixture.name);
}
```

Device acceptance still required: iOS 16 and current iOS, local font loading, long profile scrolling, wide and narrow threads, slow/failed images, spoiler expand/collapse, YouTube/WebM playback, external links and in-app anime links. Source syntax/resource/diff checks passed; no iOS build ran on this Windows host.
