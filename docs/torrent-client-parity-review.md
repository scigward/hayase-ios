# Torrent Client review — 2026-09-23

Reference: `hayase-app/interface` at `cde83e26b84d632494c446a45053851c93b593d2`.
Reviewed the client route layout and five page wrappers, overview/status/globe,
files/peers/trackers/library tables and cell renderers, column-header menus,
shared table/button primitives, and `modules/torrent/client.ts`.

## Changes

- Donate explicitly uses fixed 6pt configuration corners (`rounded-md`), not
  UIKit's adaptive configuration shape. Preserves the existing heart and pulse.
- Client heading 24pt, description 16pt, separator 1pt; centered 1440pt outer
  maximum. Breakpoints use the root logical viewport, including sidebar width.
- Overview progress: 2/4 columns at md; statistics: 1/3 at xl; protocols: 1/2/3
  at md/lg. Reusable grid keeps incomplete final rows aligned. Restored source
  typography, spacing, badge padding and green/blue/orange/purple status colors.
- Files, trackers and library retain columns in horizontal scroll containers.
  Library no longer removes its header or metadata on small screens. Files
  progress has its 128pt minimum; library series/name have 288pt minimums.
  File/library rows self-size for wrapped names instead of clipping at 48/56pt.
- Shared Asc/Desc menus for files, peers and library; select-all control and
  selection preserved across search. Library sorting also applies to legacy
  native rows using their available metadata. Missing series titles use the
  existing AniList single-title service instead of a permanent numeric fallback.
- Rescan/delete errors are surfaced with the existing toast component. Duplicate
  actions are disabled while pending. Delete confirms a frozen selection and
  lists names; a failed delete does not discard selection or remove local rows.
- Successful empty arrays clear cached rows, unlike failed requests. Poll results
  are serialized on the main queue and guarded against changed selection/backend
  and successful deletes. Tracker responses are checked against their requested
  hash. Playback navigation and existing player lifecycle were not rewritten.
- Bridge elapsed time now advances per observed torrent in seconds; remaining
  time remains milliseconds. Completion is exactly 1, not a premature 99.9%.
  Empty WebTorrent overview uses the interface's zero-value statistics.
- Extracted file/library cells and library sorting from the controller; reused
  existing icon, header, toast, backend and AniList services.

## Verification and boundaries

`node scripts/check_settings_source.mjs`,
`node scripts/check_torrent_client_source.mjs`, JavaScript syntax checking, and
`git diff --check` pass. The torrent script executes the bridge statistics
function with elapsed/remaining, completion, peers and missing-torrent cases;
its Swift checks are source contracts and delimiter checks only.

No Xcode/iOS build or runtime UI comparison was possible on Windows. No GitHub
builds were checked. This is not evidence of complete pixel-for-pixel parity.

Known differences requiring further work: UIKit menus/confirmation presentation
are native rather than web dropdown/dialog geometry; table column sizing uses
native minimum widths rather than the browser's automatic table algorithm;
library dates do not yet include the web's aging-warning icon/tooltip; refresh
cadences remain native; the optional legacy libtorrent backend still lacks the
web backend's peer/tracker data and library metadata rescan implementation.
Those existing backend limitations were not replaced with invented results.

Device/Codemagic acceptance: verify Donate at iOS 26; client root/subroutes at
390, 640, 768, 1024 and 1280pt, including split view and rotation; scroll every
table to its last column; wrap long torrent names; apply both sort directions;
select/filter/select-all; rescan/delete success and failure; delete the final
torrent; switch active torrents during a refresh; open a library torrent and
confirm player/miniplayer continuity.
