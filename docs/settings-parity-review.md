# Settings and route-transition implementation review

## Splash, extension badges/icons, and support button follow-up

Baseline: 703717a. Sources: interface static/logo_white_fit.svg, app.html (black startup background), src/lib/components/icons/Simkl.svelte, ui/extensions/ExtensionCard.svelte, SearchModal.svelte, app.css, and routes/app/settings/+layout.svelte.

- Native launch screen: LaunchScreen.storyboard is plain black. The interface shows no logo before its animated splash page (see splash-parity-review.md), and no forced delay was added.
- Badges: SettingsExtensionCardView fixes the action column at its content width so the text/badge column can grow. Shared BadgeFlowView in ExtensionsViewController resists height compression and invalidates its measured height on width changes. Source uses wrapping rows and 8-point gaps; wrapping itself is intentional.
- Images: settings icons retain the source's explicit accent background and use the image element's fill sizing. Search-result icons in ExtensionSearchViewController have no background or corner rounding, matching SearchModal.svelte. Embedded backgrounds in downloaded images are not altered.
- Simkl: TrackerIcons.swift now uses SimklLogo.imageset, copied from the actual source SVG, instead of a letter placeholder.
- Donate: SettingsLayoutView uses SettingsSupportButton. Filled 18-point heart, #fa68b6, 8-point gap, 12-point bold Nunito, source 32-point button height, glow, and 1-second alternating scale 1 to 0.85. Animation stops off-window, in background, or for reduced motion. CSS drop-shadow vs Core Animation rendering and web idle detection vs native application activity remain unverified/different; exact device-pixel parity is not claimed.
- Validation: source-contract checks, asset-manifest references, vector/storyboard XML parsing, and git diff --check. No Swift compilation, asset-catalog compilation, or iOS runtime execution on this Windows host. GitHub builds are not checked; the user uses Codemagic. No patch artifact requested. Device checks still needed: cold launch, narrow/wide extension cards after import/resize, transparent icons, Simkl visibility, and donate animation/lifecycle.

## Status

Source implementation and source-contract checks completed; **not an iOS build or runtime approval, and not a claim of complete visual parity**. The reported iPad/iPhone symptom still requires device verification. Player ownership, rendering-surface transfer, and miniplayer lifetime code were not changed.

Native baseline: `66cbe6a3d6d31ae9e96e10cbf9deedfcfe723534` on `codex/webtorrent-backend-switch`. The newer Lucide dependency update was fast-forwarded without replacing it.

Interface reference: `hayase-app/interface@cde83e26b84d632494c446a45053851c93b593d2`.

## Findings and implementation

- Confirmed layout hazards in the previous implementation included mixed table-header/aside sizing and an explicitly constrained footer label with autoresizing-mask translation still enabled. These are confirmed source defects, **not a runtime-proven explanation of the screenshot**.
- Settings now uses a measured, non-stretching header and one manually sized scroll area. Its controller orchestrates routes rather than owning every cell and account implementation.
- The destination is committed and laid out without implicit animation before the old route snapshot fades. Previously, the route mutation ran inside a UIKit transition. Interrupted transitions remove their stale snapshot first. The existing fullscreen/mobile-player/history exclusions remain in the sidebar.
- A route comparison replaces the selected-tab-only guard, allowing the compact settings index to navigate to Player.
- Existing Input, ComboBox, CommandPopoverViewController, GhostButton, BadgeFlowView, icon/font/theme helpers, auth services, settings persistence, changelog service, and torrent backend ownership are reused.
- Extension management is inline in settings. Import/delete/options use ExtensionService; source-code retrieval belongs there rather than in the view.
- Authentication, sync, account settings, import/export, UI-scale confirmation/reversion, and live torrent settings updates remain connected. Fractional torrent speed is no longer truncated by integer parsing.
- Obsolete SettingsCells.swift and AccountCardCell.swift were replaced by focused views; their old versions remain recoverable through Git.

## Source of truth

Web files read for the implementation:

- `src/routes/+layout.svelte`, `src/routes/app/+layout.svelte`
- `src/routes/app/settings/+layout.svelte`, `+page.ts`, `+page.svelte`
- `src/routes/app/settings/{player,client,interface,extensions,accounts,app,changelog}/+page.svelte`
- `src/lib/components/SettingCard.svelte`, `SettingsNav.svelte`
- `src/lib/components/ui/{button,label,input,switch,slider,toggle,toggle-group,combobox}/`
- `src/lib/components/ui/extensions/{extensions,ExtensionCard,ExtensionSettings}.svelte`
- `src/lib/components/ui/dialog/{dialog-content,dialog-overlay}.svelte`
- `src/lib/components/ui/sonner/`, `src/lib/utils.ts`
- `src/lib/modules/settings/util.ts`, extension storage/service dependencies
- `src/app.css`, `tailwind.config.ts`
- License route and build configuration (to establish that the dependency license text is generated).

