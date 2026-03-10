import staticAdapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  compilerOptions: {
    runes: false,
  },
  onwarn: (warning, handler) => {
    if (warning.code.includes('a11y')) return;
    if (warning.code === 'element_invalid_self_closing_tag') return;
    handler?.(warning);
  },
  preprocess: vitePreprocess(),
  kit: {
    // Output to TheAnimeTool/Resources/webapp/ so Xcode bundles it into the app
    adapter: staticAdapter({
      pages: '../TheAnimeTool/Resources/webapp',
      assets: '../TheAnimeTool/Resources/webapp',
      fallback: 'index.html',
      strict: false,
    }),
    // Disable service worker (not applicable in WKWebView)
    serviceWorker: {
      register: false,
    },
  },
};

export default config;
