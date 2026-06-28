//
//  PageQuery.swift
//  Hayase
//
//  Lightweight query state used by native AniList surfaces.
//  Mirrors the urql query-store model used by the Interface without pulling
//  transport details into view controllers.
//

import Foundation

enum AniListRequestPolicy {
    case cacheFirst
    case cacheAndNetwork
    case networkOnly
    case pausedUntilVisible
}

final class PageQuery<Value> {
    enum State {
        case idle
        case fetching(previous: Value?)
        case success(Value)
        case empty
        case failure(Error, previous: Value?)
    }

    private let queue = DispatchQueue(label: "com.hayase.pageQuery")
    private var observers: [UUID: (State) -> Void] = [:]
    private(set) var state: State = .idle
    private var token: AniListRequestToken?

    var currentValue: Value? {
        queue.sync {
            switch state {
            case .success(let value):
                return value
            case .fetching(let previous), .failure(_, let previous):
                return previous
            case .idle, .empty:
                return nil
            }
        }
    }

    @discardableResult
    func observe(_ observer: @escaping (State) -> Void) -> UUID {
        let id = UUID()
        let current = queue.sync { () -> State in
            observers[id] = observer
            return state
        }
        DispatchQueue.main.async { observer(current) }
        return id
    }

    func removeObserver(_ id: UUID) {
        queue.async { [weak self] in
            self?.observers.removeValue(forKey: id)
        }
    }

    func pause() {
        queue.async { [weak self] in
            self?.token?.cancel()
            self?.token = nil
        }
    }

    func attach(_ token: AniListRequestToken?) {
        queue.async { [weak self] in
            self?.token?.cancel()
            self?.token = token
        }
    }

    func setFetching(previous: Value? = nil) {
        transition(to: .fetching(previous: previous ?? currentValue))
    }

    func setSuccess(_ value: Value, isEmpty: Bool = false) {
        transition(to: isEmpty ? .empty : .success(value))
    }

    func setFailure(_ error: Error, previous: Value? = nil) {
        transition(to: .failure(error, previous: previous ?? currentValue))
    }

    private func transition(to newState: State) {
        let callbacks = queue.sync { () -> [(State) -> Void] in
            state = newState
            return Array(observers.values)
        }
        DispatchQueue.main.async {
            callbacks.forEach { $0(newState) }
        }
    }
}
