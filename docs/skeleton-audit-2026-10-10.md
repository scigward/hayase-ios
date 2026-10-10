# Skeleton audit, 2026-10-10

Every `animate-pulse` placeholder of the interface (`grep animate-pulse src`: 36 lines in 8 files) against its Swift counterpart. Nothing here was built or run on a device; the interface was read, not measured, except where the entry says so.

## The pulse

`animate-pulse` is `pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite`, opacity 1 to 0.5 and back. `HayaseSkeleton.startPulse` is that (1 s each way, same curve). The changelog had a copy of its own with `easeInEaseOut`.

## Do the card skeletons share the animation of the cards?

Yes, in the interface too: `skeleton.svelte` and `skeletontrace.svelte` both have `.item { animation: 0.3s ease 0s 1 load-in }`, the same as `small.svelte` and `episode.svelte`. A skeleton has no hover, no `select:` and no press scale (it is a `div`, not an `a`). So the load-in of a skeleton stays; what differed is below.

## Entries

| Skeleton (interface) | Swift | Result |
| --- | --- | --- |
| `skeleton.svelte` (card, 20 in `query`, 50 in `recommendation`) | `SkeletonCardCell` | Sizes, wrappers (`bg-background` around the pulse), spacing, `animate={false}` and the count match. Fixed: `.item` is `aspect-ratio: 152/290`, so its load-in turns about the middle of 290pt, not of the 256pt of the bars. Fixed: the search page and the recommendations of the anime page did not give a skeleton its place in the row, so all of them shared one mount key. |
| `skeletontrace.svelte` (50 in `trace`) | `SkeletonTraceCardCell` | Fixed: it had no `load-in`. |
| `skeleton-banner.svelte` | `SkeletonBannerCell` | Matches (the margins add up to the same bottom offset, 20 + 12 + 16). |
| `SearchModal.svelte` (12 cards) | `SearchModal.swift` | Fixed: the second bar is where `justify-between` puts it (13pt of free space between three rows, so 53pt from the top), not 4pt under the first. |
| `Comments.svelte` (4) | `ThreadCommentSkeletonView` | Matches. |
| `Threads.svelte` (4) | `makeThreadSkeletonCard` | Matches. |
| `Themes.svelte` (2) | `makeThemeSkeletonCard` | Fixed: the bar of the second row is centred in its 32pt row (76pt), it was 1pt high. |
| `changelog/+page.svelte` (5) | `HayaseChangelogSkeletonEntry` | Fixed: the shared pulse, and the pulse starts again when the page comes back on screen. |
| `Avatar.Fallback` of `Profile.svelte` | `ProfileAvatarView` | Fixed: the app pulsed a placeholder over the avatar while the image came, which the interface does not have (its fallback, the name on `bg-muted`, shows until the image is there). The pulse is gone and the fallback is the `bg-muted` circle. |

## Not done

- `SkeletonTraceCard animate={false}` (a query that has not started) has no case in the search page of the app.

## The writer

`Resources/Markdown/editor.html` showed the placeholder twice: the text area's own (with its lines) and OverType's `.overtype-placeholder`, which collapses the lines into one. The interface's `app.css` hides the second (`.overtype-placeholder { display: none !important }`); the page of the editor now does too.
