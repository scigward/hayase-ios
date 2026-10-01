// W2GEvents.swift — W2G event types
// Mirrors: hayase-app/interface/src/lib/modules/w2g/events.ts

import Foundation

// MARK: - PlayerState

/// Synchronised playback state exchanged between W2G peers.
/// Mirrors `interface/events.ts → PlayerState { paused, time }`.
struct W2GPlayerState: Codable, Equatable {
    let paused: Bool
    let time: Double
}

// MARK: - MediaState

/// Describes the media a host is playing.
/// Mirrors `interface/events.ts → MediaState { torrent, mediaId, episode }`.
struct W2GMediaState: Codable, Equatable {
    let torrent: String
    let mediaId: Int
    let episode: Int

    private static let lastKey = "last-torrent"

    /// `server.last`, the torrent played last, kept between launches.
    static var last: W2GMediaState? {
        get {
            UserDefaults.standard.data(forKey: lastKey).flatMap { try? JSONDecoder().decode(W2GMediaState.self, from: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: lastKey)
        }
    }
}

// MARK: - Event envelope

/// Typed event envelope sent over P2P data channels.
/// Mirrors `interface/events.ts → class Event<K>` with `type` + `payload`.
struct W2GEvent: Codable {
    let type: EventKind
    let payload: AnyCodable  // flexible JSON payload

    enum EventKind: String, Codable {
        case `init`
        case media
        case index
        case player
        case message
    }

    init(type: EventKind, payload: AnyCodable) {
        self.type = type
        self.payload = payload
    }

    // Convenience factories matching the web's `new Event('type', payload)`.

    static func initEvent(user: W2GChatUser) -> W2GEvent {
        W2GEvent(type: .`init`, payload: AnyCodable(user))
    }

    static func mediaEvent(_ state: W2GMediaState?) -> W2GEvent {
        W2GEvent(type: .media, payload: AnyCodable(state))
    }

    static func indexEvent(_ index: Int) -> W2GEvent {
        W2GEvent(type: .index, payload: AnyCodable(index))
    }

    static func playerEvent(_ state: W2GPlayerState) -> W2GEvent {
        W2GEvent(type: .player, payload: AnyCodable(state))
    }

    static func messageEvent(_ text: String) -> W2GEvent {
        W2GEvent(type: .message, payload: AnyCodable(text))
    }
}

// MARK: - AnyCodable (lightweight type-erased Codable wrapper)

/// Minimal type-erased Codable so we can encode heterogeneous payloads into
/// the single `W2GEvent.payload` field without pulling in a heavy library.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // IMPORTANT: Try Int/Double BEFORE Bool. JSONDecoder backed by NSNumber
        // can decode JSON integers 0/1 as Bool (NSNumber bridging), which corrupts
        // downstream types (e.g. W2GMediaState.episode: 1 → true → decode fails).
        // Int.decode on JSON true/false correctly fails, so this order is safe.
        if container.decodeNil() {
            value = NSNull()
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable: unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        // IMPORTANT: Do NOT create singleValueContainer() eagerly at the top.
        // The Encodable case (structs like W2GChatUser, W2GMediaState, W2GPlayerState)
        // needs to call e.encode(to: encoder) which creates a KEYED container.
        // Creating a singleValueContainer first conflicts with that — causing crashes
        // (preconditionFailure) or silent encoding failures that drop init/media/player
        // events entirely. Create the container lazily only in branches that need it.
        switch value {
        case is NSNull:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case let b as Bool:
            var container = encoder.singleValueContainer()
            try container.encode(b)
        case let i as Int:
            var container = encoder.singleValueContainer()
            try container.encode(i)
        case let d as Double:
            var container = encoder.singleValueContainer()
            try container.encode(d)
        case let s as String:
            var container = encoder.singleValueContainer()
            try container.encode(s)
        case let arr as [Any]:
            var container = encoder.singleValueContainer()
            try container.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]:
            var container = encoder.singleValueContainer()
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let e as Encodable:
            // Let the concrete type create whatever container it needs (keyed, unkeyed, etc.)
            try e.encode(to: encoder)
        default:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}
