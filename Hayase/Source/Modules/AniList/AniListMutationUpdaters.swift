//
//  AniListMutationUpdaters.swift
//  Hayase
//
//  AniList mutation cache fanout helpers.
//  Mirrors: graphcache updates in src/lib/modules/anilist/urql-client.ts.
//

import Foundation

enum AniListMutationUpdaters {
    static func applyFavourite(mediaID: Int, isFavourite: Bool) {
        AniListViewerState.shared.applyFavourite(isFavourite, for: mediaID)
        AniListClient.shared.updateFavouriteState(mediaID: mediaID, isFavourite: isFavourite)
    }

    static func applyMediaListEntry(mediaID: Int, entry: AnimeItem.MediaListEntry?) {
        AniListViewerState.shared.applyEntry(entry, for: mediaID)
        AniListClient.shared.updateMediaListEntry(mediaID: mediaID, entry: entry)
    }

    static func applyViewerUpdate(_ viewer: TrackerViewer) {
        TrackerAccountManager.shared.setViewer(viewer, for: .anilist)
    }
}
