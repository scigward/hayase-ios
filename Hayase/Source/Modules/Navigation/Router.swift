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
        if route == currentRoute {
            notify(route, kind: .replace)
            return
        }
        history.push(route, hostTabIndex: resolvedHostTabIndex(for: route, explicit: hostTabIndex))
        notify(route, kind: .push)
    }

    func replace(_ route: Route, hostTabIndex: Int? = nil) {
        history.replace(route, hostTabIndex: resolvedHostTabIndex(for: route, explicit: hostTabIndex))
        notify(route, kind: .replace)
    }

    func sync(_ route: Route, hostTabIndex: Int? = nil) {
        guard route != currentRoute else { return }
        history.replace(route, hostTabIndex: resolvedHostTabIndex(for: route, explicit: hostTabIndex))
        notify(route, kind: .sync)
    }

    func cacheAnimeItem(_ item: AnimeItem) {
        animePayloads[item.id] = item
    }

    func cachedAnimeItem(for id: Int) -> AnimeItem? {
        animePayloads[id]
    }

    func navigateToAnime(_ item: AnimeItem, hostTabIndex: Int? = nil) {
        cacheAnimeItem(item)
        navigate(.anime(id: item.id), hostTabIndex: hostTabIndex)
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
        guard let entry = history.back() else { return false }
        notify(entry.route, kind: .back)
        return true
    }

    @discardableResult
    func forward() -> Bool {
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
        explicit ?? route.tabIndex ?? currentHostTabIndex ?? currentRoute.tabIndex
    }

    private func notify(_ route: Route, kind: NavigationKind) {
        observers.values.forEach { $0(route, kind) }
    }
}
