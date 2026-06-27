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

    init(route: Route) {
        self.route = route
    }
}

// MARK: - History

final class History {
    private(set) var entries: [HistoryEntry]
    private(set) var currentIndex: Int

    init(initialRoute: Route) {
        entries = [HistoryEntry(route: initialRoute)]
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

    func reset(to route: Route) {
        entries = [HistoryEntry(route: route)]
        currentIndex = 0
    }

    func push(_ route: Route) {
        if current.route == route { return }
        if canGoForward {
            entries.removeSubrange((currentIndex + 1)..<entries.count)
        }
        entries.append(HistoryEntry(route: route))
        currentIndex = entries.count - 1
    }

    func replace(_ route: Route) {
        entries[currentIndex] = HistoryEntry(route: route)
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
