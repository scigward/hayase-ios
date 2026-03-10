import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [sveltekit()],

  // Needed when loading from file:// in WKWebView
  base: './',

  server: {
    port: 5173,
    open: true,
  },

  build: {
    target: 'esnext',
    // outDir is controlled by svelte.config.js adapter
  },

  worker: {
    format: 'es',
  },
});
