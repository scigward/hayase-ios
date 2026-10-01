//
//  AniListConnectionStatus.swift
//  Hayase
//
//  Mirrors: interface lib/modules/online.ts (`navigator.onLine`) and the `error` store of
//  lib/modules/anilist/urql-client.ts, which the Online bar reads.
//

import Foundation
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
