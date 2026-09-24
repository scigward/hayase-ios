# AniList rich text runtime

Production resources used by AniListRichTextView's existing WKWebView, not build or verification scripts. All parser code is bundled; no CDN or npm install is needed in Codemagic or at app runtime.

Reference: hayase-app/interface cde83e26b84d632494c446a45053851c93b593d2, src/lib/components/Shadow.svelte and pnpm-lock.yaml.

- marked.umd.js: marked 18.0.6, npm package lib/marked.umd.js (MIT; marked-LICENSE.txt).
- purify.min.js: DOMPurify 3.4.12, npm package dist/purify.min.js (Apache-2.0 OR MPL-2.0; included license files).
- AniListRichText.js: shared AniList syntax preprocessing, Marked configuration, DOMPurify allowlist and controlled media generation.

Intentional fixes versus the reference: slugless anime URLs preserve the last ID digit; YouTube iframes have a real closing tag; WebM URLs require HTTP(S) and play inline on iOS; final generated markup is sanitized again. The source's limited tag allowlist is preserved, including filtering out table elements and task checkboxes. Mentions remain non-navigating, matching the reference's href='#'.

The native host injects this runtime in WebKit's isolated client content world. User content is JSON-encoded, rendered through DOMPurify, and protected by CSP; external navigation only permits HTTP(S)/mailto. Profile descriptions scroll at 200pt. Threads/comments expand, including after image loading, font loading and spoiler toggles. Content height is measured independently of the WKWebView viewport so it can shrink.

Do not recreate separate profile/thread parsers. Update these pinned libraries and the fixture comparisons together when updating the interface reference.
