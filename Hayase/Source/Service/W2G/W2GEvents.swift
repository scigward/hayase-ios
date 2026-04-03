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
        if container.decodeNil() {
            value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
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
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let b as Bool:
            try container.encode(b)
        case let i as Int:
            try container.encode(i)
        case let d as Double:
            try container.encode(d)
        case let s as String:
            try container.encode(s)
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let e as Encodable:
            try e.encode(to: encoder)
        default:
            try container.encodeNil()
        }
    }
}
