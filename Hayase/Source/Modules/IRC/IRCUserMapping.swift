//
//  IRCUserMapping.swift
//  Hayase
//
//  Created by scigward.
//
//  Mirrors the pure user/avatar mapping logic in
//  src/lib/modules/irc/index.ts (`getPFP`, `ircUserToChatUser`,
//  `ircIdentToChatUser`, `EXT_MAP`).
//
//  This is a deliberately scoped first increment: the WebSocket transport
//  and IRC line-protocol parsing (NICK/JOIN/PRIVMSG/NAMES/etc., matching
//  irc/connections.ts + the `@thaunknown/web-irc` client interface.swift
//  depends on) are not included yet — this file only covers the parts with
//  zero networking, so they're portable and checkable in isolation. See the
//  architecture comparison notes for the rest of the plan.
//
//  Correction from earlier discussion: interface's IRC transport connects
//  over a WebSocket (`wss://irc.hybridirc.com:7002`, see connections.ts),
//  not a raw TCP+TLS socket — worth flagging since that changes what the
//  Swift transport layer should use (`URLSessionWebSocketTask`, not the
//  `Network` framework) once that piece is built.

import Foundation

/// A resolved chat participant, ready for display.
///
/// Mirrors the shared `ChatUser` type from `components/ui/chat/index.ts`,
/// scoped to what the IRC surface needs. Not unified with `W2GChatUser`
/// (`Modules/W2G/W2GChatModels.swift`) yet — that type is W2G-specific today
/// and has no `guest` flag. Worth consolidating into one shared chat-user
/// type once the IRC surface is built out, matching how interface shares a
/// single `ChatUser` between both features.
struct IRCUser: Equatable {
    let id: String
    let name: String
    let avatarURL: String
    let isGuest: Bool
}

extension IRCUser: ChatListUser {
    var resolvedAvatarURL: String { avatarURL }
}

/// The identity Hayase presents to the IRC network before connecting.
/// Mirrors interface's `IRCChatUser`.
struct IRCIdentity: Equatable {
    enum Kind: String {
        case anilist = "al"
        case guest
    }

    let nick: String
    let id: String
    let pfpID: String
    let prefix: String
    let ext: String
    let type: Kind
}

/// The raw nick/ident pair as seen on the wire for a connected IRC user.
/// Mirrors interface's `IRCUser` (unfortunately named the same as our
/// display-facing `IRCUser` above; interface's is the raw wire type — kept
/// separate here as `IRCRawUser` to avoid that collision in Swift).
struct IRCRawUser: Equatable {
    let nick: String
    let ident: String
}

enum IRCUserMapping {
    /// Single-letter extension codes IRC nicks encode. Mirrors `EXT_MAP`.
    static let extensionMap: [Character: String] = ["j": "jpg", "p": "png", "w": "webp", "g": "gif"]

    private static let defaultAvatarURL = "https://s4.anilist.co/file/anilistcdn/user/avatar/medium/default.png"

    /// Mirrors `getPFP`.
    static func avatarURL(id: String, pfpID: String, prefix: String, ext: String, type: IRCIdentity.Kind) -> String {
        guard type == .anilist, !id.isEmpty, !pfpID.isEmpty, !prefix.isEmpty, !ext.isEmpty else {
            return defaultAvatarURL
        }
        return "https://s4.anilist.co/file/anilistcdn/user/avatar/large/\(prefix)\(id)-\(pfpID).\(ext)"
    }

    /// Mirrors `ircUserToChatUser`: maps an identity whose fields are already known.
    static func chatUser(from identity: IRCIdentity) -> IRCUser {
        IRCUser(
            id: identity.id,
            name: identity.nick,
            avatarURL: avatarURL(id: identity.id, pfpID: identity.pfpID, prefix: identity.prefix,
                                  ext: identity.ext, type: identity.type),
            isGuest: identity.type == .guest)
    }

    /// Mirrors `ircIdentToChatUser`: decodes a raw IRC nick/ident pair into a
    /// displayable user. AniList users' nicks encode their avatar as a
    /// prefix before the first underscore, e.g. `pJj3xK9_someone` — a guest
    /// nick has no such encoding.
    static func chatUser(from raw: IRCRawUser) -> IRCUser {
        // JS: `nick.split('_')` never omits empty pieces — match that so an
        // empty or underscore-only nick behaves the same as upstream.
        let nickParts = raw.nick.components(separatedBy: "_")
        let pfp = nickParts[0]
        let restParts = nickParts.dropFirst()
        // JS: `rest.join('_') || user.nick` — falls back on the JOINED
        // STRING being falsy (empty), not on `rest` having zero elements.
        // Those differ for a nick like "abc_" (one trailing underscore, then
        // nothing): `rest` is `[""]` — one element, so an array-emptiness
        // check would treat it as "has content" and produce `nick = ""`,
        // while JS's join produces `""` too and IS empty, so it falls back
        // to the original `user.nick` ("abc_") instead. Checking the joined
        // string's emptiness (not the array's) matches JS exactly.
        let joinedRest = restParts.joined(separator: "_")
        let nick = joinedRest.isEmpty ? raw.nick : joinedRest

        let identParts = raw.ident.components(separatedBy: "_")
        let typeRaw = identParts.first
        let id = identParts.count > 1 ? identParts[1] : nil

        guard typeRaw == IRCIdentity.Kind.anilist.rawValue else {
            return IRCUser(id: id ?? "0", name: nick, avatarURL: defaultAvatarURL, isGuest: true)
        }

        let pfpChars = Array(pfp)
        let extLetter = pfpChars.first.map(String.init) ?? ""
        let prefix = pfpChars.count > 1 ? String(pfpChars[1]) : ""
        let pfpID = pfpChars.count > 2 ? String(pfpChars[2...]) : ""
        let ext = extLetter.first.flatMap { extensionMap[$0] } ?? extLetter

        return chatUser(from: IRCIdentity(nick: nick, id: id ?? "0", pfpID: pfpID, prefix: prefix, ext: ext, type: .anilist))
    }
}
