//
//  Router.swift
//  Hayase
//
//  Mirrors: src/routes/+layout.svelte, src/routes/app/anime/[id]/+layout.ts, src/routes/app/anime/[id]/thread/[threadId]/+layout.ts
//

import Foundation

// MARK: - Router

final class Router {
    static let shared = Router(initialRoute: .home)
    static let AnimeNavigationFailedNotification = "AnimeNavigationFailedNotification"
    static let AnimeNavigationWillLoadNotification = "AnimeNavigationWillLoadNotification"
    static let ThreadNavigationFailedNotification = "ThreadNavigationFailedNotification"
    static let ThreadNavigationWillLoadNotification = "ThreadNavigationWillLoadNotification"

    enum NavigationKind {
        case push
        case replace
        case back
        case forward
        case sync
    }

    struct NavigationOptions {
        var noScroll = false
    }

    /// `error(500, err)` of a `+layout.ts` whose load failed: the page the route shows in place of itself.
    struct RouteError {
        let status: Int
        let message: String
    }

    typealias Observer = (_ route: Route, _ kind: NavigationKind, _ options: NavigationOptions) -> Void

    private let history: History
    private var observers: [UUID: Observer] = [:]
    private var animePayloads: [Int: AnimeItem] = [:]
    private var routeReadyAnimePayloadIDs: Set<Int> = []
    private var loadedAnimeRouteIDs: Set<Int> = []
    private var pendingAnimeNavigationID: UUID?
    private var pendingThreadNavigationID: UUID?
    private var threadTitles: [Int: String] = [:]
    private var threadPayloads: [Int: AniListThread] = [:]
    private var loadedThreadRouteIDs: Set<Int> = []
    private var playerPayload: VideoPlayerViewController?
    private var routeErrors: [String: RouteError] = [:]

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

    func navigate(_ route: Route, hostTabIndex: Int? = nil, noScroll: Bool = false) {
        pendingAnimeNavigationID = nil
        pendingThreadNavigationID = nil
        if route == currentRoute {
            notify(route, kind: .replace, options: NavigationOptions(noScroll: noScroll))
            return
        }
        history.push(route, hostTabIndex: resolvedHostTabIndex(for: route, explicit: hostTabIndex))
        notify(route, kind: .push, options: NavigationOptions(noScroll: noScroll))
    }

    func replace(_ route: Route, hostTabIndex: Int? = nil, noScroll: Bool = false) {
        pendingAnimeNavigationID = nil
        pendingThreadNavigationID = nil
        history.replace(route, hostTabIndex: resolvedHostTabIndex(for: route, explicit: hostTabIndex))
        notify(route, kind: .replace, options: NavigationOptions(noScroll: noScroll))
    }

    @discardableResult
    func navigate(path: String, hostTabIndex: Int? = nil, noScroll: Bool = false) -> Bool {
        guard let route = Route(path: path) else { return false }
        navigate(route, hostTabIndex: hostTabIndex, noScroll: noScroll)
        return true
    }

    @discardableResult
    func replace(path: String, hostTabIndex: Int? = nil, noScroll: Bool = false) -> Bool {
        guard let route = Route(path: path) else { return false }
        replace(route, hostTabIndex: hostTabIndex, noScroll: noScroll)
        return true
    }

    /// `replaceState(location.href, { search })`: the entry the page is on remembers its state,
    /// and nothing navigates.
    func remember(_ route: Route) {
        guard case .search = currentRoute, case .search = route else { return }
        history.replace(route, hostTabIndex: history.current.hostTabIndex)
    }

