//
//  History.swift
//  Hayase
//
//  Browser-style route history for native navigation.
//

import Foundation

// MARK: - HistoryEntry

struct HistoryEntry: Hashable {
    var route: Route
    var hostTabIndex: Int?

    init(route: Route, hostTabIndex: Int? = nil) {
        self.route = route
        self.hostTabIndex = hostTabIndex
    }
}

// MARK: - History

final class History {
    private(set) var entries: [HistoryEntry]
    private(set) var currentIndex: Int

    init(initialRoute: Route) {
        entries = [HistoryEntry(route: initialRoute, hostTabIndex: initialRoute.tabIndex)]
        currentIndex = 0
    }

    var current: HistoryEntry {
        entries[currentIndex]
    }

    var canGoBack: Bool {
        currentIndex > 0
    }

    var canGoForward: Bool {
        currentIndex < entries.count - 1
    }

    func reset(to route: Route, hostTabIndex: Int? = nil) {
        entries = [HistoryEntry(route: route, hostTabIndex: hostTabIndex ?? route.tabIndex)]
        currentIndex = 0
    }

    func push(_ route: Route, hostTabIndex: Int? = nil) {
        if current.route == route { return }
        if canGoForward {
            entries.removeSubrange((currentIndex + 1)..<entries.count)
        }
        entries.append(HistoryEntry(route: route, hostTabIndex: hostTabIndex))
        currentIndex = entries.count - 1
    }

    func replace(_ route: Route, hostTabIndex: Int? = nil) {
        entries[currentIndex] = HistoryEntry(route: route, hostTabIndex: hostTabIndex)
    }

    func back() -> HistoryEntry? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return current
    }

    func forward() -> HistoryEntry? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return current
    }
}
