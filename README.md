# TheAnimeTool
This tool is currently in slow development.

This is early experimental app only for learning at this moment. Will be rebuilt in the near future.

## Introduction
A convenient tool that uses anilist API  and nyaa tracker for iOS anime watching.

<img src="Previews/preview_main.png" alt="alt text" width="400"><img src="Previews/preview_search_anime.png" alt="alt text" width="400">
<img src="Previews/preview_torrent_list.png" alt="alt text" width="400"><img src="Previews/preview_video_list.png" alt="alt text" width="400">
<img src="Previews/preview_video_playing.png" alt="alt text" width="400">

## Hayase UI Porting Progress — ~70%

The table below tracks how much of the [Hayase](https://github.com/scigward/interface) web UI has been ported to the iOS native app.

| Hayase UI component / route | Status | iOS equivalent | Notes |
|---|---|---|---|
| `ui/cards/small.svelte` (poster card) | ✅ ~95% | `AnimeCollectionViewCell` | Matching cover art, score badge, status |
| `ui/cards/skeleton.svelte` (loading shimmer) | ✅ ~90% | `SkeletonPosterCell` | Gradient shimmer on both banner and poster rows |
| `ui/cards/episode.svelte` (episode card) | ✅ ~85% | `EpisodeCell` | Thumbnail, title, overview, runtime, airdate |
| `ui/banner/full-banner.svelte` (hero banner) | ✅ ~90% | `FeaturedBannerCell` | 15-s auto-rotate, dot indicators, cover+title overlay |
| `/app/home` (home page sections) | ✅ ~85% | `BrowseAnimeViewController` | 7 sections: Popular This Season, Trending, All Time Popular, Romance, Action, Adventure, Fantasy |
| `/app/search` (search + filters) | ✅ ~80% | `SearchViewController` | Genre/format/status/sort filter chips, infinite scroll |
| `/app/schedule` (weekly schedule) | ✅ ~90% | `ScheduleViewController` | 7-day chip picker, AniList airingSchedules |
| `/app/anime/[id]` (detail layout) | ✅ ~80% | `AnimeDetailViewController` | Banner, cover, badges, genres, synopsis, Find Torrents, Share, AniList link |
| `/app/anime/[id]` (episodes tab) | ✅ ~85% | `EpisodeCell` in table section | Thumbnail, title, overview, runtime via ani.zip |
| `/app/anime/[id]` (relations tab) | ✅ ~80% | `HorizontalCardsCell` + `RelationCardCell` | Horizontal scroll, relation type badges |
| `/app/anime/[id]` (characters tab) | ✅ ~80% | `HorizontalCardsCell` + `CharacterCardCell` | Horizontal scroll, role label |
| `/app/settings` (settings page) | ✅ ~70% | `SettingsViewController` | 6 grouped sections with toggles and navigation |
| `ui/torrentclient/overview.svelte` | 🟡 ~40% | `DownloadsViewController` | Has progress bar; missing speed/ETA/peers overlay |
| `ui/torrentclient/files/` | 🟡 ~45% | `VideoListViewController` | File list present; missing file priority controls |
| `/app/player` (video player) | 🟡 ~60% | `PlayerViewController` | Native player; missing Hayase overlay controls |
| `ui/profile/` | ❌ 0% | — | Not yet started |
| `/app/w2g` (Watch2Gether) | ❌ 0% | — | Not applicable for iOS MVP |
| `/app/chat` | ❌ 0% | — | Not applicable for iOS MVP |

> **Last updated:** 2026-02-22. Percentage increases with each Hayase UI porting commit.

## TODO
0. Rebuild modules & relationships
1. User torrent storage
2. Universal media player integration
3. Update UI UX