The route fade follows the CSS View Transitions default of 250 ms and CSS ease, because the source's animation-name declaration contains an invalid shorthand value. Reference: https://www.w3.org/TR/css-view-transitions-1/ . Browser rendering/blending was not executed in this environment.

## Source-derived geometry

| Element | Implemented values |
| --- | --- |
| Header | Nunito 24 bold / 32 line height; description 16 / 24; gap 2 |
| Page padding | 12 below md; 40 from md |
| Separator margins | 12 below md; 24 from md |
| Breakpoints | 640 preview grid; 768 card orientation; 1024 wide aside |
| Wide body | max 1440; aside 240; column gap 48; content max 1152 |
| Setting cards | muted token; radius 6; horizontal padding 24; vertical padding 16; gap 12 |
| Card text | title 14 bold / 20; description 12 medium / 16 |
| Switch | track 32 x 16; thumb 12; 150 ms |
| Account card | accent header; muted footer; avatar 32; tracker icon 24 |
| Extension card | padding 16 x 12; radius 6; icon 40; title 16 / 24; badges 14 |
| Route fade | 250 ms; cubic control points (0.25, 0.1), (0.25, 1) |
| Dialog | max 512 by default; padding 24; gap 16; 200 ms fly/scale, 150 ms backdrop |

Widths use the scaled root viewport instead of the remaining content width after the sidebar. Narrow/wide layout reacts to bounds changes. Reduced-motion disables route and dialog animation.

## Native file map

All paths below are relative to `Hayase/Source/` unless otherwise stated.

| File | Responsibility |
| --- | --- |
| App/UIColor+HayaseTheme.swift | Shared popover token |
| Components/UI/Extensions/ExtensionsViewController.swift | Backward-compatible BadgeFlowView customization |
| Components/UI/Profile/AccountCardCell.swift | Removed old monolithic table-cell implementation |
| Components/UI/Profile/AccountCardView.swift | Account layout/state rendering |
| Components/UI/Profile/AccountCardView+Authentication.swift | Existing auth flows and Kitsu dialog |
| Components/UI/Profile/AccountCardView+Settings.swift | Shared-control account dialogs |
| Components/UI/Settings/SettingsCardView.swift | Reusable cards, typography, input/action/slider controls |
| Components/UI/Settings/SettingsDialogViewController.swift | Shared dialog and nonblocking message presentation |
| Components/UI/Switch/HayaseSwitch.swift | Source-sized accessible switch |
| Components/UI/Sidebar/HayaseRouteTransition.swift | Layout-first, interruptible snapshot fade |
| Components/UI/Sidebar/HayaseSidebarController.swift | Root snapshot scope and transition cancellation |
| Modules/Extensions/ExtensionModels.swift | Optional deprecated/manifest-version metadata |
| Modules/Extensions/ExtensionService.swift | Source-code retrieval |
| Modules/Torrent/Backend/TorrentBackendSettings.swift | Fractional speed serialization |
| Modules/Torrent/TorrentService.swift | Fractional speed conversion for legacy backend |
| Routes/App/Settings/HayaseDebugViewController.swift | Preserved copy-device-info action |
| Routes/App/Settings/SettingsCells.swift | Removed obsolete cell collection |
| Routes/App/Settings/SettingsSectionCatalog.swift | Section metadata and inline extensions |
| Routes/App/Settings/SettingsViewController.swift | Route and page-state orchestration |
| Routes/App/Settings/SettingsViewController+Content.swift | Section/control composition |
| Routes/App/Settings/SettingsViewController+Actions.swift | Existing persistence/service actions |
| Routes/App/Settings/SettingsLayoutView.swift | Header, scroll region, navigation/support/footer |
| Routes/App/Settings/SettingsPreviewGridView.swift | Subtitle and theme-preview tiles |
| Routes/App/Settings/SettingsThemePreviewPalette.swift | Source theme-preview swatches |
| Routes/App/Settings/SettingsChangelogView.swift | Responsive changelog/loading/error rendering |
| Routes/App/Settings/SettingsExtensionCardView.swift | Extension card and status lifetime |
| Routes/App/Settings/SettingsExtensionsView.swift | Inline tabs/import/list/options/source dialogs |
| Source-check script (since removed at user request) | Historical source-contract and delimiter regression checks |

## Known differences and unresolved verification

These are **remaining gaps**, not claims that UIKit makes exact parity impossible.

