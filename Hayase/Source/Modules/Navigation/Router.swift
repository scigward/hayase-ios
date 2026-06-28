//
//  Router.swift
//  Hayase
//
//  Small native router that uses route paths as the source of truth, mirroring
//  the interface's goto/replaceState/back/forward navigation model.
//

import Foundation

// MARK: - Router

final class Router {
    static let shared = Router(initialRoute: .home)

    enum NavigationKind {
        case push
        case replace
        case back
        case forward
        case sync
    }

    typealias Observer = (_ route: Route, _ kind: NavigationKind) -> Void

    private let history: History
    private var observers: [UUID: Observer] = [:]
    private var animePayloads: [Int: AnimeItem] = [:]
    private var routeReadyAnimePayloadIDs: Set<Int> = []
    private var pendingAnimeNavigationID: UUID?
    private var threadTitles: [Int: String] = [:]
    private var playerPayload: VideoPlayerViewController?

    private init(initialRoute: Route) {
        history = History(initialRoute: initialRoute)
    }

    var currentRoute: Route {
        history.current.route
    }

    var currentHostTabIndex: Int? {
        history.current.hostTabIndex
    }

    var canGoBack: Bool {
        history.canGoBack
    }

    var canGoForward: Bool {
        history.canGoForward
    }

    func reset(to route: Route, hostTabIndex: Int? = nil) {
        history.reset(to: route, hostTabIndex: resolvedHostTabIndex(for: route, explicit: hostTabIndex))
        notify(route, kind: .replace)
    }

    func navigate(_ route: Route, hostTabIndex: Int? = nil) {
        pendingAnimeNavigationID = nil
        if route == currentRoute {
            notify(route, kind: .replace)
            return
        }
        history.push(route, hostTabIndex: resolvedHostTabIndex(for: route, explicit: hostTabIndex))
        notify(route, kind: .push)
    }

    func replace(_ route: Route, hostTabIndex: Int? = nil) {
        pendingAnimeNavigationID = nil
        history.replace(route, hostTabIndex: resolvedHostTabIndex(for: route, explicit: hostTabIndex))
        notify(route, kind: .replace)
    }

    @discardableResult
    func navigate(path: String, hostTabIndex: Int? = nil) -> Bool {
        guard let route = Route(path: path) else { return false }
        navigate(route, hostTabIndex: hostTabIndex)
        return true
    }

    @discardableResult
    func replace(path: String, hostTabIndex: Int? = nil) -> Bool {
        guard let route = Route(path: path) else { return false }
        replace(route, hostTabIndex: hostTabIndex)
        return true
    }

    func sync(_ route: Route, hostTabIndex: Int? = nil) {
        pendingAnimeNavigationID = nil
        guard route != currentRoute else { return }
        history.replace(route, hostTabIndex: resolvedHostTabIndex(for: route, explicit: hostTabIndex))
        notify(route, kind: .sync)
    }

    func cacheAnimeItem(_ item: AnimeItem) {
        let isRouteReady = item.isRouteReadyMediaPayload
        if let existing = animePayloads[item.id] {
            let merged = existing.mergingRouteMedia(item)
            animePayloads[item.id] = merged
            if isRouteReady || merged.isRouteReadyMediaPayload {
                routeReadyAnimePayloadIDs.insert(item.id)
            }
            return
        }

        animePayloads[item.id] = item
        if isRouteReady {
            routeReadyAnimePayloadIDs.insert(item.id)
        }
    }

    func cachedAnimeItem(for id: Int) -> AnimeItem? {
        animePayloads[id]
    }

    func cachedFullAnimeItem(for id: Int) -> AnimeItem? {
        guard let item = animePayloads[id] else { return nil }
        if routeReadyAnimePayloadIDs.contains(id) || item.isRouteReadyMediaPayload {
            return item
        }
        return nil
    }

    func updateCachedAnimeItem(mediaID: Int, update: (inout AnimeItem) -> Void) {
        guard var item = animePayloads[mediaID] else { return }
        update(&item)
        animePayloads[mediaID] = item
    }

    func clearAniListViewerState() {
        pendingAnimeNavigationID = nil
        animePayloads = animePayloads.mapValues { item in
            var item = item
            item.mediaListEntry = nil
            item.isFavourite = nil
            return item
        }
    }

    func navigateToAnime(_ item: AnimeItem, hostTabIndex: Int? = nil) {
        cacheAnimeItem(item)

        if cachedFullAnimeItem(for: item.id) != nil {
            navigate(.anime(id: item.id), hostTabIndex: hostTabIndex)
            return
        }

        // Match SvelteKit's /app/anime/[id] load: do not render the anime
        // route from a partial card/search payload. Keep the current route on
        // screen until the route-ready IDMedia equivalent is available.
        let requestID = UUID()
        let sourceRoute = currentRoute
        pendingAnimeNavigationID = requestID
        AniListClient.shared.fetchResolverMediaById(item.id) { [weak self] media in
            guard let self,
                  self.pendingAnimeNavigationID == requestID,
                  self.currentRoute == sourceRoute,
                  let media else { return }
            self.pendingAnimeNavigationID = nil
            self.cacheAnimeItem(media)
            self.navigate(.anime(id: media.id), hostTabIndex: hostTabIndex)
        }
    }

    func navigateToAnimeThread(animeID: Int, threadID: Int, title: String?, hostTabIndex: Int? = nil) {
        if let title { threadTitles[threadID] = title }
        navigate(.animeThread(animeID: animeID, threadID: threadID), hostTabIndex: hostTabIndex)
    }

    func cachedThreadTitle(for id: Int) -> String? {
        threadTitles[id]
    }

    func navigateToPlayer(_ player: VideoPlayerViewController, hostTabIndex: Int? = nil) {
        playerPayload = player
        navigate(.player, hostTabIndex: hostTabIndex)
    }

    func cachedPlayer() -> VideoPlayerViewController? {
        playerPayload ?? MiniPlayerManager.shared.activePlayer
    }

    func clearCachedPlayer(_ player: VideoPlayerViewController) {
        guard playerPayload === player else { return }
        playerPayload = nil
    }

    @discardableResult
    func back() -> Bool {
        pendingAnimeNavigationID = nil
        guard let entry = history.back() else { return false }
        notify(entry.route, kind: .back)
        return true
    }

    @discardableResult
    func forward() -> Bool {
        pendingAnimeNavigationID = nil
        guard let entry = history.forward() else { return false }
        notify(entry.route, kind: .forward)
        return true
    }

    @discardableResult
    func observe(_ observer: @escaping Observer) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func resolvedHostTabIndex(for route: Route, explicit: Int?) -> Int? {
        // Real app routes own their tab. Tabless detail routes, like anime
        // pages and the player, inherit the current host tab instead.
        route.tabIndex ?? explicit ?? currentHostTabIndex ?? currentRoute.tabIndex
    }

    private func notify(_ route: Route, kind: NavigationKind) {
        observers.values.forEach { $0(route, kind) }
    }
}
