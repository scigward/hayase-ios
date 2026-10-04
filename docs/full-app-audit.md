# Full app audit: Swift app against the interface

Date: 2026-10-04. Swift app: `cd5b64c` on `codex/webtorrent-backend-switch` (269 files, 77,354 lines in `Hayase/Source`, plus the 9 files of `CoreDataService`). Interface: `cde83e26` (`interface/src`, the source of truth).

This is a list and a record, nothing was fixed or added while it was written. Five kinds of finding are listed:

1. [Missing features](#1-missing-features): something the interface does that the Swift app does not do at all.
2. [Mismatches with the interface](#2-mismatches-with-the-interface): it exists, but behaves or looks different. This section also holds the [architecture conformance](#architecture-conformance) review against the rules in `.github/agents/my-agent.agent.md`.
3. [Swift-specific bugs and risks](#3-swift-specific-bugs-and-risks): problems that come from how the Swift/iOS side is built, not from the interface.
4. [Dead code](#4-dead-code)
5. [Duplicated code](#5-duplicated-code)

Appendices: [A. features that are absent on purpose](#appendix-a-features-the-interface-has-for-desktop-and-android-only), [B. what became of the earlier audit documents](#appendix-b-status-of-the-earlier-audit-documents), [C. coverage and limits](#appendix-c-coverage-and-limits).

## How to read an entry

- **Severity**: *High* = a feature users expect does not work or the device misbehaves; *Medium* = a visible difference or a robustness gap; *Low* = small, cosmetic or only reachable in uncommon situations. Every entry counts, whatever its size.
- **Confidence**: *Confirmed* = the code on both sides was read and the claim checked with a search of the whole source; *Likely* = follows from the code but depends on timing or a device; *Needs device* = a platform rule that cannot be checked without running the app.
- Interface paths are relative to `interface/src`, Swift paths to `Hayase/Source` unless they start with a repository folder.
- A difference that a code comment already explains as intended is listed in [Appendix B](#documented-deviations-that-stay), not as a defect.

## Summary

| Section | Entries | High | Medium | Low |
| --- | ---: | ---: | ---: | ---: |
| 1. Missing features | 14 | 4 | 7 | 3 |
| 2. Mismatches (14 differences, 5 architecture entries) | 19 | 0 | 8 | 11 |
| 3. Swift-specific | 17 | 1 | 7 | 9 |
| 4. Dead code | 12 | n/a | n/a | n/a |
| 5. Duplicated code | 14 | n/a | n/a | n/a |

The ones with the biggest effect on a user:

- `MF-01`/`MF-02` links do nothing: extension install links, Watch Together invites and anime links cannot open the app on the right page.
- `MF-03` playback cannot be seen or controlled from the lock screen, Control Centre or headphones.
- `MF-04` subtitle files that come with the torrent are never loaded.
- `SB-01` the screen is allowed to lock while a video plays.
- `MF-06`/`MF-07` extensions need the network at every launch, and downloaded episodes do not appear in the torrent search.

## Status of the missing features (after the work of 2026-10-04)

The entries of section 1 below stay as they were written. This is what became of them. Before each one was
done it was checked against what the interface enables on iOS (`SUPPORTS.isIOS` / `isMobile`).

| Entry | State |
| --- | --- |
| MF-01 links | Done: `hayase://anime/<id>`, `w2g/<code>`, `schedule`, `debug`, `extensions/install/<url>` (or `?url=`) and the same paths on hayase.watch / hayase.app are handled (`AppDelegate`, `Modules/Navigation/DeepLink.swift`); a link that arrives before the app has its pages waits for them. Universal links are handled when the associated-domains entitlement is there; it is not added, because a build that is signed again by whoever installs it cannot carry it. |
| MF-02 install prompt | Done: `Components/UI/Extensions/ExtensionInstallPrompt.swift`, reached by the links above. The dialog scrolls as a whole where the interface scrolls only its list. |
| MF-03 lock screen | Done: `Components/UI/Player/MediaSession.swift` (Now Playing and remote commands). |
| MF-04 sidecar subtitles | Done: `Components/UI/Player/Subtitles.swift` (subtitle files and fonts of the torrent). |
| MF-05 subtitle extensions | Done: `ExtensionService.subtitlesQuery`, loaded by `Subtitles`. |
| MF-06 extension code | Done: the code is kept in `Application Support/Extensions` and started from there; when it does not load that way (or none is saved yet) the extension is imported from its address as before. `update()` now waits for the first load, as `storage.update` does (this also settles `SB-06`). |
| MF-07 local results | Done: the library entries of the media and episode are results of the extension `local`. |
| MF-08 identifiers | Done for text (magnet, 40-digit hash, `.torrent` address) and for a `.torrent` file dropped on the dialog. A `.torrent` file pasted from the clipboard is not handled: a text field takes no file. |
| MF-09 in-player chat | Not applicable on iOS: the Messages button is in the bottom control row, which `player.svelte` does not render on iOS (`!SUPPORTS.isIOS`) or in the minimal UI. |
| MF-10 AniSkip | Done: `Components/UI/Player/Chapters.swift` mirrors `chapters.ts` (whole chapters, first-occurrence auto-skip from AnimeThemes, the patterns, `skip()`). AniSkip is asked when the file has no chapters and is not Matroska, the container whose chapters the interface reads itself. |
| MF-11 themes | Not done: kept out of scope as decided earlier. |
| MF-12 debug ribbon | Done: `Components/UI/Menubar/Menubar.swift`. |
| MF-13 licence and error pages | Done: the licence is a page (`Route.license`, text bundled in `Resources/License/LICENSE.txt`: the licence of the interface and of the third-party code in this app) and a failed anime or thread load shows the error page. `Route.debug` was added with it, so `debug` is a route too. |
| MF-14 game controller | Done, not run on a device: `Modules/Gamepad.swift` mirrors `gamepad.ts` (A is Enter, B and Menu are Escape, the D-pad and the left stick are the arrows with the same repeat and stick thresholds; read each frame while the app is active), and `Modules/Navigation/Navigate.swift` mirrors `navigate.ts` (`inputType`, the spatial arrow navigation with its scoring and slow-down on repeat, focus that scrolls the element to the middle, Enter as a click, the `[data-input='dpad'] *:focus` tint). Where the app differs on purpose: a key goes up the responder chain and the first responder with a key command for it takes it (a DOM event reaches every listener unless one stops it); the focus is the app's own `activeElement`, since UIKit's focus engine is not moved by a controller; what counts as an element is decided by type (controls, editable text views, rows that the table or collection delegate selects, and views that opt in with `onDPadClick`, which is `use:click`), so the tap-gesture labels of the player, the terms links of the setup and the hover preview card are not elements; a touch or the pointer ends D-pad focus (a click on the page blurs it in the browser); a hardware keyboard's arrows still go only to the key commands that take them, as before, there being no window-level listener to fall back to. The player's arrows, the seek bar's keys, the Close item of the combobox and the controls that come back on `navigate` follow `$inputType` as the interface does. |

---

## 1. Missing features

### MF-01 — The `hayase://` scheme is registered but nothing handles it · High · Confirmed
- Swift: `Resources/Info.plist` declares `CFBundleURLTypes` with the scheme `hayase`. There is no `application(_:open:options:)`, no scene delegate and no `onOpenURL` (searched `Hayase`). The only user of the scheme is `ASWebAuthenticationSession` for the AniList, MAL and Simkl log-ins.
- Interface: `routes/+layout.svelte` and `routes/app/+layout.svelte` react to `native.navigate({ target, value })` with the targets `extensions` (open the install prompt for `?url=`), `schedule`, `anime`, `w2g` and `debug`. The app itself generates `https://hayase.watch/anime/<id>` (Share button) and `https://hayase.watch/w2g/<code>` (Watch Together invite).
- Effect: an extension install link, a Watch Together invite, an anime link and a `hayase://` link all do nothing when opened. Universal links are not set up either (no associated-domains entitlement; the project has no `.entitlements` file).

### MF-02 — No extension install prompt · High · Confirmed
- Interface: `lib/components/ui/extensions/ExtensionInstallPrompt.svelte` and the route `routes/app/extensions/install/[...url]`. It fetches the manifest of a link, validates it, lists the new extensions with a source viewer each, marks the "Already Installed" ones and installs with "Install (n)", Cancel and Close.
- Swift: no counterpart. Extensions can only be added by pasting a manifest URL in Settings → Extensions (or on the setup page). `Route` has no install case.

### MF-03 — No lock screen, Control Centre or remote-control integration · High · Confirmed
- Interface `ui/player/player.svelte` calls `native.setMediaSession`, `setPositionState`, `setPlayBackState` and `setActionHandler` for play, pause, seekto, seekbackward, seekforward, previoustrack, nexttrack and enterpictureinpicture.
- Swift: nothing uses `MPNowPlayingInfoCenter` or `MPRemoteCommandCenter` (searched `Hayase`). `UIBackgroundModes` has `audio` and the session category is `.playback`, so sound continues in the background, but title, artwork, position and the buttons of the lock screen, Control Centre, AirPods and car systems are missing.

### MF-04 — Subtitle (and font) files shipped inside the torrent are never loaded · High · Confirmed
- Interface `ui/player/subtitles.ts`: the non-video files of the torrent (`otherFiles`) are filtered with `subRx` (`srt`, `vtt`, `ass`, `ssa`, `sub`, `txt`). With one subtitle file it is loaded; with several, only those whose name contains the video's name. Font files of the torrent are given to the renderer as well.
- Swift: `MPVWrapper.load(url:with:externalSubtitles:)` has the plumbing (`pendingExternalSubtitles`, then `sub-add` on `MPV_EVENT_FILE_LOADED`), but its only caller, `VideoPlayerViewController.loadVideoURL`, never passes `externalSubtitles`, and `TorrentBatchResolver.ItemResolution` does not carry the non-video files. Sidecar subtitles and fonts of a release are ignored; only tracks inside the video container and "Add Subtitle File" work.

### MF-05 — Subtitle extensions are never queried · Medium · Confirmed
- Interface `modules/extensions/extensions.ts` `subtitlesQuery`: every enabled extension of type `subtitle` is asked for `{ url, language }[]` (10 s timeout, errors as toasts) and the files are loaded as extra tracks by `subtitles.ts`.
- Swift: the type exists in `ExtensionModels.swift` (a comment) but there is no query for it (searched `Modules/Extensions` for "subtitle"). A subtitle extension can be installed and enabled, and nothing happens.

### MF-06 — Extension code is not kept on the device · Medium · Confirmed
- Interface `modules/extensions/storage.ts`: `CodeManager.downloadScripts` saves each extension's code (`idb-keyval` `set(id, code)`); `initiate()` starts every worker from that cache (`getMany`). Extensions work offline and start without a request; new code arrives only through `update()` when the version changes.
- Swift `ExtensionService.swift`: the file header says the code is kept in `Library/Application Support/Extensions/{id}.js`, but nothing writes it. `ExtensionWorker.load(extensionURL:)` does `import('<esm.sh url>')` inside a `WKWebView` at every launch (`initiate`).
- Effect: with no connection, or with esm.sh down, no extension loads ("Extension failed to initialise" on the first search). Code that changes upstream under the same `gh:`/`npm:` link runs at the next launch without a version change or an update step, where the interface only runs code it saved when installing or updating.

### MF-07 — Downloaded episodes are not added to the torrent search results · Medium · Confirmed
- Interface `extensions.ts` `torrentResults` adds a task for `native.library()`: every library entry with `mediaID === media.id && episode === episode` becomes a result (`accuracy: 'medium'`, extension `local`, no seeders) next to the extension results. It works offline.
- Swift `ExtensionService.search(query:)` only asks the extension workers. `WebTorrentDownloaded` only marks and ranks results that an extension also returned; a downloaded episode that no extension lists (or with no connection) cannot be found from the search dialog and has to be opened from the Torrent Client library.

### MF-08 — Pasting an info-hash or `.torrent` link, or dropping a `.torrent` file, in the search dialog · Medium · Confirmed
- Interface `SearchModal.svelte`: `torrentRx = /(^magnet:){1}|(^[A-F\d]{8,40}$){1}|(.*\.torrent$){1}/i` is tested on the filter text, on pasted text and on dropped text; a dropped or pasted `.torrent` file (`application/x-bittorrent`) is read and played with `server.playIdentifier`.
- Swift `ExtensionSearchViewController.filterChanged` only recognises text starting with `magnet:`. Bare hashes and `.torrent` URLs are used as a text filter, and there is no paste or drop handling for torrent files (no `UIDropInteraction`/`UIPasteConfiguration` in the file). For a magnet the `TorrentResult` is built with `hash: text`, so the whole magnet URI is stored in `torrentHashString` instead of an info-hash (*Likely* effect: the entity lookup by hash and the "downloaded" mark never match it).

### MF-09 — No Watch Together chat panel in the player · Medium · Confirmed
- Interface `ui/player/player.svelte`: with an active room (`$w2globby`) the controls show a Messages button and `W2GChatPanel` (`ui/chat`) beside the video (not in the mini player).
- Swift: no "chat" reference at all under `Components/UI/Player`. The room has its own chat in the W2G page, but not while watching.

### MF-10 — No AniSkip fallback and no first-occurrence auto-skip · Medium · Confirmed
- Interface `ui/player/chapters.ts`: with no usable chapters it asks `api.aniskip.com` for opening and ending ranges; `getFirstOccurences` (AnimeThemes) marks one chapter per type as `autoskippable` (Opening/Intro and Ending/Outro/Credits, 60–120 s).
- Swift `VideoPlayerViewController.updateSkipChapterButton`: uses only chapters from MPV, and approximates auto-skip with `Settings.playerSkip && episodeNumber != 1`. Files without chapters never show the Skip button (searched `Hayase` for "aniskip": none). The chapter-name patterns are also narrower, see `MM-05`.

### MF-11 — Themes · Medium · Confirmed, known
- Interface: eight themes plus custom colours (`settings.theme`, `customThemeColors` applied as CSS variables in `routes/+layout.svelte`) and `--sys-accent` from `native.accentColor()`.
- Swift: stored (`SettingsFileService.extraKeys`) and previewed (`SettingsThemePreviewPalette`) but never applied: `UIColor.HayaseTheme` is the fixed default theme. Documented as out of scope in `docs/settings-parity-review.md`.

### MF-12 — No "Debug Mode!" ribbon · Low · Confirmed
- Interface `ui/menubar/menubar.svelte` (outside the desktop-only branch): while the debug level setting is not empty a red diagonal "Debug Mode!" ribbon is fixed at the top left, on every platform.
- Swift: the debug level is applied (MPV log level, `Router` logging) but nothing is shown (searched for "Debug Mode").

### MF-13 — No in-app licence page and no error pages · Low · Confirmed
- Interface: `routes/app/license` (generated third-party licence list), `routes/+error.svelte` and `routes/app/+error.svelte` (a page for a failed load).
- Swift: "License Information" opens the upstream licence in Safari (documented); a failed anime load shows a toast; `Route` has no `license`, `debug`, `update`, `authorize` or error case.

### MF-14 — No game controller support · Low · Confirmed
- Interface `modules/gamepad.ts` maps a gamepad to d-pad navigation of the whole UI. Swift imports no `GameController`. (Hardware keyboards are handled in the player and in the command popover only.)

---

## 2. Mismatches with the interface

### MM-01 — The Debug page is a different page · Medium · Confirmed
- Interface `routes/app/debug/+page.svelte`: `SettingCard` rows (App and Device Info, Device Logs, Settings, Torrent Capabilities, Media Capabilities), then an audio codec support matrix (9 codecs × 11 sample rates), a video codec support matrix (16 codecs × 8 resolutions) and an Input Events panel (the latest mouse, keyboard, pointer, wheel and touch event). Its intro paragraph links to the settings page.
- Swift `Routes/App/Settings/HayaseDebugViewController.swift`: hand-built layout (24pt title, 16pt card titles, shorter text, no link), a back arrow, **two cards the interface does not have** ("Copy App and Device Info" and "Streaming Logger", the latter backed by the Swift-only `pref_showLogger`), and none of the matrices or the input events panel. The "Settings" card exports the raw `UserDefaults` domain (filtered by prefix) instead of the settings object, and redacts `pref_nzbPassword`, `pref_nzbLogin` and `pref_simklClientSecret` where the interface redacts `nzbPassword` and `nzbLogin`.
- It is also not a route: there is no `Route.debug`, so it has no history entry and `native.navigate('debug')` has nothing to open.

### MM-02 — The set of routes differs · Low · Confirmed
- `Route` (`Modules/Navigation/Route.swift`) has `home`, `search`, `schedule`, `w2g`, `chat`, `client`, `settings`, `profile`, `anime`, `animeThread`, `player`. The interface also has `/app/license` (`MF-13`), `/app/debug` (`MM-01`), `/app/extensions/install/[...url]` (`MF-02`), `/update` and the settings route `plugins` (desktop or Android only, Appendix A) and `/authorize` (the web OAuth landing page, which `ASWebAuthenticationSession` replaces).

### MM-03 — Subtitle and audio track selection is a simplified version · Medium · Confirmed
- Interface `subtitles.ts`: nothing is selected when `subtitleLanguage` is empty; one track is selected; the last chosen track (language and name, then number) is remembered from episode to episode; among the tracks of the wanted language it prefers *forced for the audio language*, then *not forced when the audio is another language*, then `default`, then the first; it falls back to English and then to the first track. Audio (`checkAudio`): the preferred language, else Japanese.
- Swift `VideoPlayerViewController.applyPreferredLanguages`: the first track whose language matches (no forced or default logic, no memory between episodes, no English or first-track fallback, a single non-matching track stays as MPV chose it), and for audio only the preferred language (no Japanese fallback).

### MM-04 — The subtitle style fonts are not bundled · Medium · Needs device
- Interface bundles Roboto Medium, Gandhi Sans, Noto Sans and the JP/KR/HK Noto faces, and switches to a CJK face by track language (`LANGUAGE_OVERRIDES`, `detectCJKLanguage`).
- Swift `MPVWrapper.configureSubtitleStyle` names `Gandhi Sans`, `Noto Sans` and `Roboto Medium` in `sub-ass-style-overrides`, but `Resources/Fonts` holds only Nunito, Geist Mono and Excalifont and no `sub-fonts-dir` is set. On a device without those faces libass substitutes another font, and there is no per-language override.

### MM-05 — Chapter-type patterns are narrower than the interface's · Low · Confirmed
- `ui/player/chapters.ts`: opening `^op(?:$|[ :\d])|opening$|^opening[ :\d]|^ncop`, ending `^ed(?:$|[ :\d])|ending$|^ending[ :\d]|^nced`.
- Swift `VideoPlayerViewController.skipType(for:)`: `^op$|opening$|^ncop|^opening ` and `^ed$|ending$|^nced|^ending `. Chapters named "OP 1", "ED2", "Opening:" or "Ending 2" are not recognised.

### MM-06 — The watch-progress model and the resume rule differ · Medium · Confirmed
- Interface `modules/watchProgress.ts`: one record per **media** (`watchProgress[mediaId] = { episode, currentTime, safeduration }`), written every 10 s while playing and not buffering; on load, `loadAnimeProgress` resumes at `max(currentTime − 5, 0)` whenever the saved episode is the one being played.
- Swift `Modules/WatchProgressService.swift`: one record per **video path** in a `UserDefaults` dictionary under `nyais_watchProgress` (the whole dictionary is rewritten on every save and never pruned); saved at most every 5 s; `restoreProgress` resumes only when the entry is in progress (5 %–95 %) and later than 5 s, and seeks to the exact saved time (no 5 s rewind). A finished episode starts from the beginning where the interface resumes near its end. Because the key is the path the backend served, a changed path falls back to the AniList id and episode lookup.

### MM-07 — The search dialog formats sizes and dates differently · Low · Confirmed
- `ExtensionSearchViewController.swift` has private copies of two helpers. `fastPrettyBytes` prints `0 B` as "0.0 B" (`utils.ts`: `num + ' B'`) and leaves a trailing ".0" for values near a whole number ("2.0 GB" for 2.01 GB, where `Number(x.toFixed(1))` gives "2 GB"). `sinceDate` uses Apple's `RelativeDateTimeFormatter`, which answers in the device language with Apple's own unit boundaries, where `utils.ts since` is `Intl.RelativeTimeFormat('en')` over fixed ranges with `Math.round` of the delta. The correct versions already exist: `TorrentFormat.fastPrettyBytes` and `AniListUtil.since` (see `DU-08`).

### MM-08 — The episode field of the search dialog cannot be 0 · Low · Confirmed
- Interface: `<Input type='number' min='0' max='65536' bind:value={$searchStore.episode}>`. Swift: stepper buttons and `max(1, …)` on edit, and an upper bound of the media's episode count on increment, so episode 0 (a prologue or special) cannot be searched.

### MM-09 — `TorrentBatchResolver.resolveSeason` has no `|| 1` on episode counts · Low · Confirmed
- `ui/player/resolver.ts` uses `episodes(rootMedia) || 1` and `episodes(media) || 1`. Swift uses `AniListUtil.episodes(for:)` directly, so a media with an unknown count (0) shifts the season offsets by one against the interface. Swift also added a `visited` guard against relation loops, which the interface does not have.

### MM-10 — Screenshot has no toast and no way to save · Low · Confirmed, documented
- Interface `ui/player/util.ts screenshot`: copies the PNG, shows "Saved screenshot to clipboard" with a Download action, and on failure shows a toast and downloads. Swift copies, gives a haptic and a centre icon, and reports failure with an alert; the image cannot be saved as a file.

### MM-11 — Two copies of the banner backdrop gradient hard-code black · Low · Confirmed
- `components/ui/banner/banner-image.svelte` uses `hsla(from var(--background) …)`. Swift `BannerImage.BannerGradientView` follows `UIColor.HayaseTheme.background`, but `AnimeDetailBannerBackdropView.GradientView` (`Routes/App/Anime/[id]/Layout.swift`) and `SidebarBackdropGradientView` (`HayaseSidebarController.swift`) use `UIColor.black`. Invisible with the default theme, wrong once themes apply (`MF-11`).

### MM-12 — The pasted-invite pattern never matches the invite the app generates · Low · Confirmed, faithful
- `routes/app/+layout.svelte` has `w2gRx = /hayase\.watch\/\/w2g\/(.+)/` (two slashes). Swift copies it (`HayaseSidebarController.w2gPattern`, "hayase\\.watch//w2g/(.+)"). Both apps *generate* `https://hayase.watch/w2g/<code>` (one slash, `W2GClient.swift:87`), so pasting an invite into the app never opens the room. This is an upstream defect reproduced on purpose; listed because the share link and the paste handler of the same app disagree.

### MM-13 — Docs that no longer describe the code · Low · Confirmed
- `docs/error-toast-parity.md` says there are no NZB or HTTP extension queries; `ExtensionService` now has `nzbURLs` and `webSeeds`.
- `ExtensionService.swift` (header) claims extension code is stored under Application Support (see `MF-06`).
- Source headers still say `FinalProject` / `Charles Augustine` (`AppDelegate.swift`) and `NyaiS` (`SearchViewController.swift`); legacy names remain in `nyais_watchProgress`, `nyais_miniPlayerSessionState`, `com.nyais.fillerCache` and the CoreData attribute `torrentNyaaId`.

### MM-14 — Watch Together opens a "Create or join" screen the interface does not have · Medium · Confirmed
- Interface `routes/app/w2g/+page.ts`: opening Watch Together creates a lobby at once (`new W2GClient(generateRandomHexCode(8), true, last media)`) and redirects to `/app/w2g/<code>`; joining is done by opening a link to a code.
- Swift `W2GViewController.setupLandingUI`: shows a landing screen (title, "Create Lobby" button, "or join an existing lobby", a code field, "Join Lobby") until a lobby exists. It is a stand-in for the missing deep links (`MF-01`, `MM-12`), but it adds a screen, its texts and fixed colours (a blue button, `UIColor(white: 0.1)` fields) that are not in the interface.

### Architecture conformance

`.github/agents/my-agent.agent.md` requires the Swift code to keep the interface's architecture: identical folder names, identical file names, and one Swift file per interface file when the interface splits a component (its own example is the 20 files of `ui/player`). Rule 2 and 3 add: no feature added, none removed. The review below compares the layout; the entries after the tables are the findings.

#### `ui/player` (21 files and the `bunny/` folder)

| Interface file | Swift counterpart | State |
| --- | --- | --- |
| `player.svelte` | `Player/VideoPlayerViewController.swift` (3,489 lines) | renamed, holds six others |
| `wrapper.svelte` | `Player/MiniPlayerManager.swift` | renamed |
| `mediahandler.svelte` | spread over `VideoPlayerViewController`, `MiniPlayerManager`, `Modules/VideoService.swift` | merged |
| `options.svelte` | `Player/PlayerOptionsController.swift` (+ `PlayerOptionCell`, `PlayerOptionsTransition`) | renamed |
| `keybinds.svelte`, `maps.ts` | `Player/PlayerKeybindsView.swift`, `Player/PlayerKeyBindings.swift` | renamed |
| `episodesmodal.svelte` | `Player/PlayerEpisodeListViewController.swift` | renamed |
| `pip.ts` | `Player/PiPController.swift` | renamed |
| `thumbnailer.ts` | `Player/PlayerThumbnailer.swift` (+ `PlayerSeekPreviewView`) | renamed |
| `statsfornerds.svelte` | `Player/PlayerTechnicalStatsView.swift` | renamed |
| `resolver.ts` | `Modules/Torrent/TorrentBatchResolver.swift` | moved and renamed |
| `animations.svelte` | `VideoPlayerViewController.showPlayerAnimation` | merged |
| `castplayer.svelte` | `VideoPlayerViewController` (`nowCasting*`), `CastPlaylistDialog.swift`, `ExternalDisplayManager.swift` | merged |
| `chapters.ts` | `VideoPlayerViewController` (`skipType`, `updateSkipChapterButton`) | merged |
| `downloadstats.svelte` | `VideoPlayerViewController.statsHUD` | merged |
| `seekbar.svelte` | `SegmentedSeekBar`, a private class in `VideoPlayerViewController.swift` | merged |
| `subtitles.ts` | `MPVWrapper.swift` + `VideoPlayerViewController` | merged |
| `util.ts`, `index.ts` | none (inline) | merged |
| `externalplayer.svelte`, `volume.svelte`, `bunny/` | none | not applicable on iOS |
| (Swift only) | `MPVWrapper.swift`, `MPVSurfaceView.swift`, `HayasePlayerPresentation.swift`, `PlayerMetadataLoadingView.swift`, `StreamingLogger.swift` | engine and platform files |

#### Components, modules and routes

| Interface | Swift | State |
| --- | --- | --- |
| `components/SearchModal.svelte` | `Components/UI/Extensions/ExtensionSearchViewController.swift` (2,194 lines) | different folder and name |
| `components/EpisodesList.svelte` | `Routes/App/Anime/[id]/EpisodesList.swift` | different folder |
| `components/EntryEditor.svelte` | `Components/EntryEditorViewController.swift` + `EntryEditorFormView.swift` | renamed, split in two |
| `components/SettingCard.svelte`, `SettingsNav.svelte` | `Components/UI/Settings/SettingsCardView.swift`, `Components/UI/Button/HayaseNavTabButton.swift` + `SettingsNavigationView` | renamed |
| `components/Online.svelte` | `Components/UI/OnlineBar/HayaseOnlineBar.swift` | renamed |
| `components/Pagination.svelte` | `Components/UI/Forums/ThreadPaginationView.swift` | renamed |
| `components/StatusDot.svelte` | inline in `AnimeCollectionViewCell`, `ScheduleEpisodeRow` | merged |
| `ui/sidebar/{sidebar,sidebarlist,SidebarButton}.svelte` | `Sidebar/HayaseSidebarController`, `HayaseSidebarListView`, `HayaseSidebarButton` | renamed (`Hayase` prefix) |
| `ui/button/{bookmark,favorite,play,progress-button,transition}.svelte` | inline in `Anime/[id]/Layout.swift` and `InterfaceProgressButton` (private, in the player file) | merged |
| `ui/cards/{episode,skeleton,skeletontrace,trace}.svelte` | inline in `AnimeCollectionViewCell`, `Skeleton.swift`, `SearchViewController` | merged |
| `ui/cards/recommendation.svelte` | `Routes/App/Anime/[id]/Recommendation.swift` | different folder |
| `ui/relations/*`, `ui/forums/Threads.svelte` | `Routes/App/Anime/[id]/Relations.swift`, `Threads.swift` | different folder |
| `ui/forums/{Comment,Comments,Write}.svelte`, `ui/markdown` | `Forums/ThreadCommentView`, `ThreadDetailViewController`, `ThreadWriteViewController`, `AniListRichTextView` | renamed |
| `ui/dialog/*`, `ui/drawer/*`, `ui/sheet/*` | `Settings/SettingsDialogViewController.swift`, `ScheduleDayViewController`, `PlayerEpisodeListViewController` | merged into users |
| `ui/sonner/*` | `Components/UI/AppErrorToast.swift`, `ErrorToastCardView.swift` | renamed |
| `ui/irc/*`, `routes/app/chat` | `Routes/App/Chat/HayaseChatViewController.swift` | renamed |
| `routes/app/w2g/[id]` | `Routes/App/W2G/W2GViewController.swift` | no `[id]` folder |
| `routes/app/client/{files,library,overview,peers,trackers}` + `ui/torrentclient/*` | `Components/UI/TorrentClient/DownloadsViewController.swift` (2,204 lines) | different folder, one file for five pages |
| `routes/app/debug` | `Routes/App/Settings/HayaseDebugViewController.swift` | different folder |
| `routes/app/settings/{accounts,app,changelog,client,extensions,interface,player}` | `SettingsSectionCatalog.swift` + `SettingsViewController+Content.swift` / `+Actions.swift` | one catalog instead of one page per route |
| `routes/app/anime/[id]/+layout.svelte` | `Routes/App/Anime/[id]/Layout.swift` (2,874 lines) | same folder, also holds the play, bookmark, favourite and share buttons, the follower row and the genre/tag rows |
| `modules/watchProgress.ts` | `Modules/WatchProgressService.swift` | renamed |
| `modules/{anilist,auth,extensions,irc,w2g,torrent,settings,anizip,animethemes,geoip}` | `Modules/{AniList,Auth,Extensions,IRC,W2G,Torrent,Settings,AniZip,AnimeThemes,GeoIP}` | same |
| `lib/utils.ts` | none: helpers are spread over `AniListUtil`, `TorrentFormat`, private functions | see `DU-08` |
| `modules/{navigate,idle,online,target,update,gamepad,chromecast,native}.ts` | `Modules/Navigation/*` (SvelteKit router stand-in, and `Navigate.swift` for `navigate.ts`), `Modules/Gamepad.swift`, `HayaseOnlineBar`, none for the rest | partly absent |

#### AR-01 — Seven interface player files are inside one 3,489-line Swift file · Medium · Confirmed
`animations`, `castplayer`, `chapters`, `downloadstats`, `seekbar`, `subtitles` and the `mediahandler` logic live in `VideoPlayerViewController.swift` together with three private classes (`SegmentedSeekBar`, `InterfaceSpinnerView`, `InterfaceProgressButton`). The agent file names the player folder as the example of what must stay split.

#### AR-02 — Other large merged files · Medium · Confirmed
`Anime/[id]/Layout.swift` (2,874), `DownloadsViewController.swift` (2,204), `ExtensionSearchViewController.swift` (2,194), `SearchViewController.swift` (1,682), `EpisodesList.swift` (1,590), `HayaseSidebarController.swift` (1,356), `MiniPlayerManager.swift` (1,121), `MPVWrapper.swift` (1,061), `Profile.swift` (1,023), `W2GViewController.swift` (1,008). The largest interface file is `player.svelte` (1,040 lines); the whole interface source is 29,449 lines against 77,354 in Swift.

#### AR-03 — Names and folders differ for about 40 components · Low · Confirmed
Rows marked "renamed", "different folder" or "merged" above. Swift files cite the interface file they mirror in their header, which is how the table was built.

#### AR-04 — The torrent session model is the old CoreData one · Medium · Confirmed
The interface plays through `server.playHash` / `server.last` / `server.active`. Swift persists a `Torrents` + `Animes` + `Videos` CoreData graph (`CoreDataService`) and builds the player from it (`ExtensionSearchViewController.startDownload`, `VideoService`, `VideoPlayerViewController.videoEntity`). Several consequences are listed elsewhere: stored file URLs (`SB-15`), watch progress keyed by path (`MM-06`), a magnet text in the hash field (`MF-08`), unused attributes and the whole `Users` entity (`DC-04`). Nothing in the interface corresponds to this layer.

#### AR-05 — Swift-only additions · Low · Confirmed
Features the interface does not have: the Debug page's "Copy App and Device Info" and "Streaming Logger" cards and `pref_showLogger` (`MM-01`), `StreamingLogger.swift`, the Watch Together landing screen (`MM-14`), a Keychain for credentials, the bridge token. The last two are security measures documented elsewhere and are not defects.

---

## 3. Swift-specific bugs and risks

### SB-01 — The screen can lock during playback · High · Confirmed
Nothing sets `UIApplication.shared.isIdleTimerDisabled` (searched `Hayase` and `CoreDataService` for "idletimer"). A web `<video>` keeps the screen awake by itself; MPV rendering into an `AVSampleBufferDisplayLayer` does not. After the user's Auto-Lock time without touches, the screen dims and locks while the episode keeps playing sound (background audio mode).

### SB-02 — `UIScreen.main` is used for layout in 19 files · Medium · Confirmed
`UIScreen.main.bounds` is the whole screen, not the window. On iPad in Split View, Slide Over or Stage Manager the window is smaller, so everything derived from it is wrong. 30 uses: `Anime/[id]/Layout.swift` (5), `HayaseStripeLayer` (2), `SelectButton` (2), `ExternalDisplayManager` (2), `Profile` (2), `HomePage` (2), `SearchViewController` (2), `HayaseDebugViewController` (2), and one each in `HayaseContentBlurView`, `FullBanner+Artwork`, `PreviewCard`, `ExtensionSearchViewController`, `ExtensionsViewController`, `ThreadDetailViewController`, `ThreadPaginationView`, `LoadIn`, `EpisodesList`, `Recommendation`, `SplashLogoView`.

### SB-03 — The viewport width is measured three ways · Medium · Confirmed
`SettingsLayoutView` and `SetupLayout` use `window.rootViewController.view.bounds.width` (the scaled logical width); `AnimeDetailViewController.viewportWidth` uses `window.bounds.width ?? UIScreen.main.bounds.width` (physical, unscaled); search, W2G and chat use their own bounds. With `uiScale` ≠ 1 the Tailwind breakpoints (`sm`/`md`/`lg`/`xl`) are asked of different widths on different pages.

### SB-04 — The storyboard references a class that does not exist and holds unreachable scenes · Medium · Confirmed
`Resources/Base.lproj/Main.storyboard` scene `tor-vc-001` has `customClass="TorrentListViewController"`, declared nowhere. Its segue leads to the scene `vid-vc-001` (`VideoListViewController`), which nothing else instantiates (`DC-02`). The whole storyboard is still loaded at launch (`UIMainStoryboardFile`) to obtain the six-tab controller, and loaded again by `rebuildInterfaceAfterSettingsReset` (and by `finishSetup` / `installSidebarShell` when the first copy is gone).

### SB-05 — A failed WebTorrent start is final for the whole run · Medium · Confirmed
`WebTorrentBackend.finishStart(.failure)` sets `startState = .failed(error)` and `ensureStarted` returns that error from then on. `waitForBridge` gives up after 80 tries × 0.25 s = 20 s, so a slow first start (cold device, large cache) fails permanently even if the bridge answers at second 21; every later play, library read and settings call fails immediately until the app is relaunched. (Only `exited` errors say "restart the app"; a timeout does not.)

### SB-06 — The extension update and the first load race · Medium · Likely
`ExtensionService.init` starts `Task { await update() }` and `readyTask = Task { await initiate(configs: Array(configs.values)) }` together. `update()` does not wait for `readyTask` (the interface's `update` awaits `this.ready`). `initiate` captured the *old* configs, so when it finishes after an update it can replace the freshly loaded worker with one loaded from the old code URL while `configs` already says the new version; and two `loadWorker` calls for one id can both create a `WKWebView`, the second assignment dropping the first without `destroy()` (a leaked web view).

### SB-07 — Nothing handles "nickname already in use" in the IRC client · Medium · Likely
`IRCClient.handleLine` handles `CAP`, `PING`, `001`, `353`, `366`, `JOIN`, `PART`, `QUIT`, `KICK`, `PRIVMSG` and nothing else (no `433`, `432`, `436`, `ERROR`, `465`). After a dropped connection the reconnect (4 s) can meet the server still holding the old session's nick; registration never completes and the chat stays connecting until the retry budget is spent. The IRC library of the interface registers a nick-in-use handler. Depends on the server's timing, so *Likely*.

### SB-08 — Tracker tokens survive an uninstall · Low · Needs device
`Keychain.set` stores tokens with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Keychain items outlive the app's deletion on iOS while `UserDefaults` does not, so a reinstall (or a device passed on) starts the setup again but is still signed in to AniList/MAL/Kitsu/Simkl. `Keychain.removeAll` runs only on the in-app reset.

### SB-09 — Casting needs local-network settings the project does not declare · Medium · Needs device
Chromecast and DLNA discovery run in the Node bridge (mDNS and SSDP, `listCurrentDisplays` in `webtorrent-bridge.js`). On iOS 14+ local-network access needs `NSLocalNetworkUsageDescription`, Bonjour browsing needs `NSBonjourServices`, and raw multicast sockets need the `com.apple.developer.networking.multicast` entitlement. `Info.plist` has none of the keys and the repository has no `.entitlements` file, so the "Cast" list may stay empty on a device. The Swift cast UI itself (`nowCasting*`, `CastPlaylistDialog`) is complete.

### SB-10 — `Info.plist` has a legacy capability and ineffective status-bar keys · Low · Confirmed
`UIRequiredDeviceCapabilities` is `armv7` (iOS 16 devices are arm64). `UIViewControllerBasedStatusBarAppearance` is `false` and `UIStatusBarHidden` is `true`, so the `prefersStatusBarHidden` / `childForStatusBarHidden` overrides (`VideoPlayerViewController`, `PlayerOptionsController`, `PlayerEpisodeListViewController`, `HayaseSidebarController`, `HayaseInterfaceNavigationController`, `HayaseProgressBarWindow`) and the `setNeedsStatusBarAppearanceUpdate()` calls in the player have no effect: the status bar is hidden everywhere, always.

### SB-11 — Logging in release builds prints private data · Low · Confirmed
21 `print(` and 39 `NSLog(` calls in production code. Examples: `WebTorrentBackend.playTorrent` prints the magnet link or `.torrent` URL; `ExtensionService.fetchAniZipData` prints ids per search; `AniListAuth` and `TorrentBatchResolver` log request failures.

### SB-12 — Timing hacks · Low · Confirmed
11 `asyncAfter(deadline: .now() + 0.x)` used as sequencing: `VideoPlayerViewController` (5), `ScheduleTooltip` (2), `SelectButton`, `Peers/Cells/Flags`, `RouteScrollRestoration`, and the 0.25 s poll in `WebTorrentBackend.waitForBridge`. Each is a guess about when a view or process is ready.

### SB-13 — 94 implicitly unwrapped properties in 20 files · Low · Confirmed
Most in `ExtensionSearchViewController` (28), `SearchViewController` (17), `ExtensionsViewController` (8, dead), `Anime/[id]/Layout.swift` (7), `DownloadsViewController` (5), `FullBanner` (4), `EpisodesList` (4). They are set in `viewDidLoad`; an access before it (a notification, a callback from a presented controller) crashes. No instance of such a crash was found; the pattern is the risk.

### SB-14 — The error poll runs for the whole process and is never stopped · Low · Confirmed
`WebTorrentBackend.errorTimer` is created once after the first successful start and never invalidated; `WebTorrentPlayRequest` holds its backend `unowned`. Both are safe only because the backend is a singleton.

### SB-15 — Stored file URLs may not survive a relaunch · Low · Likely
`VideoService.InsertVideosFromWebTorrentFiles` persists each file's `url`/`lan` (served by the backend's local HTTP server) in the `Videos` entity as `videoPath`, and `WatchProgressService` keys progress by that string. If the backend's address changes between launches, old paths are dead and progress is found only by the AniList id and episode fallback.

### SB-16 — Deprecated window lookups · Low · Confirmed
`UIApplication.shared.windows.first` in `VideoPlayerViewController`, `AccountCardView+Authentication` and `HayaseInterfaceScale`; the app has no scene manifest (`UIApplicationSceneManifest` is absent, the window belongs to the app delegate), so iPadOS multi-window and Stage Manager window placement are unavailable.

### SB-17 — One force cast and 72 `fatalError` initialisers · Low · Confirmed
`Img/Logo.swift:40` `layer as! CAShapeLayer`. The `fatalError` calls are the `required init?(coder:)` stubs of programmatic views and cannot be reached outside storyboards, so only the cast is listed as a risk. (No `try!`, no force-unwrapped `URL(string:)` was found.)

---

## 4. Dead code

Found with a whole-source name scan (a declaration whose name is used nowhere else), followed by a manual check of every item; delegate callbacks, `@objc` members, protocol requirements and Codable fields were excluded as false positives.

### DC-01 — `Components/UI/Extensions/ExtensionsViewController.swift` (798 lines) · Confirmed
`ExtensionsViewController`, `ExtensionCell` and `RepoCell` are referenced only inside the file. It is the earlier extensions screen, replaced by `SettingsExtensionsView` / `SettingsExtensionCardView`. Only `BadgeFlowView` (about 110 lines at the end) is still used, by `SettingsExtensionCardView`. Its `setupTableView` also duplicates `ExtensionSearchViewController`'s (`DU-14`).

### DC-02 — `Components/UI/TorrentClient/VideoListViewController.swift` (503 lines) · Confirmed
`VideoListViewController` and `VideoTableViewCell` are reachable only through the storyboard scene `vid-vc-001`, whose only incoming segue comes from the scene with the missing class (`SB-04`). `VideoService.downloadedBytesForFileIndex`, `totalBytesForFileIndex` and `CheckIsDoNotDownloadForFileIndex` are used only by it.

### DC-03 — `Components/UI/Sidebar/HayaseInterfaceNavigationController.swift` · Confirmed
The class is declared and referenced nowhere (not in the storyboard either), together with its `UINavigationControllerDelegate` and gesture code.

### DC-04 — CoreData leftovers · Confirmed
Entity `Users` in `Model.xcdatamodel` (no class, never fetched). Attributes never read or written by code: `Animes.animeFlagTemp`, `animeNextEps`, `animeNextEpsTime`, `animePopularity`, `animeOrder`; `Torrents.torrentDownloads`, `torrentLocalPath`, `torrentNyaaId`, `torrentOrder`; `Videos.videoDownloadPercent`.

### DC-05 — `MPVWrapper` methods nobody calls · Confirmed
`isPausedState`, `reloadCurrentItem`, `applyPreset`, `syncTimebase` (empty body), `getSpeed`, `getCurrentSubtitleTrack`, `getCurrentAudioTrack`, `setSubtitlePosition`, `setSubtitleScale`, `setSubtitleMarginY`, `setSubtitleAlignX`, `setSubtitleAlignY`, `setSubtitleFontSize`; and the `pendingExternalSubtitles` / `sub-add` branch, which is never filled (`MF-04`).

### DC-06 — AniList module leftovers · Confirmed
`AniListClient.decodeAniListMedia` (private), `AiringScheduleResponse` and `AiringSchedulePagedResponse` with their nested `Airing*` / `PP*` types (`AniListTypes.swift`), `AnimeRelationGraph.visibleRelations`, `HomeSectionContentState.showsPlaceholderItems`, `PageQuery.currentValue`, and the decoded field `AniListMedia.popularity`.

### DC-07 — Other modules · Confirmed
`AniZipService.episodesCached`, `mappingsByKitsuId`, `mappingsByMalId`; `Anitomy.allElements`; `TrackerSync.simklID`; `DagreGraph.sinks`, `DagreGraph.neighbors`, the enum cases `bottomToTop` and `rightToLeft` of `DagreLayout`; `MatroskaMetadataService.clearCache`; `WebTorrentBridgeStatus.hudMessage`; `TorrentBatchResolver.selectByAnime`; the unused local `pkg` in `ExtensionService.jsurl`.

### DC-08 — Views and controls · Confirmed
`HayaseStripeLayer.makeImage` and `seamlessTileSize`; `FullBannerProgress.setColor`; `Hover.dragDidOccur`; `ExtensionSearchViewController.isSearching`, `progressTimer`, `bottomStack`; `ThreadDetailViewController.finishVisibleCommentLikeAttempt`; `VideoPlayerViewController.activeCastDisplayName`; `HayaseSidebarListView.setSelectedIndex`; `HayaseSidebarRoute.isNativeRoute`; `AnimeDetailViewController`'s `installHover` and `updateGenresAndTrailer` (`Layout.swift`).

### DC-09 — Status-bar overrides · Confirmed
Ineffective because of the `Info.plist` keys (`SB-10`).

### DC-10 — Files in the repository root that nothing uses · Confirmed
`package/` and `uint8-util-2.2.6.tgz` (an unpacked npm package and its tarball; no script, workflow or config refers to `uint8-util` outside it), `Previews/*.png` (five screenshots of the old UI, such as `preview_torrent_list.png` and `preview_video_list.png`, referenced nowhere), `Tests/Fixtures/` (a JSON fixture and a README with a one-off Node snippet, no test target or runner).

### DC-11 — Four build definitions for one build · Confirmed
`.github/workflows/build-ipa.yml`, `.github/workflows/export-final-source.yml`, `codemagic.yaml` and `bitrise.yml` each repeat the XcodeGen, WebTorrent bundle and GeoIP steps. `bitrise.yml` has no other reference in the repository.

### DC-12 — Comments that describe code that is gone · Confirmed
`ExtensionService.swift` header (Application Support storage that does not exist, `MF-06`), `VideoService.lastError` ("Forwarded to VideoListViewController", dead since `DC-02`), `ExtensionSearchViewController.swift:153` ("skip VideoListViewController"), and the legacy project names listed in `MM-13`.

---

## 5. Duplicated code

Found by comparing normalised function bodies (identical, 7 lines or more) and same-named functions in different files (80 % or more similar). Line numbers are those of the audited commit.

| ID | Where | What |
| --- | --- | --- |
| DU-01 | `Button/SelectButton.swift:202` and `Checkbox/Checkbox.swift:87` | `updatePressScale`, identical (18 lines) |
| DU-02 | `Anime/[id]/Layout.swift:32` (`AnimeDetailBannerBackdropView.GradientView`), `Sidebar/HayaseSidebarController.swift:1212` (`SidebarBackdropGradientView`), `Banner/BannerImage.swift` (`BannerGradientView`) | the same radial-gradient `draw` and `setCompact`; the first two identical and hard-coded black, the third theme-aware (`MM-11`) |
| DU-03 | `DownloadsViewController.swift:1772`, `VideoListViewController.swift:448` (dead), `W2GViewController.swift:976`, `MiniPlayerManager.swift:750` | `topViewController`, identical in three, near-identical in the fourth |
| DU-04 | `DownloadsViewController.swift:1759`, `W2GViewController.swift:963` | `presentEpisodeSearch` / `presentW2GEpisodeSearch`, identical (10 lines) |
| DU-05 | `ExtensionSearchViewController.swift:1446–2121`, `PlayerEpisodeListViewController.swift:545–583`, `PlayerOptionsTransition.swift` | the custom presentation transition (`presentationController`, `animationController`, `presentationTransitionWillBegin`), 83–100 % similar |
| DU-06 | `Peers/PeersTable.swift`, `Trackers/TrackersTable.swift`, `FileEntryTableCell.swift`, `LibraryColumnCell.swift` | `makeValueLabel`, `hover`, `updateColumnWidths`, identical or 97 % |
| DU-07 | `ChatMessageToastCardView.swift:107–134` and `ErrorToastCardView.swift:152–183` | `startTimer`, `hover`, `pan` (93–100 %) |
| DU-08 | `ExtensionSearchViewController.swift:1991` (`fastPrettyBytes`) and `:2013` (`sinceDate`) against `TorrentFormat.fastPrettyBytes` and `AniListUtil.since`; time text in `VideoPlayerViewController.swift:2349`, `MiniPlayerManager.swift:630`, `PlayerOptionsController.swift:509` | the private copies print differently (`MM-07`); three copies of the `h:mm:ss` formatter (the interface has one `toTS`) |
| DU-09 | `Input/Input.swift:160` and `Textarea/Textarea.swift:115` | `updateRing` (98 %) |
| DU-10 | `SettingsLayoutView.swift:42–51` and `Setup/SetupStepView.swift:86–97` | `keyboardChanged`, `setContent` (93–94 %) |
| DU-11 | `Auth/KitsuSync.swift:93–100` and `Auth/MALSync.swift:103–110` | `get`, `refresh` (96 % / 81 %) |
| DU-12 | `Chat/HayaseChatViewController.swift` and `W2G/W2GViewController.swift` | `viewWillTransition` (100 %), `tableView` (97 %), `configureTabBarItem` (85 %) |
| DU-13 | `Anime/[id]/Layout.swift:2418` and `Home/HomePage.swift:254`; `AnimeCollectionViewCell.swift:298` and `Skeleton/Skeleton.swift:174`; `HayaseStripeLayer.swift:272` and `TrailerTooltip.swift:188`; `AniZip/AniZipTypes.swift:198` and `:271` | `usesDesktopSidebar` (92 %), `requestInterfaceMountAnimation` (86 %), `didMoveToWindow` (99 %), `decodeStringMap` (identical, same file) |
| DU-14 | `ExtensionSearchViewController.swift:673` and `ExtensionsViewController.swift:166` (dead) | `setupTableView` (88 %) |

Other repetition that is not function-for-function:
- Settings keys as string literals instead of `Settings.Keys`: `"pref_torrentSpeed"` in 6 files, `"pref_torrentLocation"` in 6, `"pref_maxConns"` in 5, `"pref_disableDHT"` and `"pref_nzbPort"` in 4 (`SettingsFileService`, `TorrentBackendSettings`, `SettingsSectionCatalog`, `SettingsViewController+Actions`, `+Content`, `SetupNetworkPage`, `SetupStoragePage`). `schedule-on-list` and `pref_showLogger` are literals used only where they are.
- The defaults of settings exist twice: `Settings.Defaults` and the `fallback:` column of `SettingsFileService.fields` (the header of `Settings.swift` already notes that they "agree today, but nothing enforced" it).

---

## Appendix A. Features the interface has for desktop and Android only

Their absence on iOS is expected and not a finding: `hideToTray`, Discord rich presence (`showDetailsInRPC`), `angle`, external player (`enableExternal`, `playerPath`, `externalplayer.svelte`), `transparency`, profiling, `openUIDevtools` / `openTorrentDevtools`, plugins (`pluginList`, `pluginPopup`, `pluginImport`, `pluginDelete`, the `settings/plugins` route), `updateToNewEndpoint`, the update page and `native.updateAndRestart`, window controls and `Menubar`, DoH settings, `playerCustom` (MediaBunny playback), `androidStorageType`, `unsafeUseInternalALAPI`, volume UI on mobile (the interface uses system volume), `native.minimise` / `maximise` / `close` / `focus`. The "Navigation Buttons" toggle (`showNavigation`) exists in both apps but its buttons only exist in the desktop menubar, so in both it does nothing on iOS.

## Appendix B. Status of the earlier audit documents

### `docs/webtorrent-parity-audit.md` (2026-10-01)
All 15 numbered findings appear to be addressed in the current code (checked by finding the code, not by running it):

| # | Finding | Where it is now |
| ---: | --- | --- |
| 1 | Active deletion keeps the library record | library refetched after delete (`DownloadsViewController` "as `server.updateLibrary()` does") |
| 2 | Terminal actions never release the session | `WebTorrentPlayRequest.release()`, `WebTorrentBackend.stopSession`, `VideoService.releaseWebTorrentSession` |
| 3 | Cancellation does not cancel backend work | `WebTorrentPlayRequest.cancel()` + `cancelPlay` |
| 4 | Unknown hash returns another torrent | `torrentByHash` in the bridge no longer falls back |
| 5 | Foreground not tied to ownership | `foregroundHash()` reads `client.sessions` |
| 6 | Cached torrents missing in ranking | `WebTorrentDownloaded` and the `downloadedDidChange` observer in the search dialog |
| 7 | Settings sent on every play | `appliedSettings` comparison in `syncSettings` |
| 8 | NZB zero values lost | `clampedInt` minimum 0 and `hasNZBServer` |
| 9 | Web seeds need an extra AniList request | `WebTorrentWebSeeds.add(media:)` |
| 10 | Failed settings update ignored | `syncSettings` failure stops the play |
| 11 | Storage preflight | `usableDirectory` checks `R_OK` and `W_OK` in the bridge |
| 12 | Cast errors not observable | `status.cast[host].error` shown in `nowCastingErrorLabel` |
| 13 | Polled events dropped | `status(afterEventID:)` cursor |
| 14 | Polling cadence | per-store intervals in `DownloadsViewController` |
| 15 | Statistics semantics | `_peersLength` and connected counts split in the bridge |

Not run on a device; the hazards the document lists as "needs a device" still stand.

### Other documents
- `docs/error-toast-parity.md` is outdated (`MM-13`).
- `docs/settings-parity-review.md`: the remaining gaps it lists (themes, dialog blur, toast icons and swipe, source-code font, extension ordering by sorted keys, donate heart timing, in-app licence page) are still open and are not repeated above except `MF-11` and `MF-13`.
- `docs/player-visual-parity-review.md`: modifier-only key bindings and held-Space fast-forward, MPV stats counters, the screenshot toast (`MM-10`) remain open.
- `docs/setup-parity-review.md`, `docs/splash-parity-review.md`, `docs/home-parity-review.md`, `docs/torrent-client-parity-review.md`: no contradiction found by this audit.

### Documented deviations that stay
Listed so the next audit does not report them again:
- Plain `http` extension URLs are refused (`ExtensionService.swift` header).
- The IRC client is a reduced port: minimal CAP, no SASL, no client-side ping, no ISUPPORT parsing, no case folding; the kick handler removes the kicker and the guest nick is `undefined_Guest-…`, both on purpose, as upstream does (`IRCClient.swift` header).
- The 1080p subtitle render height default (`Settings.Defaults.subtitleRenderHeight`) against the interface's 720 on mobile.
- `TorrentBatchResolver` guards against relation loops (`visited`); the interface does not.
- Optional NZB registration does not block peer streaming (`webtorrent-parity-audit.md`, platform adaptations).
- `TorrentBackendSettings` uses the iOS sandbox paths (`Caches` or `Documents`).

## Appendix C. Coverage and limits

| Area | How it was checked |
| --- | --- |
| App shell, launch, routes, deep links, background modes | `AppDelegate`, `Info.plist`, `project.yml`, `Route` read in full against `routes/+layout.svelte`, `routes/app/+layout.svelte`, `menubar.svelte`; the four CI files compared by the steps they contain |
| Player (options, subtitles, chapters, resolver, cast, mini player, progress, completion, tracking) | `player.svelte`, `options.svelte`, `subtitles.ts`, `chapters.ts`, `resolver.ts`, `mediahandler.svelte`, `wrapper.svelte`, `castplayer.svelte`, `externalplayer.svelte`, `seekbar.svelte`, `pip.ts`, `downloadstats.svelte`, `episodesmodal.svelte`, `animations.svelte`, `util.ts` read; against Swift `PlayerOptionsController`, track selection, resume, completion, `TorrentBatchResolver`, `MPVWrapper` style code. Not read: `maps.ts`, `thumbnailer.ts`, `statsfornerds.svelte`, `volume.svelte`, `bunny/`, and `keybinds.svelte` beyond its binding logic (the earlier player reviews cover their look). `VideoPlayerViewController` was read in the parts those touch, not line by line |
| Extensions (storage, worker use, queries, dedupe, local results, subtitles) | `storage.ts`, `extensions.ts` against `ExtensionService.swift` (read in full) and the `ExtensionWorker` loading path |
| Search dialog | `SearchModal.svelte` against `ExtensionSearchViewController` by feature (paste, drop, ranking, errors, skeleton, auto-select) |
| Auth and tracking | `auth/client.ts`, `util.ts`, `local.ts` against `AniListAuth.watch` / `setInitialState`; `kitsu.ts`, `mal.ts`, `simkl.ts` not compared line by line (the Swift files cite them and share `TrackerSync`) |
| IRC | `irc/index.ts`, `connections.ts` against `IRCClient.swift` |
| Anime page, schedule, themes, forums | layout, page, schedule, themes and threads read against the Swift files by feature; spoiler, share, trailer, tags, links, filler, week layout all present |
| Settings, home, search, setup, splash, torrent client | rely on the earlier reviews (Appendix B) plus a check of `defaults.ts` against `SettingsFileService.fields` |
| W2G | `w2g/index.ts` and the room page against `W2GClient` / `W2GViewController`: trackers, 30 s re-announce, 2 s tolerance, texts, share text and message limit match, the landing screen is `MM-14`; the P2P wire protocol (p2pt, tracker messages, WebRTC) was not re-read |
| Static scans | dead names (whole source, hand-verified), identical and near-identical functions, risk patterns (`try!`, `as!`, `fatalError`, `[0]`, force-unwrapped URLs, observers, timers, `UIScreen.main`, `print`/`NSLog`, IUOs, `asyncAfter`) |

Limits: Windows host with no Xcode and no device. Nothing was built or run; every *Needs device* and *Likely* entry is a reading of the code. The interface source was read at `cde83e26`; a later interface revision can add differences.
