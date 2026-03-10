# NyaiS WebApp

Svelte/TypeScript webapp that runs inside a WKWebView as the UI for the NyaiS iOS app.

## Architecture

```
scigward/interface (source base)
         │
         ▼
    WebApp/src/          ← SvelteKit project (adapter-static)
         │  Two targeted changes vs interface:
         │  1. src/lib/anizip.ts: hayase.ani.zip → api.ani.zip
         │  2. window.native injected by NativeBridge.swift (no source change needed)
         │
         ▼ pnpm build
    TheAnimeTool/Resources/webapp/   ← bundled into .ipa
         │
         ▼ WKWebView (WebViewController.swift)
    iOS App
```

## window.native bridge

`NativeBridge.makeUserScript()` injects `window.native` at document start.  
`src/lib/modules/native.ts` from the interface repo does:

```js
export default Object.assign({ ...webFallbacks }, globalThis.native)
```

So our injected `window.native` overrides every web fallback automatically — **no source changes needed in native.ts**.

## Development

```bash
cd WebApp
pnpm install
pnpm dev          # http://localhost:5173 (uses web fallbacks from native.ts)
pnpm build        # outputs to ../TheAnimeTool/Resources/webapp/
```

## Fixes applied vs interface repo

| File | Change |
|------|--------|
| `src/lib/anizip.ts` | `hayase.ani.zip` → `api.ani.zip` (public API, no auth headers) |
| `svelte.config.js` | output path → `../TheAnimeTool/Resources/webapp`, SW disabled |
| `vite.config.ts` | `base: './'` for `file://` WKWebView loading |
