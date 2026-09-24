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
