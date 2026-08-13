// W2GChatModels.swift — Chat types for W2G
// Mirrors: hayase-app/interface/src/lib/components/ui/chat/index.ts

import Foundation

// MARK: - ChatUser

/// Represents a user in the W2G lobby.
/// Mirrors web `ChatUser` which is a subset of AniList Viewer:
/// `{ id, name, avatar: { large }, mediaListOptions }`.
///
/// The web's avatar field is `{ large: string }` (an object), not a flat string.
/// We use custom coding to read/write `avatar.large` for cross-platform compat.
struct W2GChatUser: Codable, Equatable {
    let id: String
    let name: String
    let avatarURL: String?

    /// AniList default avatar, used as fallback for guests (mirrors web's `?? 'https://s4.anilist.co/...'`).
    static let defaultAvatarURL = "https://s4.anilist.co/file/anilistcdn/user/avatar/large/default.png"

    /// Resolved avatar URL – returns `avatarURL` if present, otherwise the AniList default.
    var resolvedAvatarURL: String {
        avatarURL ?? Self.defaultAvatarURL
    }

    enum CodingKeys: String, CodingKey {
        case id, name, avatar
    }

    private struct AvatarWrapper: Codable, Equatable {
        let large: String?
    }

    init(id: String, name: String, avatarURL: String?) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Web's ChatUser.id can be a number (AniList viewer ID) or string (guest hex).
        if let strID = try? container.decode(String.self, forKey: .id) {
            id = strID
        } else if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = "unknown"
        }
        name = try container.decode(String.self, forKey: .name)
        // Web sends avatar as { large: "url" }; decode the nested object.
        if let wrapper = try? container.decode(AvatarWrapper.self, forKey: .avatar) {
            avatarURL = wrapper.large
        } else {
            // Fallback: accept a flat string for iOS-to-iOS compat.
            avatarURL = try? container.decode(String.self, forKey: .avatar)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Web sends id as a number for AniList viewers. Encode as Int when possible
        // for cross-platform compatibility.
        if let intID = Int(id) {
            try container.encode(intID, forKey: .id)
        } else {
            try container.encode(id, forKey: .id)
        }
        try container.encode(name, forKey: .name)
        // Encode avatar as { large: "url" } to match web format.
        if let url = avatarURL {
            try container.encode(AvatarWrapper(large: url), forKey: .avatar)
        } else {
            try container.encodeNil(forKey: .avatar)
        }
    }

    /// Build from the local AniList TrackerViewer, or fall back to a guest.
    static func fromLocalViewer() -> W2GChatUser {
        if let viewer = TrackerAccountManager.shared.viewer(for: .anilist) {
            return W2GChatUser(id: viewer.id, name: viewer.name, avatarURL: viewer.avatarURL)
        }
        return W2GChatUser(id: W2GClient.generateRandomHex(length: 16), name: "Guest", avatarURL: nil)
    }
}

/// `isGuest` uses `ChatListUser`'s default (`false`) — W2G has no guest
/// concept distinct from a regular participant the way IRC does.
extension W2GChatUser: ChatListUser {}

// MARK: - ChatMessage

/// A single chat message.
/// Mirrors web `ChatMessage { message, user, type, date }`.
struct W2GChatMessage {
    let message: String
    let user: W2GChatUser
    let type: MessageType
    let date: Date

    enum MessageType {
        case incoming
        case outgoing
    }
}
