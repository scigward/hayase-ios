// IRCLobby.swift — Singleton lobby state holder
// Mirrors: hayase-app/interface/src/lib/modules/irc/lobby.ts
//
// Web: `export const irc = writable<Promise<MessageClient> | null>(null)`,
//      and `irc.svelte` does `$irc ??= MessageClient.new(ident)` — meaning
//      the connection is created once and persists across navigation until
//      something explicitly sets `$irc = null` (the exit/door button).
//      The sidebar reads this same store directly to show a status dot,
//      regardless of which page is currently active.
// iOS: A simple observable singleton holding the current IRCClient, mirrong
//      W2GLobby.swift's existing pattern exactly for consistency.
//
// This file did not exist in the first pass of the IRC port — the chat view
// controller owned its own private IRCClient instance instead, scoped to
// its own lifecycle. That meant the connection didn't persist the way
// interface's does, and nothing else in the app (like the sidebar) had any
// way to observe connection state. This fixes both.

import Foundation

/// Global IRC lobby state. Mirrors the web's `irc` writable store.
/// Holds the current `IRCClient` instance (nil when no session is active).
final class IRCLobby {
    static let shared = IRCLobby()

    /// Mirrors `export const prevAgreed = writable(false)` in
    /// `modules/irc/index.ts`. Deliberately an in-memory flag, not
    /// `UserDefaults` — the web store is a plain in-memory `writable`, so it
    /// resets on every fresh page load and the content-warning page reappears
    /// each session. An earlier version of this port persisted the
    /// agreement to `UserDefaults`, which meant it was never reset once
    /// set — after agreeing once, every later app launch skipped straight
    /// to a live connection the moment the chat tab was opened, with no
    /// warning page at all. That's a real behavioral divergence from
    /// upstream, not a Swift necessity, so it's fixed by matching the web
    /// store's actual (session-only) lifetime instead.
    static var prevAgreed = false

    /// Posted on the main queue whenever `client` changes.
    static let didChange = Notification.Name("IRCLobbyDidChange")

    /// The active IRC session, or nil.
    var client: IRCClient? {
        didSet {
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    private init() {}

    /// Mirrors `$irc ??= MessageClient.new(ident)`: reuses an existing
    /// session if one is already active, otherwise creates and connects a
    /// new one. Returns the (possibly pre-existing) client either way.
    @discardableResult
    func connect() -> IRCClient {
        if let existing = client {
            return existing
        }
        let newClient = IRCClient(identity: .current())
        client = newClient
        newClient.connect()
        return newClient
    }

    /// Mirrors `quit()`: disconnects and clears the session.
    func leave() {
        client?.disconnect()
        client = nil
    }
}
