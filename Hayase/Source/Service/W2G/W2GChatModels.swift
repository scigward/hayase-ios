// W2GChatModels.swift — Chat types for W2G
// Mirrors: hayase-app/interface/src/lib/components/ui/chat/index.ts

import Foundation

// MARK: - ChatUser

/// Represents a user in the W2G lobby.
/// Mirrors web `ChatUser` which is a subset of AniList Viewer:
/// `{ id, name, avatar: { large }, mediaListOptions }`.
struct W2GChatUser: Codable, Equatable {
    let id: String
    let name: String
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case avatarURL = "avatar"
    }

    /// Build from the local AniList TrackerViewer, or fall back to a guest.
    static func fromLocalViewer() -> W2GChatUser {
        if let viewer = TrackerAccountManager.shared.viewer(for: .anilist) {
            return W2GChatUser(id: viewer.id, name: viewer.name, avatarURL: viewer.avatarURL)
        }
        return W2GChatUser(id: W2GClient.generateRandomHex(length: 16), name: "Guest", avatarURL: nil)
    }
}

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
