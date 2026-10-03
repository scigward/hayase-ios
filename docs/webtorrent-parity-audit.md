# WebTorrent parity audit

Date: 2026-10-01. Scope: Swift's **WebTorrent** path.

This is an investigation and prioritized work list. No application behavior was changed by this audit. Findings distinguish source-confirmed differences, platform adaptations, shared upstream limitations, and behavior that still needs an iOS reproduction. This is not a claim that every network, filesystem, or player scenario has been runtime-tested.

## Reference snapshots and evidence

- Swift app: `4531125583cacd0c54b4ac8698ba7d1817b459cf`, matching the fetched `codex/webtorrent-backend-switch` remote at audit time.
- [interface](https://github.com/hayase-app/interface/tree/cde83e26b84d632494c446a45053851c93b593d2): `cde83e26b84d632494c446a45053851c93b593d2`.
- [torrent-client](https://github.com/hayase-app/torrent-client/tree/aac548a05ef919e9ab4eb1f20d96ba3fb8a03274): `aac548a05ef919e9ab4eb1f20d96ba3fb8a03274`.
- [Electron host](https://github.com/hayase-app/electron/tree/dcd4fda1808807cdfb957ce65cd6010a09ce385e): `dcd4fda1808807cdfb957ce65cd6010a09ce385e`. Its lockfile pins the same torrent-client revision above.
- [native API schema](https://github.com/hayase-app/native/tree/0c73fc92b341f0a24c6c57c1bf8c9c0dcd2bbdb4): `0c73fc92b341f0a24c6c57c1bf8c9c0dcd2bbdb4`, pinned by interface.

Important baseline caveat: these upstream snapshots themselves contain API skew. Interface's `modules/torrent/client.ts` calls `native.playTorrent`, but its pinned native schema and the Electron preload expose `addTorrent`. Interface's browser fallback supplies dummy `playTorrent` data. That fallback is **not** a real backend reference. This report compares frontend intent with the real torrent-client implementation; it does not assume that checking out these repositories together reproduces the deployed website. The backend revision inside the user's installed IPA was not independently recovered.

Native file links below are relative to this report. Upstream links are revision-pinned.

## Why files can remain on disk

Upstream has **no time-based expiry** for downloaded files. With Persist Files disabled, it deletes the previous foreground torrent only **after a different torrent finishes initialization successfully**, provided no other session owns it and it is not a background download. With Persist Files enabled, removing that torrent from the live client preserves its files and cache record.

The rules come from torrent-client [`playTorrent` and `evictOrphan`](https://github.com/hayase-app/torrent-client/blob/aac548a05ef919e9ab4eb1f20d96ba3fb8a03274/index.ts#L162-L191), [`evictOrphan`/bitfield saving](https://github.com/hayase-app/torrent-client/blob/aac548a05ef919e9ab4eb1f20d96ba3fb8a03274/index.ts#L398-L438), and [`stopSession`](https://github.com/hayase-app/torrent-client/blob/aac548a05ef919e9ab4eb1f20d96ba3fb8a03274/index.ts#L540-L546).

| Situation | Expected upstream behavior | Swift audit result |
| --- | --- | --- |
| Play A, then successfully load different B; Persist Files off | Remove A's store and metadata if orphaned | Same upstream method is called with a stable session ID. The normal switch path is present; actual disk removal needs a device test. |
| Play another file/episode in the same torrent | Keep the batch store | Expected; not an expiry bug. |
| Persist Files on | Keep previous files and metadata | Expected; Swift uses the correct preference key/default. |
| Load B fails while A was playing | Eviction of A is not reached | Shared upstream failure-path weakness, amplified by Swift's uncancelled timeout/cancellation paths. |
| Explicitly close the Swift player | Swift destroys playback, but does not release the backend session | Confirmed integration gap; see finding 2. Ordinary page navigation must still preserve the miniplayer/session. |
| Delete the active torrent from Library | Upstream skips session-owned torrents | Swift bypasses that protection for file removal but leaves ownership/cache behind; see finding 1. |
| Kill/relaunch the app | No general stale-file sweep in the reviewed backend | Not evidence of a Swift-only TTL regression. Abrupt termination is not a reliable cleanup trigger. |

Additional distinctions:

- **Streamed Download** changes piece selection; it does not continuously delete previously watched pieces from disk.
- Library is built from `hayase-cache` metadata, not a physical directory scan. A library record, a Core Data record, and actual media bytes are different things.
- The 20/1 active/background store-cache slot values govern memory cache, not days of file retention.
- The Library's old-metadata warnings are not deletion deadlines.
- Swift's default media location is `Library/Caches/HayaseWebTorrent`; its Internal/Documents option is `Documents/HayaseWebTorrent`. Electron's default is OS temporary storage under `webtorrent`. The iOS cache directory is not an application-defined TTL and Documents is not temporary storage. This platform/path difference can affect observed longevity, but is not by itself proof that the normal switch deletion failed.
- Changing location replaces the backend metadata Store for subsequent work. Existing torrent stores keep their original paths. Returning to an old directory and cross-directory cleanup need testing; do not recursively delete arbitrary folders as a parity fix.

Sources: [native settings/path](../Hayase/Source/Modules/Torrent/Backend/TorrentBackendSettings.swift), [upstream Store](https://github.com/hayase-app/torrent-client/blob/aac548a05ef919e9ab4eb1f20d96ba3fb8a03274/filesystem/store.ts), [Electron temporary path](https://github.com/hayase-app/electron/blob/dcd4fda1808807cdfb957ce65cd6010a09ce385e/src/main/background/background.ts).

## Confirmed differences and integration gaps

Priority: **P1** correctness/data/session issues; **P2** observable functional parity; **P3** fidelity/performance. Priority is a proposed implementation order, not authorization to change code during this audit.

### 1. P1 — Active deletion removes files but can retain the library record

**Evidence:** [bridge `removeRunningTorrents` and `deleteTorrents`](../Hayase/Resources/WebTorrentBackend/webtorrent-bridge.js) removes selected running torrents with `destroyStore: true`, then calls upstream `deleteTorrents`. Upstream builds its protected hashes from `sessions.values()` and skips those hashes. The bridge never releases that session. Consequently the upstream metadata deletion for an actively owned hash is skipped even after its live files were removed.

Swift [Library deletion](../Hayase/Source/Components/UI/TorrentClient/DownloadsViewController.swift) reports success and filters local rows before a backend library refetch completes. Interface instead awaits `server.updateLibrary()` before clearing selection/resolving its promise. A surviving cache record can therefore disappear locally and return on refresh.

**Target:** choose the upstream contract deliberately: retain/protect active torrents, or explicitly stop playback/release ownership before deleting. Do not combine forced removal with stale ownership. Refetch authoritative Library before presenting the final result.

**Test:** delete the playing hash, inspect media bytes and its `hayase-cache/<hash>` record, refresh and relaunch. Also delete an inactive hash while another torrent plays; playback must remain unaffected.

Upstream: [`deleteTorrents`](https://github.com/hayase-app/torrent-client/blob/aac548a05ef919e9ab4eb1f20d96ba3fb8a03274/index.ts#L246-L297), [interface delete promise](https://github.com/hayase-app/interface/blob/cde83e26b84d632494c446a45053851c93b593d2/src/lib/components/ui/torrentclient/library/table.svelte#L134-L145).

### 2. P1 — Swift-only terminal playback actions never release WebTorrent ownership

**Evidence:** [MiniPlayerManager.close](../Hayase/Source/Components/UI/Player/MiniPlayerManager.swift) clears saved playback and calls [player teardown](../Hayase/Source/Components/UI/Player/VideoPlayerViewController.swift). Teardown stops MPV/native stream helpers, but the manager/client/bridge expose no `stopSession` RPC. [Backend selection](../Hayase/Source/Modules/Torrent/Backend/TorrentBackendManager.swift) only applies the new backend's settings; it does not release the previous WebTorrent session.

**Impact:** an apparently closed Swift playback can remain session-owned in Node. That prevents orphan eviction, can retain files, and can keep downloading/seeding while Node remains alive. Persist Files off is not enough to release that ownership.

**Qualification:** interface does not expose an equivalent explicit miniplayer-close workflow in the reviewed wrapper; Electron also does not call `stopSession` from its preload. This is a missing integration with the backend's lifecycle API for Swift's additional terminal actions, not a claim that navigating away should delete files.

**Target/test:** keep ownership across navigation/minimization; release it exactly once on a genuine stop/close/backend replacement, honoring Persist Files. Test both persist states, repeated close, reset, and backend switching.

### 3. P1 — Metadata cancellation and timeout do not cancel backend work

**Evidence:** bridge `withTimeout` races `playTorrent` against 90 seconds; its AbortController cancels only the timeout timer. Swift cancellation/restore timeout removes observers and player state, but [WebTorrentBridgeClient](../Hayase/Source/Modules/Torrent/Backend/WebTorrentBridgeClient.swift) does not expose a cancellable play/session operation. Upstream sets the session hash before awaiting initialization and evicts the old hash only after initialization succeeds.

**Impact:** metadata can complete and downloads can continue after the screen was dismissed or timed out. A failed switch can leave an earlier live torrent orphaned without running its eviction. Later retries can overlap with pending work.

**Target/test:** define cancellation, ownership rollback, and late-result suppression together. Cancel metadata loading A, start B immediately, allow A's metadata to arrive later; B must remain current and A must not leak. Network timeout and app restore timeout need the same ownership checks.

### 4. P1 — An explicit unknown hash can return another torrent's statistics

**Evidence:** bridge `torrentByHash(hash)` falls back to `activeTorrent`/first torrent if the requested hash is missing. `torrentInfo` uses that helper instead of upstream `torrentInfo`, which throws `Torrent not found` for a missing hash.

**Impact:** status, progress and webseed preflight can silently refer to the wrong torrent. Other RPCs such as peers/files still use exact upstream lookup, producing internally inconsistent snapshots.

**Target/test:** only allow fallback for an explicitly hashless status request. Request a nonexistent hash while A is running; the hash-specific info call must reject, not return A.

### 5. P2 — Bridge foreground status is not tied reliably to session ownership

**Evidence:** `observeTorrent` makes every newly added torrent active. It returns early for previously observed torrents; successful `playTorrent` does not explicitly bind `activeTorrent` to the returned hash. `deleteTorrents` unconditionally clears that pointer, even when only an unrelated torrent was deleted. Status then picks the first live torrent. Upstream supports multiple live/background torrents; interface follows `server.active.id` rather than whichever torrent was added first/last.

**Target/test:** derive foreground identity from the successful play request/session. With multiple live torrents, reuse an already loaded hash and delete an unrelated hash; status must follow the foreground session. The inactive-delete pointer reset was reproduced in a mocked bridge test; visible wrong selection requires multiple live torrents.

### 6. P2 — Cached torrents are missing from extension ranking and downloaded indication

**Evidence:** the bridge has a `cachedTorrents` RPC, but the Swift client has no corresponding consumer/shared downloaded-hash store. [ExtensionSearchViewController](../Hayase/Source/Components/UI/Extensions/ExtensionSearchViewController.swift) explicitly skips the downloaded-torrent rank. Interface populates `server.downloaded` at startup, updates it on playback/library changes, ranks cached results ahead of ordinary/low-seeder results after the low-accuracy check, and renders their downloaded indicator.

**Target/test:** use the authoritative backend cache hashes consistently in ranking and row presentation. Persist a cached result with few seeders, restart, and compare its rank/indicator and auto-selection with interface.

Upstream: [SearchModal](https://github.com/hayase-app/interface/blob/cde83e26b84d632494c446a45053851c93b593d2/src/lib/components/SearchModal.svelte#L124-L152), [client cache store](https://github.com/hayase-app/interface/blob/cde83e26b84d632494c446a45053851c93b593d2/src/lib/modules/torrent/client.ts#L75-L114).

### 7. P2 — Replaying a torrent unnecessarily destroys/recreates NZB infrastructure

**Evidence:** [WebTorrentBackend.playTorrent](../Hayase/Source/Modules/Torrent/Backend/WebTorrentBackend.swift) submits full settings before every play, even unchanged. Upstream `updateSettings` destroys/recreates its NZBManager. Interface uses a change-filtered `derivedDeep` settings subscription instead. Upstream's existing-torrent branch does not re-register the torrent with that new NZBManager.

**Impact:** extra connections/churn on every play; replaying an already-live torrent can leave the replacement NZBManager without registered wires for that torrent. Exact device/network symptoms still need reproduction.

**Target/test:** update only changed settings and handle seed-manager changes explicitly. Replay the same live hash with a working NZB server; verify webseed peers/traffic continue and unchanged settings do not reconnect the pool.

Upstream: [settings update](https://github.com/hayase-app/torrent-client/blob/aac548a05ef919e9ab4eb1f20d96ba3fb8a03274/index.ts#L105-L134), [init/reuse](https://github.com/hayase-app/torrent-client/blob/aac548a05ef919e9ab4eb1f20d96ba3fb8a03274/index.ts#L490-L529), [interface settings subscription](https://github.com/hayase-app/interface/blob/cde83e26b84d632494c446a45053851c93b593d2/src/lib/modules/settings/settings.ts#L57-L84).

### 8. P2 — NZB zero-valued disabling behavior is lost

**Evidence:** [settings catalog](../Hayase/Source/Routes/App/Settings/SettingsSectionCatalog.swift) and TorrentBackendSettings clamp NZB port/pool size to at least 1. Swift's `hasNZBServer` therefore tests only credential strings. Interface and torrent-client require all five fields to be truthy; a zero port or pool prevents NZB configuration/querying. The bridge itself permits zero, but Swift cannot pass it through.

**Target/test:** preserve the upstream disabling semantics and agree on valid ranges. Set port/pool to zero with credentials retained; no NNTP pool/query should start. Do not copy interface's invalid TCP-port upper bound of 65536.

### 9. P2 — Adding extension webseeds depends on an extra AniList request

**Evidence:** [WebTorrentWebSeeds.add](../Hayase/Source/Modules/Torrent/Backend/WebTorrentWebSeeds.swift) fetches resolver media again and silently returns if that request fails, before querying either HTTP or NZB extensions. Interface passes the media object already supplied to `_loadTorrent`; it does not impose this additional post-play AniList fetch.

**Impact:** torrent peers can work while available extension webseeds are never queried due to an unrelated AniList failure. The completed-torrent guard and seed payload fields are otherwise present.

**Target/test:** reuse resolved media where available; distinguish genuine missing media from a redundant fetch failure. With media already loaded, make AniList unavailable and compare seed extension calls.

### 10. P2 — Playback ignores a failed settings update

**Evidence:** WebTorrentBackend's pre-play `updateSettings` completion discards its Result and starts playback anyway. `applySettings` failures are only written to StreamingLogger. The bridge may reject directory creation before installing the new settings.

**Impact:** playback can proceed using old persistence/location/NZB settings while Settings displays the newly saved values. This is a confirmed native failure-path gap, not a claim that interface has a toast for every settings RPC error.

**Target/test:** retain explicit applied-versus-requested state or propagate failure; do not silently act as if the new settings succeeded. Fail the location update and verify the effective persistence/path is known to the caller.

### 11. P2 — Storage preflight checks directory creation, not access permissions

**Evidence:** TorrentBackendSettings ignores mkdir errors; bridge `usableDirectory` only attempts mkdir and can silently fall back with a warning. It does not call the upstream R_OK/W_OK `verifyDirectoryPermissions`. Electron's download selection calls that API and exposes the failure.

**Impact:** an existing but unusable directory may pass creation preflight and fail later. Fallback may not match the stored location shown in Settings. This is a filesystem-handling difference; iOS uses sandbox locations rather than Electron's arbitrary folder picker.

**Target/test:** validate effective directory access and report the actual fallback location without blocking safe recovery. Test read-only/unavailable locations in a controlled sandbox, not user directories.

### 12. P2 — Casting errors/session completion are not observable through the RPC result

**Evidence:** bridge `playDisplay` intentionally returns immediately and catches later rejection as a non-user-facing warning. Interface awaits `native.castPlay` for the cast session and displays a rejected session's error in castplayer. A short HTTP RPC cannot simply await an entire viewing session, but Swift lacks an equivalent cast-session error/completion event here.

**Target/test:** preserve the asynchronous transport adaptation while adding observable session state/error delivery. Test an unreachable receiver, rejected launch and receiver disconnect; do not show successful casting solely because the start RPC returned `{}`.

Upstream: [castplayer await/error](https://github.com/hayase-app/interface/blob/cde83e26b84d632494c446a45053851c93b593d2/src/lib/components/ui/player/castplayer.svelte#L108-L125), [Electron cast forwarding](https://github.com/hayase-app/electron/blob/dcd4fda1808807cdfb957ce65cd6010a09ce385e/src/preload/index.ts#L88-L91).

### 13. P2 — Polled error delivery can drop backend events

**Evidence:** bridge retains 40 log events but `/status` returns only the last 12. Swift polls every second, advances `lastErrorEventID` for every returned event, and displays userFacing errors. More than 12 events between successful polls can push an error out of the response before Swift sees it. Electron uses an error callback rather than this bounded status snapshot.

**Target/test:** cursor-based event retrieval or equivalent reliable delivery, retaining bounded memory and toast coalescing. Emit an error followed by more than 12 informational events before the next poll; the error should still reach Swift. Verify behavior after temporary RPC failure and background/foreground transitions.

### 14. P3 — Torrent-client polling differs substantially from interface

**Evidence:** DownloadsViewController polls every second, fetching Library and all live info/files/peers/protocol snapshots together even when their tabs are not visible; trackers refresh every 10 seconds. Interface uses subscribed stores: stats 200 ms (underpowered 3 s), files/peers/protocol 5 s (underpowered 15 s), Library/trackers 120 s. Its next poll is scheduled after completion. Swift's in-flight guard is good, but one slow grouped call delays applying the entire snapshot.

**Target/test:** equivalent per-store demand/cadence with iOS power constraints documented, rather than one broad polling loop. Count RPCs in Overview, Library, Peers and off-page; throttle one endpoint and check whether unrelated statistics continue updating.

### 15. P3 — Statistics and cached-only overview semantics differ

**Evidence:** bridge custom `statsFromTorrent` reports `peers.wires = torrent.wires.length` (connected wires), whereas upstream getStats uses `_peersLength` (discovered peer count). Bridge elapsed time is wall-clock seconds since observation; upstream elapsed is zero. It also changes missing-name/progress handling. Numeric rounding for Swift UInt64 decoding is a necessary transport adaptation, but does not explain these semantic changes.

DownloadsViewController additionally falls back to the first cached Library hash/entry without an active session, potentially labeling cached-only progress as Downloading/Seeding. Interface's live stores follow `server.active.id`; Library is separate.

**Target/test:** explicitly map discovered versus connected counts without silently renaming their meaning; separate inactive cache data from live transfer status. Compare a swarm with many discovered/few connected peers, and a restart with cached entries but no active player. Any retained elapsed-time enhancement should be documented as an intentional exception rather than claimed exact parity.

Upstream: [getStats](https://github.com/hayase-app/torrent-client/blob/aac548a05ef919e9ab4eb1f20d96ba3fb8a03274/torrent/info.ts#L21-L54), [timed frontend stores](https://github.com/hayase-app/interface/blob/cde83e26b84d632494c446a45053851c93b593d2/src/lib/modules/torrent/client.ts#L33-L72).

## Platform adaptations and shared upstream limitations — not automatic fix requests

1. **NAT/WebRTC capability gaps:** [build script](../scripts/build_webtorrent_backend.sh) replaces NAT mapping with a no-op and node-datachannel with unsupported-operation stubs. Peer streaming therefore is not network-capability-identical to Electron. Port forwarding/WebRTC-only peer tests are needed. Do not restore unsupported native addons blindly or display them as working.
2. **Build provenance risk:** the script fetches torrent-client `main` on each build and installs with `--no-frozen-lockfile`. Electron uses a pinned lockfile revision; its current torrent-client pin matches this audit, but future builds can drift without a Swift commit. Record the actual built backend/dependency versions before comparing a particular IPA. This is a reproducibility risk, not proof that today's build contains different code.
3. **Optional NZB isolation is deliberate:** bridge registration does not block peer streaming on NNTP readiness/failure, per the user's previous requirement. Upstream awaits registration. Preserve that safety exception; test successful registration and seed-manager replacement rather than reverting it for literal parity.
4. **Player engine adaptation:** Swift consumes the same backend HTTP file URLs through MPV; interface uses browser playback plus backend attachments/tracks/subtitles/chapters APIs. Those attachment RPCs are not exposed by the Swift bridge. MPV may provide equivalent embedded data independently; missing RPCs alone do not prove missing subtitles/fonts/chapters. Test embedded fonts, multiple subtitle tracks, external batch subtitles, seeks and chapter extraction.
5. **NodeMobile lifecycle:** one runtime per app process and Swift-specific startup/exit diagnostics are platform constraints, not strings to replace indiscriminately. Electron does send backend `destroy` on app exit. Its backend destroy does not explicitly stop every session with `destroyStore: true`, so clean desktop exit is not evidence of unconditional file deletion either.
6. **Shared upstream weaknesses:** no TTL/startup stale-file sweep; metadata writes/unlinks catch errors; delete/rescan use `Promise.allSettled` without reporting each failed hash; failed initialization has no session rollback; changing storage roots does not migrate old data. These can affect both apps. If changing them, distinguish an upstream robustness improvement from a parity correction.
7. **Valid differences to keep:** Keychain NZB credentials, authenticated local control RPCs, finite/unsigned numeric normalization, iOS sandbox paths, and the user's explicit 1080p subtitle-render-limit exception. Interface hides desktop DoH settings on iOS; their absence here is not a missing iOS control.
8. **Restore timing requires comparison:** interface persists the requested last torrent before loading; Swift persists a usable player/miniplayer session and clears it on explicit close or failed restore. Swift does restore WebTorrent via VideoService, so it is incorrect to claim restoration is entirely missing. Test interruption during metadata versus after successful playback separately.

## Coverage and validation boundary

Reviewed source paths: source resolution and metadata loading; stable session ownership; persist/streamed selection; disk/cache/library deletion and rescan; storage/settings updates; HTTP/NZB extension seeds; stats/peer/file/protocol/tracker RPCs; cached-result ranking; error event delivery; casting; player teardown/restore/backend selection; packaging/native-addon substitutions. Underlying tracker/DHT/PeX, HTTP range streaming and store algorithms largely remain delegated to upstream rather than reimplemented in Swift.

Four inline Node tests used **actual extracted bridge functions** and an in-memory fake client:

- Explicit missing hash returns the active torrent: reproduced.
- Deleting an inactive hash clears the foreground pointer: reproduced (status refresh stubbed).
- Active deletion removes the fake live torrent while session-protected cache survives: reproduced; the fake deletion protection was modeled directly from upstream `deleteTorrents`, not a real filesystem test.
- Timeout rejects the bridge response while the original work still completes: reproduced.

No real torrents, user files, or application settings were changed. No iOS/Xcode build, device run, live swarm, NNTP server, cast receiver or on-device disk deletion test was performed. Source confirmation is stronger than a guess, but does not establish the frequency or exact disk footprint of the user's observed issue.

## Recommended implementation order / device checklist

1. Agree on the lifecycle contract and implement findings 1–3 together: deletion, terminal-session release, cancellation/late-result handling. Do not delete files on ordinary page navigation.
2. Correct hash/foreground identity (4–5), then run A→B success/failure, same-batch switching, cancellation and unrelated deletion scenarios.
3. Restore cached-result behavior and fix seed/configuration paths (6–11), preserving optional-NZB isolation.
4. Add reliable cast/error events and match polling/stat semantics (12–15).
5. For each retention scenario, record effective `torrentPersist`, effective path, backend revision, session hash, live torrent hashes, `hayase-cache` entries and media-byte sizes **before and after**. Test Persist Files both off/on, app close/relaunch, reset and storage-location changes.
6. Complete live-peer/HTTP/NZB/cast/MPV tests on compact iPhone and regular iPad. This audit does not certify pixel-perfect UI parity of all torrent/player controls.
