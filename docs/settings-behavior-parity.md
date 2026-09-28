# Settings behavior review

Reference: `hayase-app/interface` settings pages, `modules/settings`,
`EpisodesList.svelte`, anime `[id]/+layout.svelte`, `preview.svelte`,
`player.svelte`, and `subtitles.ts`.

## Corrected in this pass

- Spoilers: mask every unwatched episode, including the next episode; exempt
  completed and rewatching lists. Blur episode images/descriptions by 6 logical
  points and rating badges by 3, without a system backdrop tint. Concealed ratings
  use the interface's placeholder values. Header scores are masked only for
  CURRENT/PLANNING entries. Tag blur now accounts for Retina scale.
- Subtitle render limit: **1080p is an explicit user-requested exception** to the
  web mobile default. Do not change it to 720p when syncing upstream. Preserve
  explicitly chosen user values. Render-limit changes apply to the next player;
  subtitle-style changes apply to the active player.
- Debanding: apply the saved value when a file loads and apply changes live.
- Display settings: cached home/search/detail views refresh after preference
  changes; account language/content-filter changes also refresh home/search data.
- Torrent settings: retain fractional speed limits, honor new download folders
  for subsequent torrents, reject stale overlapping folder updates, and align
  bridge defaults with the settings UI. Existing downloads are not relocated.
- Logging: send the interface's namespace strings to the bundled debug singleton;
  update active MPV logging and enable native route diagnostics for Interface/All.
- Settings files: use web field names/types, accept legacy native exports,
  validate before replacement, and notify consumers after the complete import.
  Preserve unsupported desktop/theme fields for round trips without applying them.
- Reset: stop playback/lobby/workers, clear account sessions and persisted settings,
  invalidate in-flight extension installs, and recreate the storyboard shell.
- Account content-filter switch: prevent overlapping mutations and restore the
  confirmed account value on failure.
- Compact episode activation: the card tap is the single search-opening path;
  table row selection must not present another independently auto-selecting modal.

## Deliberately unchanged

- Themes remain outside the requested scope.
- Navigation Buttons is desktop-only in the interface; no extra iOS navigation
  controls were added. Minimal Player UI hides download statistics, matching web.
- Preferred audio/subtitle languages are initial track-selection preferences.
- Existing native confirmations and iOS sandbox download-location choices remain.

## Verification and device checks

Passed: `git diff --check`, bridge JavaScript syntax, build-script shell syntax,
and executable tests against the bridge's actual settings functions covering
fractional limits, defaults, folder updates, stale update rejection and debug
forwarding. Source-reviewed Swift symbols, call sites and source inclusion.

No Xcode/iOS build or simulator is available on the Windows editing host. No CI
build was requested or checked. On device, verify spoiler rendering at multiple
scales, changing settings during playback, web/legacy settings import, reset,
and one-tap episode search on iPhone (including cancellation before auto-select).
These checks are required before claiming pixel-exact or fully runtime-tested parity.
