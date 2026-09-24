# Player, homepage, social routes and entry editor

Reference: hayase-app/interface at cde83e26b84d632494c446a45053851c93b593d2.

This change replaces the extension-search metadata alert with the player route's loading state. Search is dismissed before navigation, one player is hydrated after metadata resolution, and timeout/teardown release the pending coordinator. Route navigation continues through the shared shell transition.

Featured artwork callbacks are guarded by a slide generation. Reconfiguration preserves the selected slide, leaving/re-entering the page restarts rotation, and failed metadata requests no longer permanently cache a missing logo. Logo selection remains highest-voted English TMDB art with aspect ratio above 1.2. The logo targets 480 points within its parent instead of being limited by its intrinsic size or an extra height cap. Follower avatars use the shared clickable profile component.

The entry editor is split into a form and controller, reusing dialogs, typography and selection controls. Status, score, progress, repeat count, save/delete callbacks and custom lists are retained. Failed mutations keep the editor open with an error toast.

W2G and Global Chat use the interface's 768-point viewport breakpoint and content-sized compact participant lists capped at 40%. Schedule uses Monday-first dates, responsive day heights, My list filtering, episode links/status marks and a custom day drawer.

## Validation

- check_settings_source.mjs
- check_torrent_client_source.mjs
- check_player_home_parity.mjs (source contracts, changed-Swift delimiter checks and 84 calendar-month models)
- git diff --check

These are source-level checks, not Swift compilation or pixel/runtime verification. No GitHub build checks were performed.

Codemagic/device acceptance still needs: delayed/failed metadata, closing a loading player, next-episode search, player/miniplayer round trips, multiple featured rotations with slow artwork responses, profile taps, editor save/delete on local and AniList accounts, and chat/calendar layouts across compact and wide windows. Drawer gesture physics, desktop calendar hover previews and keyboard/pointer interactions have not been verified against the browser at runtime.

## Follow-up: stripes, loading lifecycle and featured timing

- SearchModal starts metadata first, animates its dialog out for 200 ms (overlay 150 ms), and waits 300 ms before navigating, matching SearchModal.svelte. The root source explicitly skips page view transitions on iOS, including iPad; that rule remains.
- Metadata loading stays inside the player's movable surface. Its spinner starts on window attachment and restarts on app activation. The pending phone player stays in the navigation shell; fullscreen starts after successful resolution. Miniplayer controls do not obscure the pending state.
- Featured advance is driven by the 15-second fill animation completion, not a separate repeating timer. A generation check rejects cancelled/stale animation completions. Cache/network refreshes update the visible cell without resetting it; selected media survives cell reuse. Only the page backdrop draws artwork, and queued updates check the currently visible cell and media.
- Homepage avatars use the source's 8-point overlap, transparent 4-point cutout and 1-point primary border instead of opaque 4-point rings.
- custom-bg is drawn as a continuous 40-degree, 10-point gradient with the CSS stops and alpha, avoiding fractional raster-tile seams. Opaque striped variants retain their CSS 119-point tile. Dialogs share the live blur/stripe component without an extra 55% black tint.
- Blur is a light native visual effect, not a screenshot. UIKit does not expose a public Gaussian pixel-radius setting, so CSS blur(4px) equality is NOT certified; device comparison remains necessary.