    func sync(_ route: Route, hostTabIndex: Int? = nil) {
        pendingAnimeNavigationID = nil
        pendingThreadNavigationID = nil
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

    /// True once, right after `navigateToAnime` has already run the route's load.
    func takeLoadedAnimeRoute(_ id: Int) -> Bool {
        loadedAnimeRouteIDs.remove(id) != nil
    }

    var previousRoute: Route? {
        history.canGoBack ? history.entries[history.currentIndex - 1].route : nil
    }

    var nextRoute: Route? {
        history.canGoForward ? history.entries[history.currentIndex + 1].route : nil
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

        // Match SvelteKit's /app/anime/[id] load: do not render the anime
        // route from a partial card/search payload. Keep the current route on
        // screen until the route-ready IDMedia equivalent is available.
        let requestID = UUID()
        let sourceRoute = currentRoute
        pendingAnimeNavigationID = requestID
        NotificationCenter.default.post(name: NSNotification.Name(Router.AnimeNavigationWillLoadNotification), object: nil)
        AnimeRouteLoader.load(id: item.id) { [weak self] result in
            guard let self,
                  self.pendingAnimeNavigationID == requestID,
                  self.currentRoute == sourceRoute else { return }
            switch result {
            case .success(let media):
                self.pendingAnimeNavigationID = nil
                self.cacheAnimeItem(media)
                self.loadedAnimeRouteIDs.insert(media.id)
                self.navigate(.anime(id: media.id), hostTabIndex: hostTabIndex)
            case .failure(let error):
                self.pendingAnimeNavigationID = nil
                NSLog("[Router] Anime route preload failed: %@", error.description)
                // SvelteKit goes to the page all the same and shows its error page there
                let route = Route.anime(id: item.id)
                self.routeErrors[route.path] = RouteError(status: 500, message: error.description)
                self.navigate(route, hostTabIndex: hostTabIndex)
            }
        }
    }

    func navigateToAnimeThread(animeID: Int, threadID: Int, title: String?, hostTabIndex: Int? = nil) {
        if let title { threadTitles[threadID] = title }

        let requestID = UUID()
        let sourceRoute = currentRoute
        pendingThreadNavigationID = requestID
        NotificationCenter.default.post(name: NSNotification.Name(Router.ThreadNavigationWillLoadNotification), object: nil)
        AniListForumClient.shared.threadResult(threadID: threadID) { [weak self] result in
            guard let self,
                  self.pendingThreadNavigationID == requestID,
                  self.currentRoute == sourceRoute else { return }
            switch result {
            case .success(let thread):
                guard let thread else {
                    self.pendingThreadNavigationID = nil
                    NotificationCenter.default.post(name: NSNotification.Name(Router.ThreadNavigationFailedNotification),
                                                    object: AniListRequestError.emptyData as NSError)
                    return
                }
                self.pendingThreadNavigationID = nil
                self.threadPayloads[threadID] = thread
                self.loadedThreadRouteIDs.insert(threadID)
                self.navigate(.animeThread(animeID: animeID, threadID: threadID), hostTabIndex: hostTabIndex)
            case .failure(let error):
                self.pendingThreadNavigationID = nil
                // the thread route's `+layout.ts` throws, and its error page takes the place of the route
                let route = Route.animeThread(animeID: animeID, threadID: threadID)
                self.routeErrors[route.path] = RouteError(status: 500, message: error.description)
                self.navigate(route, hostTabIndex: hostTabIndex)
            }
        }
    }

    /// The error the load of `route` ended with, once: the page that is shown instead of the route.
    func takeRouteError(for route: Route) -> RouteError? {
        routeErrors.removeValue(forKey: route.path)
    }

    func cacheThread(_ thread: AniListThread) {
        threadPayloads[thread.id] = thread
    }

    func cachedThread(for id: Int) -> AniListThread? {
        threadPayloads[id]
    }

    func takeLoadedThreadRoute(_ id: Int) -> Bool {
        loadedThreadRouteIDs.remove(id) != nil
    }

    func cachedThreadTitle(for id: Int) -> String? {
        threadTitles[id] ?? threadPayloads[id]?.title
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
        pendingThreadNavigationID = nil
        guard let entry = history.back() else { return false }
        notify(entry.route, kind: .back)
        return true
    }

    @discardableResult
    func forward() -> Bool {
        pendingAnimeNavigationID = nil
        pendingThreadNavigationID = nil
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

    private func notify(_ route: Route, kind: NavigationKind, options: NavigationOptions = NavigationOptions()) {
        if Settings.debugLevel == "*" || Settings.debugLevel == "ui:*" {
            NSLog("[ui:router] %@ (%@)", route.path, String(describing: kind))
        }
        observers.values.forEach { $0(route, kind, options) }
    }
}
