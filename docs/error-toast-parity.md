# Error toast parity audit

Reference: `hayase-app/interface`'s `toast.error` and `toast.promise` call sites,
plus its pinned `svelte-sonner@0.3.28` (`src/lib/Toaster.svelte`, `Toast.svelte`,
and `Icon.svelte` in https://github.com/wobsoriano/svelte-sonner/tree/v0.3.28).

## Wired native paths

| Interface error | Swift owner |
| --- | --- |
| Invalid extension URI / Invalid extension config / Extension Already Exists! | Both extension import screens and ExtensionService |
| Extension {id} Failed to load! | ExtensionService's post-load worker test; startup and disabled extensions stay quiet as in storage.ts |
| Kitsu Error / MAL Error / Simkl Error | Provider token and viewer requests; preserve API descriptions, Kitsu's multiple details, and MAL/Simkl HTTP response text |
| Login failed! | Account web-authentication failures and AniList login viewer request, excluding user cancellation |
| Failed to import settings / Failed to export settings | Settings file actions, including export share errors |
| Failed to copy logs! / Failed to save file! | Debug log/file export |
| Couldn't find anime for specified image! ... | Image search failure |
| Failed to rescan torrents / Failed to delete torrents | Torrent library actions |
| Low disk space | Successful WebTorrent startup, asynchronous upstream capacity check; threshold 1e9 bytes |
| Torrent Process Error! / Failed to add NZB | Existing bridge error events and metadata failures |
| Error fetching NZB / webseed / subtitles from {extension} | `ExtensionService` (`nzbURLs`, `webSeeds`, `subtitlesQuery`, through `querySources` and `callSources`), titled with the name of the extension |
| Saved screenshot to clipboard (with its Download action) / Failed to copy screenshot to clipboard. | `VideoPlayerViewController.captureScreenshot`; the toast has the action button of svelte-sonner. The failure has no download behind it: there is no frame to save |

Error titles and supplied durations come from the interface. API error bodies are
not replaced by generic credential advice. Native transport/decoding failures retain
their native descriptions where no provider error exists. Cancellation is not an error toast.

Torrent search method failures remain inline: `SearchModal.svelte` renders an
error block for each failed extension. Extension status checks on settings cards
also remain status indicators. Neither is a toast in the interface.

## No corresponding native operation yet / different platform operation

These are inventoried, not claimed as wired. Implementing them requires the
underlying feature, not an unused toast call:

- Explicit `createNZB` / `createHTTP` webseed additions: made by
  `WebTorrentWebSeeds.swift` after the extension queries; optional NNTP manager
  failures are reported by the bridge.
- MAL/Kitsu/Simkl full-list synchronization errors and missing sync credentials:
  native providers currently expose authentication, not those full sync operations.
- Plugin errors: no native web-plugin runner.
- Failed to set DoH: no native set-DoH operation.
- Download folder selection and setup storage errors: native settings use predefined
  sandbox locations, not the web directory picker/setup route.
- Theme clipboard errors: theme functionality remains outside the requested scope.
- Internal AniList API mode errors: no native unsafe-internal-API action.
- Browser mobile playback and audio-codec setup (`Mobile playback setup failed`,
  `Audio Codec Unsupported`): native playback uses MPV rather than these browser APIs.

## Shared presentation

`AppErrorToast` owns the overlay/stack; `ErrorToastCardView` owns typography, icon,
layout, timer and dismissal. Sonner uses system UI font, not the page's inherited
Nunito font. Error icons are filled 20px glyphs in a 16px slot. The interface does
not enable close buttons or rich error colors.

- Width 356; viewport offsets max(32, safe-area), top-right.
- At <=600: 16px horizontal margins, 20px top, full available width.
- 16px padding + 1px theme border, radius 8; title 13/19.5 medium,
  description 13/18.2 regular, text gap 2, stack gap 14.
- Theme background/foreground/muted description and Tailwind shadow-lg.
- Three visible expanded cards, newest first; slide/fade 400ms CSS ease,
  upward swipe dismissal at 20px, timer pause while interacting, reduced motion.
- Overlay hit testing passes through outside toast cards; accessible dismissal.

## Device verification still required

No Apple toolchain is available on the editing host. Check iPhone/iPad widths,
rotation, long provider errors, three simultaneous toasts, swipe/timer dismissal,
VoiceOver, and navigation underneath the overlay. Trigger a failed import, failed
login, failed library action, malformed settings file, and low-space condition.
Confirm cancelled authentication/share sheets stay quiet and torrent playback is
not delayed by the storage check.
