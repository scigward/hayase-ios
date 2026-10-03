//
//  SetupFlow.swift
//  Hayase
//
//  Mirrors: src/lib/index.ts (SETUP_VERSION), src/routes/+page.ts and src/routes/app/+layout.ts (which send the
//  app to /setup until `setup-finished` has reached the version), and the route list of src/routes/setup
//

import Foundation

enum SetupRoute: Equatable {
    /// `/setup`
    case welcome
    /// `/setup/storage`
    case storage
    /// `/setup/network`
    case network
    /// `/setup/extensions`
    case extensions

    /// Footer.svelte: `NEXT` and `PREV` by step. The welcome page has no step.
    var step: Int? {
        switch self {
        case .welcome: return nil
        case .storage: return 0
        case .network: return 1
        case .extensions: return 2
        }
    }
}

enum SetupFlow {
    /// `SETUP_VERSION`
    static let version = 3

    /// `localStorage['setup-finished']`
    static let finishedKey = "setup-finished"
    /// `persisted('torrent-port-forwarding', false)`, which the network page writes and the extensions page reads
    static let portForwardingKey = "torrent-port-forwarding"

    /// `Number(localStorage.getItem('setup-finished')) >= SETUP_VERSION`
    static var isFinished: Bool {
        UserDefaults.standard.integer(forKey: finishedKey) >= version
    }

    /// `localStorage.setItem('setup-finished', SETUP_VERSION.toString())`
    static func markFinished() {
        UserDefaults.standard.set(version, forKey: finishedKey)
    }

    static var hasPortForwarding: Bool {
        get { UserDefaults.standard.bool(forKey: portForwardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: portForwardingKey) }
    }
}
