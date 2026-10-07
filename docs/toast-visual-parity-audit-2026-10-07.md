# Toast visual parity audit — 2026-10-07

## References and scope

- Native baseline: `a85da3bb29435ed422048a01447d3f5083b56c60` (latest `master` when fetched).
- Interface: `hayase-app/interface` at `cde83e26b84d632494c446a45053851c93b593d2`.
- Exact package version from interface's lockfile: `svelte-sonner@0.3.28`, tag commit
  `a5895f21149779cd829e6039f8d3f8c3ca55f494`.
- Authoritative files: interface `src/routes/+layout.svelte`, `src/app.css`,
  `components/ui/sonner/sonner.svelte`, `components/ui/chat/MessageToast.svelte`,
  `components/ui/chat/ChatProfile.svelte`, `components/ui/profile/Profile.svelte`,
  `components/ui/avatar/{avatar,avatar-fallback}.svelte`; Sonner
  `src/lib/{Toaster,Toast,Icon,Loader}.svelte` and `state.ts`.

This is a source-level review of every existing native toast presenter and its
visual states, not a claim of pixel-verified UIKit rendering. Backend errors,
operation-specific wording and supplied durations remain owned by their callers.
Theme implementation is still intentionally excluded; this comparison uses the
interface's default dark palette rather than implementing other themes.

## Presentation contract

| Surface/state | Interface contract | Native implementation |
| --- | --- | --- |
| Container | Top-right, expanded, three visible; newest first; gap 14 | Shared `Sonner.swift` viewport/stack |
| Desktop/tablet | Width 356; top/right `max(32, safe-area)` | Same logical point geometry |
| Compact | Logical viewport <=600: margins 16, top 20, width viewport−32 | Same breakpoint, independent of device idiom |
| UI scale | Toasts inherit the mobile scaled viewport | Host scales its logical viewport and safe-area coordinates, observes UI-scale changes |
| Card | Padding 16 + border 1, radius 8; Tailwind `shadow-lg` | Two shadow layers with matching offsets/blur/spread and black/10 alpha |
| Colors | Background black; foreground 98%; description 50%; border 10% | Existing `HayaseTheme` tokens; no rich red/green backgrounds |
| Title/description | System UI 13 medium / 19.5 and 13 regular / 18.2; gap 2 | Shared `CSSText` line-box/baseline conversion; gap only when both exist |
| Whitespace | Title normal; description pre-line; long text wraps | Titles collapse whitespace; descriptions retain line breaks, not repeated horizontal whitespace |
| Icons | Filled error/success SVG20, even-odd paths, 16px slot with negative margins | Exact upstream paths rendered once through shared SVG parser; matching placement/tint |
| Loader | Twelve gray radial bars, 1.2s linear fade with staggered negative delays | Shared `Loader.swift`, not a platform spinner; respects reduced motion changes |
| Promise resolution | Same card; icon opacity0/scale.8 →1 in 300ms ease; loader fades/scales out in 200ms | Existing card updated in place; detail retained and stack height recalculated |
| Action | Height24, horizontal padding8, font12/18, radius4, text gap6, primary colors; no hover dim | Custom action button with CSS line-box metrics, centered in card |
| Action focus | Black/40%, 2px spread; shadow transition200ms ease | Keyboard focus observer, matching shadow animation; no platform button appearance |
| Enter/reflow | Transform, opacity and height400ms CSS ease `(0.25,0.1,0.25,1)` | Shared cubic-timed animation; fractional card heights and rounded stack offsets |
| Normal removal | Exit transition400ms; remove height immediately, unmount after200ms | Separate stack/card animation; retain toast index until removal |
| Swipe removal | Upward amount≥20; 200ms ease-out to current swipe amount−height | Shared styled/custom gesture; preserve last valid amount on direction cancellation |
| Rejected swipe | Restore transform400ms CSS ease | Same timing, independent of the stack's timer observer |
| Fourth toast | Opacity0/no pointer events until a visible slot opens; fades into that slot | Visibility participates in reflow instead of an immediate `isHidden` toggle |
| Hover/touch | Pause the whole stack, including gaps, loading cards, actions and newly arriving cards | Non-consuming window observers; recalculate stationary pointer containment after reflow |
| Lifetime | Default4s, caller overrides preserved; loading/infinite has no timeout | Remaining duration retained across whole-stack pause; no content-based deduplication |
| Reduced motion | No transitions/animations | Shared animations and loader obey the native accessibility setting |
| Chat notification | Transparent, unstyled, shadowless; right avatar32/ring4; column px8 | `MessageToast.swift`, reusing existing profile/bubble components |
| Chat text | System14 bold/20 name, system10/16.25 time, system12/16 bubble | Toast-only system fonts and CSS baselines; ordinary chat defaults unchanged |
| Compact chat header | Normal whitespace and flex shrink; wrapped header increases card height | Constrained multiline name/time metrics; bubble placed below the measured header |
| Chat avatar | Muted circular fallback, inherited system16/24 text, no loading skeleton; foreground ring on focus | Toast-only shared avatar mode; regular profile/follower appearances unchanged |
| Overlay | Above route content; no interaction interception outside toast content | Window overlay; transparent host/viewport hit testing passes through |

The interface does not call warning/info/default/cancel-button toast variants.
It does not enable toast close buttons or `richColors`. No unused native variants
or extra controls were added.

## Call-site coverage

All current native styled errors use `AppErrorToast`/`TorrentErrorToast`: extension
import/load/query failures, authentication/sync, settings import/export, player
screenshot/file errors, image search, torrent/backend/webseed failures, library
operations, and storage/debug errors. Success toasts (including screenshot
Download actions), loading/resolved library and image-search promises use the
same styled card. IRC and W2G notifications use the custom chat card in the same
stack. The unused bottom-right `SettingsToast` implementation was removed after
checking that it had no callers.

The shared implementation is split into stack/API (`Sonner.swift`), styled card
and text (`Toast.swift`), icons (`Icon.swift`), loader (`Loader.swift`), and swipe
interaction (`ToastInteraction.swift`), preserving existing call-site APIs.

## Validation and remaining device checks

- Reviewed the exact pinned Sonner source, not a newer Sonner release.
- Independently reviewed content/geometry and animation/lifecycle changes.
- Parsed all changed/new Swift files with the Swift tree-sitter grammar; no
  syntax errors. This does not substitute for Swift type checking or an iOS build.
- Checked duplicate declarations, toast call sites, recursive source inclusion,
  retained non-toast component defaults, and `git diff --check`.
- No Xcode/device runtime or build-service check ran on the Windows editing host.

Device acceptance matrix: iPhone portrait/landscape and large/split-view iPad;
logical widths600/601 and multiple UI scales; title-only/description-only/long
unbroken errors; four simultaneous toasts and removal of a middle card; normal
timeout/upward swipe/horizontal cancellation; pointer paused in a gap while a
card is removed; interaction with action/loading cards; promise success/error;
long chat usernames and localized times; pending/failed avatar images; keyboard
focus, reduced motion and VoiceOver; navigation/modals/miniplayer underneath the
overlay. Compare typography, antialiasing, shadow rasterization and animation
interruptions on-device before claiming pixel-identical native rendering.
