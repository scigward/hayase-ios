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
        case paused
        case fetching(previous: Value?)
        case success(Value)
        case empty
        case failure(Error, previous: Value?)
    }

    private let queue = DispatchQueue(label: "com.hayase.pageQuery")
    private var observers: [UUID: (State) -> Void] = [:]
    private(set) var state: State = .idle
    private var token: AniListRequestToken?
    private var resumeHandler: (() -> AniListRequestToken?)?
    private var hasStarted = false
    /// Runs the query again (`requestPolicy: 'cache-and-network'`), for `refocusExchange`.
    private var refetchHandler: (() -> AniListRequestToken?)?
    private var refocusObserver: NSObjectProtocol?

    init() {
        refocusObserver = NotificationCenter.default.addObserver(forName: AniListRefocus.didRefocus,
                                                                  object: nil, queue: .main) { [weak self] _ in
            self?.refocus()
        }
    }

    deinit {
        if let refocusObserver { NotificationCenter.default.removeObserver(refocusObserver) }
    }

    func setRefetch(_ handler: @escaping () -> AniListRequestToken?) {
        queue.async { [weak self] in
            self?.refetchHandler = handler
        }
    }

    /// An operation that has started, that is not paused and that is not waiting for an answer.
    private func refocus() {
        let handler = queue.sync { () -> (() -> AniListRequestToken?)? in
            guard hasStarted, resumeHandler == nil, let refetchHandler else { return nil }
            if case .fetching = state { return nil }
            return refetchHandler
        }
        guard let handler else { return }
        _ = handler()
    }

    var currentValue: Value? {
        queue.sync {
            switch state {
            case .success(let value):
                return value
            case .fetching(let previous), .failure(_, let previous):
                return previous
            case .idle, .paused, .empty:
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

    func preparePaused(_ resumeHandler: @escaping () -> AniListRequestToken?) {
        transition { [weak self] in
            self?.token?.cancel()
            self?.token = nil
            self?.resumeHandler = resumeHandler
            self?.hasStarted = false
            return .paused
        }
    }

    @discardableResult
    func resume() -> Bool {
        let handler = queue.sync { () -> (() -> AniListRequestToken?)? in
            guard !hasStarted, let resumeHandler else { return nil }
            hasStarted = true
            self.resumeHandler = nil
            state = .fetching(previous: currentValueUnlocked())
            return resumeHandler
        }

        guard let handler else { return false }
        notifyObservers()
        _ = handler()
        return true
    }

    func pause() {
        queue.async { [weak self] in
            self?.token?.cancel()
            self?.token = nil
            self?.resumeHandler = nil
        }
    }

    func attach(_ token: AniListRequestToken?) {
        queue.async { [weak self] in
            self?.token?.cancel()
            self?.token = token
        }
    }

    func setFetching(previous: Value? = nil) {
        transition { [weak self] in
            self?.hasStarted = true
            return .fetching(previous: previous ?? self?.currentValueUnlocked())
        }
    }

    func setSuccess(_ value: Value, isEmpty: Bool = false) {
        transition { [weak self] in
            self?.resumeHandler = nil
            self?.hasStarted = true
            return isEmpty ? .empty : .success(value)
        }
    }

    func setFailure(_ error: Error, previous: Value? = nil) {
        transition { [weak self] in
            self?.resumeHandler = nil
            self?.hasStarted = true
            return .failure(error, previous: previous ?? self?.currentValueUnlocked())
        }
    }

    private func currentValueUnlocked() -> Value? {
        switch state {
        case .success(let value):
            return value
        case .fetching(let previous), .failure(_, let previous):
            return previous
        case .idle, .paused, .empty:
            return nil
        }
    }

    private func transition(_ mutate: @escaping () -> State) {
        let callbacks = queue.sync { () -> [(State) -> Void] in
            state = mutate()
            return Array(observers.values)
        }
        let newState = stateSnapshot()
        DispatchQueue.main.async {
            callbacks.forEach { $0(newState) }
        }
    }

    private func stateSnapshot() -> State {
        queue.sync { state }
    }

    private func notifyObservers() {
        let current = queue.sync { () -> (State, [(State) -> Void]) in
            (state, Array(observers.values))
        }
        DispatchQueue.main.async {
            current.1.forEach { $0(current.0) }
        }
    }
}
