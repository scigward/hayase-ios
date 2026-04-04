// W2GLobby.swift — Singleton lobby state holder
// Mirrors: hayase-app/interface/src/lib/modules/w2g/lobby.ts
//
// Web: `export const w2globby = writable<W2GClient | undefined>()`
// iOS: A simple observable singleton that holds the current W2GClient.

import Foundation

// MARK: - W2GLobby

/// Global W2G lobby state. Mirrors the web's `w2globby` writable store.
/// Holds the current `W2GClient` instance (nil when no session is active).
///
/// Usage:
///   W2GLobby.shared.client   // current W2GClient or nil
///   W2GLobby.shared.client = W2GClient(code: "abc12345", isHost: true)
///   W2GLobby.shared.client?.destroy()
///   W2GLobby.shared.client = nil
final class W2GLobby {
    static let shared = W2GLobby()

    /// Posted on the main queue whenever `client` changes.
    static let didChange = Notification.Name("W2GLobbyDidChange")

    /// The active W2G session, or nil.
    var client: W2GClient? {
        didSet {
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    private init() {}

    // MARK: - Convenience (mirrors web route logic)

    /// Create or reuse a host lobby. Mirrors web `/app/w2g/+page.ts → load()`.
    ///
    /// - If a client already exists, returns its code.
    /// - Otherwise creates a new host client with a random 8-char code and
    ///   optionally attaches the last-played media state.
    @discardableResult
    func createHostLobby(media: W2GMediaState? = nil) -> String {
        if let existing = client {
            return existing.code
        }
        let code = W2GClient.generateRandomHex(length: 8)
        client = W2GClient(code: code, isHost: true, media: media)
        return code
    }

    /// Join a lobby by code. Mirrors web `/app/w2g/[id]/+page.ts → load()`.
    ///
    /// - If a client already exists with a different code, destroys it first.
    func joinLobby(code: String) {
        if let existing = client {
            if existing.code == code { return }
            existing.destroy()
            client = nil
        }
        client = W2GClient(code: code, isHost: false)
    }

    /// Destroy the current session and clear the client.
    func leave() {
        client?.destroy()
        client = nil
    }
}
