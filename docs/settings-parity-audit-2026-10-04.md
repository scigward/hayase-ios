# Settings parity audit — 2026-10-04

Compared native baseline `f1dbe440069afc1d2ff05cebf101c8884e9654c8` with
[`hayase-app/interface` at `cde83e26`](https://github.com/hayase-app/interface/tree/cde83e26b84d632494c446a45053851c93b593d2).
This is a source-level audit, not a claim of pixel-perfect on-device validation.

## Tab coverage

| Tab | Verified and corrected in this pass |
| --- | --- |
| Player | iOS-visible row copy, ordering, choices and consumers checked; corrected subtitle-preview text metrics, extra image rounding/shadow, numeric suffix padding and shared input interactions. |
| Client | Corrected compact fluid download-path sizing, transfer-speed top alignment and pool placeholder (`5`, while the default remains `4`); folder selection now verifies the directory and shows the upstream 15-second failure toast without saving a bad location. |
| Interface | Corrected preview colors, sample controls, slider geometry/endpoints and keyboard shortcuts; UI-scale dialog now uses the web header spacing and responsive reversed footer. Theme activation remains intentionally deferred. |
| Extensions | Corrected badge line height/flag alignment, icon proportions/animations, repository icons, import/status help, secondary dialog buttons and source viewer sizing/scrolling. Installed source displays cached code. Unset values remain placeholders; clearing a number removes its override; select choices retain numeric/boolean/string types. Custom provider status text is preserved. |
| Accounts | Corrected animated settings icon, avatar fallback, text metrics, missing help tooltips, selector border, compact dialog headings, and Kitsu form/button/footer spacing. Existing authentication/sync functionality retained. |
| App | Row copy/iOS conditionals checked; import now restarts the native interface without an added success message, export also copies JSON, and volume imports/exports map to the actual player preference. |
| Changelog | Corrected effective sibling spacing, gutters, typography, error placement, skeleton dimensions/pulse and sticky dates. Removed a narrow-column required-constraint conflict. |

Shared settings controls now reuse `SelectButton` variants for hover/press/disabled behavior.
Settings labels activate their enabled switch/input. The shared tooltip delay is 700ms,
not 700 seconds; long help text wraps, and replacing status help removes the old hover recognizer.
Input press targets are weak to avoid retaining a field or its parent through a cycle.

## Source distinctions preserved

- Installed extension source: `80vw × 70vh`; preview source: natural `!w-auto`, capped at 95%.
- Tracker settings use a responsive `Dialog.Header`; extension titles sit directly in content and remain left-aligned.
- Settings row layout changes at 768px; download-path width changes at 640px; navigation changes again at 1024px.
- Android-TV-only custom-player and non-iOS external-player/desktop settings are not added to iOS.

## Exceptions and remaining gaps

- **1080p subtitle render default is the explicit user exception.** Its existing explanatory code comment is preserved.
- **Themes remain preview-only**, as requested. No custom-theme editor or global theme wiring was added.
- Native authentication, document/share UI, Keychain storage, reset confirmation and valid numeric/socket safety bounds remain intact. These are not literal browser-equivalent flows; the existing reset exception is recorded in `settings-parity-review.md`.
- **Extension ordering remains different:** native configs, repositories and option keys are alphabetically sorted; web object iteration retains insertion order. Swift dictionaries/persisted configs do not currently retain the necessary source-order metadata. This pass does not claim that gap is fixed.
- Native autoplay emulates EOF from position updates and schedules the next episode after 0.5s; web uses the renderer's ended event immediately. The native detector also fires near `duration - 0.5`, so removing the delay alone could truncate playback. This needs an on-device EOF check, not a speculative settings change.
- Nunito's native line boxes keep the existing anti-clipping font-metric allowance. Native shadow rasterization, font leading and pointer focus still require visual comparison on a device.

## Validation and device checks

- Reviewed settings route/catalog copy and platform conditions against all seven current web pages and their shared components.
- Cross-reviewed changed APIs, enum cases, primitive select call sites, constraint priorities and dialog sizing.
- `git diff --check` and focused source-contract checks passed. No generated JavaScript helpers were added.
- No Xcode/UIKit build or runtime test was run: the Windows host has no Apple toolchain. No CI builds were checked.
- Check iPhone/compact iPad and full-width iPad: every tab, label activation, numeric editing, path selection, preview grid, scale keep/revert/countdown, tracker dialogs, extension option/source/preview dialogs, long lines, status help and Changelog scrolling. Check volume JSON round-trip and failed folder selection separately.
