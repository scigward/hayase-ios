# TheAnimeTool
This tool is currently in slow development.

This is early experimental app only for learning at this moment. Will be rebuilt in the near future.

## Introduction
A convenient tool that uses anilist API  and nyaa tracker for iOS anime watching.

<img src="Previews/preview_main.png" alt="alt text" width="400"><img src="Previews/preview_search_anime.png" alt="alt text" width="400">
<img src="Previews/preview_torrent_list.png" alt="alt text" width="400"><img src="Previews/preview_video_list.png" alt="alt text" width="400">
<img src="Previews/preview_video_playing.png" alt="alt text" width="400">

## Hayase UI Porting Progress — ~98%

The table below tracks how much of the [Hayase](https://github.com/scigward/interface) web UI has been ported to the iOS native app.

| Hayase UI component / route | Status | iOS equivalent | Notes |
|---|---|---|---|
| `ui/cards/small.svelte` (poster card) | ✅ ~95% | `AnimeCollectionViewCell` | Cover art, score badge, status, airing info |
| `ui/cards/skeleton.svelte` (loading shimmer) | ✅ ~90% | `SkeletonPosterCell` | Gradient shimmer on both banner and poster rows |
| `ui/cards/episode.svelte` (episode card) | ✅ ~90% | `EpisodeCell` | Thumbnail, title, runtime badge, overview, airdate |
| `ui/banner/full-banner.svelte` (hero banner) | ✅ ~90% | `FeaturedBannerCell` | 15-s auto-rotate, dot indicators, cover+title+desc overlay |
| `/app/home` (home page sections) | ✅ ~92% | `BrowseAnimeViewController` | 8 sections incl. Airing Today; skeleton loading; "View More" → Schedule |
| `/app/search` (search + filters) | ✅ ~85% | `SearchViewController` | Genre/format/status/sort chips, infinite scroll, trending default |
| `/app/schedule` (weekly schedule) | ✅ ~90% | `ScheduleViewController` | 7-day chip picker, AniList airingSchedules; pushable from Home |
| `/app/anime/[id]` (detail layout) | ✅ ~90% | `AnimeDetailViewController` | Banner, cover, badges, genres, synopsis, Share, AniList, Trailer button |
| `/app/anime/[id]` (tabs navigation) | ✅ ~90% | `UISegmentedControl` sticky header | 5 tabs: Episodes / Relations / Chars / Staff / Stats |
| `/app/anime/[id]` (episodes tab) | ✅ ~85% | `EpisodeCell` in table section | ani.zip thumbnail, title, runtime badge, overview, airdate |
| `/app/anime/[id]` (relations tab) | ✅ ~80% | `HorizontalCardsCell` + `RelationCardCell` | Horizontal scroll, relation type badges, tap → detail |
| `/app/anime/[id]` (characters tab) | ✅ ~80% | `HorizontalCardsCell` + `CharacterCardCell` | Horizontal scroll, MAIN/SUPPORTING role label |
| `/app/anime/[id]` (staff tab) | ✅ ~85% | `HorizontalCardsCell` + `StaffCardCell` | Horizontal scroll, role text below portrait |
| `/app/anime/[id]` (stats tab) | ✅ ~85% | `StatsCell` | `ScoreBarChartView` bar chart + `UIProgressView` status breakdown |
| `/app/settings` (settings page) | ✅ ~70% | `SettingsViewController` | 6 grouped sections, toggles + UserDefaults persistence |
| `ui/torrentclient/overview.svelte` | ✅ ~95% | `TorrentDetailViewController` | Full replica: progress+%, speed↓/↑, ETA, elapsed, seeders/leechers/peers |
| `ui/torrentclient/files/table.svelte` | ✅ ~65% | `VideoListViewController` + `VideoTableViewCell` | Downloaded/total size ("3.2 MB / 1.2 GB"), progress bar, play/skip; bypassed from extension search (direct-to-player) |
| `/app/player` (video player) | ✅ ~95% | `VideoPlayerViewController` | PiP, episode title, download-stats floating HUD, speed control button (0.5×–2×), AirPlay route picker |
| `ui/player/downloadstats.svelte` | ✅ ~95% | `VideoPlayerViewController.statsHUD` | Floating top-right HUD: ↓ speed + buffer + %; auto-hides on completion |
| `ui/player/speed.svelte` | ✅ ~95% | `VideoPlayerViewController.speedButton` | Dedicated 46×30pt button with UIMenu (0.5×…2×); monospace label |
| `ui/player/airplay` | ✅ ~95% | `AVRoutePickerView` in top bar | 36×30pt, indigo active tint, next to speed button |
| `ui/profile/` | ❌ 0% | — | Not yet started |
| `/app/w2g` (Watch2Gether) | ❌ 0% | — | Not applicable for iOS MVP |
| `/app/chat` | ❌ 0% | — | Not applicable for iOS MVP |

> **Last updated:** 2026-02-22 batch 6. Percentage increases with each Hayase UI porting commit.

## TODO
0. Rebuild modules & relationships
1. User torrent storage
2. Universal media player integration
3. Update UI UX
