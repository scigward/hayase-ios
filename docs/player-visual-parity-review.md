# Player source-parity review

Reference: `hayase-app/interface` at `cde83e2`; native starting revision:
`7ff20d2675558f1b7d6caed755a938b8755fd2d6`.

## Spacing follow-up (2026-10-01)

- The player now opts into exact single-line CSS alignment boxes (stats 28pt,
  title 18pt, episode/chapter/time 14pt). Shadow and accent-glyph drawing bleed
  sits outside those boxes. Previously text was centred inside the extra
  shadow height, placing stats text below its icons and changing footer gaps.
  Homepage multiline labels keep their existing sizing/drawing path.
  Title/episode tap feedback also retains the line style when its underline ends.
- Stats retain the source's 16pt group gaps and 8pt icon gaps, with 18pt Lucide
  icons and both chained drop shadows. Speed formatting follows fastPrettyBits,
  including lowercase `kb` and removing an unnecessary trailing `.0`.
- A browser probe of the Tree CSS measured a 122px menu containing an expanded
  row and two leaf rows. Tree.Item's vertical margins collapse: a 2px row gap,
  38px expanded-row advance and 36px leaf-row advance. The submenu starts at
  x259/y2 relative to its outer parent, rather than x264/y0. Native geometry now
  uses those measurements, including the 4pt rounded-sm corners.
- Tall submenus preserve root centring. Tree movement uses Tailwind's 150ms
  cubic-bezier(.4,0,.2,1); the shared close button travels and scales with the
  rest of Dialog.Content. Chapter time labels share the title's 14pt leading.

These measurements verify CSS geometry; UIKit glyph rendering and animation
still require the compact/iPad checks below. No iOS build was run locally.

## Implemented

- Mobile controls follow `player.svelte`: 40-point previous/next controls,
  48-point play/options controls, matching glyph sizes, spacing, disabled state,
  typography, text shadows, bottom alignment and truncation priorities.
- Control visibility follows playback/buffering/idle state; spinner delay,
  rotation, fades and fast-forward feedback follow the reference timings.
- Seekbar uses chapter-local progress, buffered/hover layers, reference gaps,
  relative touch seeking and absolute pointer seeking. Scrubbing restores the
  prior pause state. Preview requests are bounded, cached and invalidated when
  switching sources without seeking the active playback instance.
- Options use the same adjacent tree structure on compact and large layouts,
  not a separate compact back-row menu. Widths, row padding, chapter time labels,
  playlist sizing, active colors and subtitle-delay input follow the source.
- Options backdrop and content have separate 150/200 ms transitions. Shared
  close/input/button/icon components are reused; cell and transition code are
  separated from the controller.
- Added the reference keyboard panel with saved drag/drop bindings, its 67-key
  layout and 22 default actions, plus external subtitle selection and a native
  Stats for Nerds panel.

## Validation performed

- Compared source against `player.svelte`, `options.svelte`, `seekbar.svelte`,
  `animations.svelte`, `downloadstats.svelte`, `keybinds.svelte`, `maps.ts`,
  `thumbnailer.ts`, `statsfornerds.svelte`, tree/dialog components and app CSS.
- Compared default binding identifiers/descriptions and ordered keyboard keys.
- Parsed changed Swift files with tree-sitter-swift. New component files parse
  cleanly. Existing `withHandle(())` and optional-cast parser limitations also
  occur in the baseline; this is not a Swift type-check or an Xcode build.
- `git diff --check` passes. XcodeGen already includes the entire source folder.
- Playback ownership, miniplayer transfer and the existing seek-glyph path were
  retained. The intentional 1080p subtitle rendering exception was not changed.

## Remaining differences and device acceptance

This is a source-level pass, not a claim of verified pixel-perfect output.
Windows cannot run UIKit or Xcode. Validate the following with a Codemagic build:

1. Compact landscape iPhone, narrow iPad window and full-size iPad: long titles,
   long chapters, all menu depths, long playlists, subtitle input and rotation.
2. Play/pause, idle fade, buffering, fast-forward, touch scrubbing, pointer hover,
   source changes while a preview is pending, and player/miniplayer round trips.
3. Keyboard drag/drop persistence, physical keyboard actions, subtitle importing,
   fullscreen, PiP and casts while options are open.

Known native differences that still prevent an unconditional 1:1 claim:

- Public UIKit backdrop blur has no numeric CSS blur-radius equivalent. The
  stats panel uses native live blur; compare its appearance on-device.
- MPV has no DOM ready-state or browser presented-frame callback counters.
  Stats reports native playback state and leaves unavailable counters as `-`.
- AVFoundation cannot generate future thumbnails for every MPV-supported
  format. Watched-frame MPV thumbnails are cached without moving playback.
- Physical modifier-only bindings and held-Space keyboard fast-forward are not
  implemented by the UIKeyCommand adapter. Touch hold behavior is retained.
- The existing native screenshot failure alert/success feedback and cast HUD
  are retained; screenshot download-action toast parity is not part of this
  implementation. These remain follow-up parity items, not verified matches.
