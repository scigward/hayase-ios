//
//  AniListViewerState.swift
//  Hayase
//
//  Mirrors: interface client.ts `medialists` (the viewer's lists from `UserLists`, which the whole
//  interface reads a media's entry from) and the `isFavourite` graphcache keeps on every Media.
//  A card, the banner or a hover card asks this, instead of asking AniList about the one media.
//

import Foundation

final class AniListViewerState {
    static let shared = AniListViewerState()
    /// Posted on the main queue when what is read from here has changed: the interface's stores tell
    /// every card and button at once, and so does this.
    static let didChange = Notification.Name("HayaseAniListViewerStateDidChange")

    private let lock = NSLock()
    /// The viewer's entries by media id, as the last `UserLists` answer has them.
    private var entries: [Int: AnimeItem.MediaListEntry] = [:]
    /// The viewer whose lists `entries` holds; nil until they have been loaded.
    private var loadedViewerID: Int?
    /// What a mutation said since: the entry it saved, or nil for one it deleted. A mutation is newer
    /// than the lists, until the lists are loaded again.
    private var entryChanges: [Int: AnimeItem.MediaListEntry?] = [:]
    private var favourites: [Int: Bool] = [:]

    private init() {}

    /// The viewer's lists are in: a media that is not on them is not on the viewer's list.
    var areListsLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadedViewerID != nil
    }

    /// `$alMap.get(mediaId)`. `fallback` is what the caller already knows, for as long as the lists
    /// are not loaded.
    func entry(for mediaID: Int, fallback: AnimeItem.MediaListEntry?) -> AnimeItem.MediaListEntry? {
        lock.lock()
        defer { lock.unlock() }
        if let change = entryChanges[mediaID] { return change }
        return loadedViewerID == nil ? fallback : entries[mediaID]
    }

    /// `media.isFavourite`, as the last toggle left it.
    func isFavourite(for mediaID: Int, fallback: Bool?) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return favourites[mediaID] ?? fallback
    }

    /// `userlists` answered. What a mutation said stays for as long as that mutation is still waiting
    /// to go out (`keepingChanges`): the answer cannot know of it yet.
    func replaceEntries(_ newEntries: [Int: AnimeItem.MediaListEntry], viewerID: Int, keepingChanges: Bool = false) {
        lock.lock()
        entries = newEntries
        loadedViewerID = viewerID
        if !keepingChanges { entryChanges.removeAll() }
        lock.unlock()
        notifyChange()
    }

    /// The `SaveMediaListEntry` and `DeleteMediaListEntry` cache updates of urql-client.ts.
    func applyEntry(_ entry: AnimeItem.MediaListEntry?, for mediaID: Int) {
        lock.lock()
        entryChanges[mediaID] = .some(entry)
        lock.unlock()
        notifyChange()
    }

    /// The `ToggleFavourite` cache update of urql-client.ts.
    func applyFavourite(_ isFavourite: Bool, for mediaID: Int) {
        lock.lock()
        favourites[mediaID] = isFavourite
        lock.unlock()
        notifyChange()
    }

    /// An account that signs out, or another one that signs in.
    func clear() {
        lock.lock()
        entries.removeAll()
        entryChanges.removeAll()
        favourites.removeAll()
        loadedViewerID = nil
        lock.unlock()
        notifyChange()
    }

    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AniListViewerState.didChange, object: nil)
        }
    }
}

extension AnimeItem {
    /// auth/client.ts `mediaListEntry`: AniList's lists first, then kitsu, mal, simkl and the local one.
    var listEntry: MediaListEntry? {
        let state = AniListViewerState.shared
        // What the item came with is AniList's own answer, which counts for as long as AniList's lists
        // are not in; for anyone who is not signed in to AniList it can only be an older copy of
        // another tracker's entry, and that tracker is asked.
        let own = mediaListEntry != nil && !state.areListsLoaded && TrackerAccountManager.shared.isLoggedIn(.anilist)
            ? mediaListEntry : nil
        return state.entry(for: id, fallback: own) ?? TrackerAggregator.externalEntry(for: id)
    }

    /// auth/client.ts `isFavourite`: AniList's own, else Kitsu's, else the local list's.
    var isFavouriteForViewer: Bool {
        if TrackerAccountManager.shared.isLoggedIn(.anilist) {
            return AniListViewerState.shared.isFavourite(for: id, fallback: isFavourite) ?? false
        }
        return TrackerAggregator.isFavourite(mediaID: id)
    }
}
