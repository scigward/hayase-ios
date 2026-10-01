//
//  AniListConnectionStatus.swift
//  Hayase
//
//  Mirrors: interface lib/modules/online.ts (`navigator.onLine`) and the `error` store of
//  lib/modules/anilist/urql-client.ts, which the Online bar reads.
//

import UIKit
import Network

final class AniListConnectionStatus {
    static let shared = AniListConnectionStatus()
    static let didChange = Notification.Name("HayaseAniListConnectionStatusDidChange")
    /// `window.addEventListener('online', …)`: posted when the device is back on a network.
    static let didComeOnline = Notification.Name("HayaseDeviceDidComeOnline")

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.hayase.connectionStatus")
    private let lock = NSLock()
    private var online = true
    private var error: String?

    /// `navigator.onLine`
    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return online
    }

    /// `$error.message` of the last AniList response, nil after one without an error.
    var errorMessage: String? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.setOnline(path.status == .satisfied)
        }
        monitor.start(queue: monitorQueue)
    }

    /// Starts the path monitor, so the first state is known before the shell asks for it.
    func start() {}

    private func setOnline(_ value: Bool) {
        lock.lock()
        let changed = online != value
        online = value
        lock.unlock()
        guard changed else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChange, object: nil)
            if value { NotificationCenter.default.post(name: Self.didComeOnline, object: nil) }
        }
    }

    /// The urql `tap` of every result: `this.error.set(error)`.
    func report(_ message: String?) {
        lock.lock()
        let changed = error != message
        error = message
        lock.unlock()
        guard changed else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }
}

/// Mirrors: interface urql-client.ts `refocusExchange({ minimumTime: 60_000 })`. When the app is
/// visible again after at least a minute hidden, every query that is still on screen asks again.
final class AniListRefocus {
    static let shared = AniListRefocus()
    /// Posted on the main queue; whoever holds an active query runs it again.
    static let didRefocus = Notification.Name("HayaseAniListRefocus")

    private var hiddenAt = Date(timeIntervalSince1970: 0)

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.hiddenAt = Date()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.hiddenAt) >= 60 else { return }
            NotificationCenter.default.post(name: Self.didRefocus, object: nil)
        }
    }

    /// Starts listening, so the first time the app is hidden is known.
    func start() {}
}
