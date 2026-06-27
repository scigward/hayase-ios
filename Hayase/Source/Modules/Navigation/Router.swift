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

    private init(initialRoute: Route) {
        history = History(initialRoute: initialRoute)
    }

    var currentRoute: Route {
        history.current.route
    }

    var canGoBack: Bool {
        history.canGoBack
    }

    var canGoForward: Bool {
        history.canGoForward
    }

    func reset(to route: Route) {
        history.reset(to: route)
        notify(route, kind: .replace)
    }

    func navigate(_ route: Route) {
        if route == currentRoute {
            notify(route, kind: .replace)
            return
        }
        history.push(route)
        notify(route, kind: .push)
    }

    func replace(_ route: Route) {
        history.replace(route)
        notify(route, kind: .replace)
    }

    func sync(_ route: Route) {
        guard route != currentRoute else { return }
        history.replace(route)
        notify(route, kind: .sync)
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

    private func notify(_ route: Route, kind: NavigationKind) {
        observers.values.forEach { $0(route, kind) }
    }
}