- Themes remain nonfunctional by explicit user scope. System/Custom previews are static fallback swatches; global dynamic theme parity is not implemented.
- Dialog backdrop currently has the shared stripe pattern but not the source's 4 px backdrop blur. Native shadow/keyboard containment and close-icon geometry have not been visually matched. UI-scale keep/revert still dismiss immediately.
- Toasts are nonblocking but do not reproduce Sonner's icons, stack, swipe dismissal, or full animation behavior.
- Source-code display uses the system monospaced font rather than Geist Mono; its dialog dimensions and on-demand retrieval do not match the web's cached source presentation.
- Extension/repository/option order uses sorted native dictionary keys, not the web's insertion order.
- Donation heart geometry/heartbeat and changelog skeleton timing still differ.
- Some preview/account/changelog labels use UIKit font metrics rather than explicit CSS line-height attributes; all wrapping needs device comparison.
- License Information opens the upstream repository license; it does not yet show the generated dependency-license page in-app.
- Existing native ASWebAuthenticationSession, document picker/share UI, and reset confirmation are preserved. Those system/safety flows differ from the browser flows. Individual extension deletion remains available through a native context menu.
- Native sandbox download-location choices and device/version text remain platform-specific.
- The source selection-highlight animation comes from the reused HayaseNavTabButton; its pixel/timing parity and interrupted-route behavior have not been run on-device.
- Static inspection does not prove absence of Auto Layout warnings, route crashes, video snapshot artifacts, or scroll-position differences.

## Verification

- `node scripts/check_settings_source.mjs`: PASS, including delimiter checks for 19 Swift files and contracts for measured header layout, shared combos, inline extensions, route mutation outside the fade, and fractional speeds.
- `git diff --check`: PASS.
- `git apply --check`: not applicable; direct commit/push requested instead of patch delivery.
- Swift syntax parse: NOT RUN.
- Type checking: NOT RUN.
- Xcode project build: NOT RUN locally; no swift/swiftc/xcodebuild available on this Windows host.
- iPhone/iPad runtime: NOT RUN.
- GitHub build status must be checked against the pushed commit; an empty status result is not a build success.

Device acceptance remains outstanding: first visit/revisit, settings index and all tabs, iPhone portrait/landscape, iPad and resized/split windows, large UI scale with keep/revert, keyboard editing, account login/logout, extension loading/error/empty/import/options, rapid route switching/back/forward, reduced motion, and active player -> other route -> miniplayer -> player. Compare against the same interface reference and equivalent logical viewport.

## Follow-up: Extensions, switch sizing, clipped text, compact routing

Incremental baseline: `75e985c`. Source references remain SettingCard.svelte (growing label and content-sized control), ui/switch/switch.svelte (nonshrinking 32 x 16 track), ui/label/label.svelte and dialog heading (short CSS line boxes), and the app sidebar/router.

- SettingsExtensionsView now finishes ExtensionService initialization before registering the defaults observer. Defaults notifications defer service reads to the next main-queue turn. Previously synchronous observation could re-enter the singleton during initialization or read configs during its didSet mutation. This is a confirmed reentrancy hazard; without a crash trace it is not a runtime-proven diagnosis of this particular crash.
- HayaseSwitch resists stretching/compression on both axes. SettingsCardView assigns controls stronger horizontal hugging than the growing text column, preserving any stronger existing priority. This addresses the narrow 18+ description column and displaced switches without changing source track dimensions.
- SettingsTypography reserves at least Nunito's actual line height. CSS allows glyph overflow outside leading-none line boxes; UILabel does not render those boxes identically. Native line boxes can therefore be taller than the CSS numeric value to avoid cutting off Enable Sync and dialog headings. Device typography comparison remains outstanding.
- HayaseSidebarController retains all original navigation stacks in routeControllers but installs only the active stack in the hidden UITabBarController. UIKit therefore has no overflow tabs to route through More. Logical indexes are stored independently in HayaseTabIndex, including while stacks are detached; active player presentation still uses the existing tab/navigation containment APIs. The obsolete selectedIndex observer was removed because the visible slot is always zero, not the logical route index.
- Files changed: SettingsExtensionsView.swift, SettingsCardView.swift, HayaseSwitch.swift, HayaseSidebarController.swift, HayaseTabIndex.swift, scripts/check_settings_source.mjs, and this report. No player rendering or miniplayer lifetime code changed.
- Validation: source contracts and delimiter checks cover 21 Swift files; git diff --check passed. No Swift parse/type-check, Xcode build, or device execution was available. No patch artifact was requested. Recheck extension first launch with saved configurations, import/update/options, every route on compact screens, switch rows, account/dialog headings, back/forward, and player/miniplayer navigation on-device.
