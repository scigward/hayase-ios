//
//  WebTorrentModels.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

struct WebTorrentTorrentInfo: Decodable {
    struct SizeInfo: Decodable {
        let total: UInt64
        let downloaded: UInt64
        let uploaded: UInt64
    }

    struct SpeedInfo: Decodable {
        let down: UInt64
        let up: UInt64
    }

    struct TimeInfo: Decodable {
        let remaining: Double?
        let elapsed: Double?
    }

    struct PeerCounts: Decodable {
        let seeders: Int
        let leechers: Int
        let wires: Int
    }

    struct PieceInfo: Decodable {
        let total: Int
        let size: UInt64
    }

    let name: String
    let progress: Double
    let size: SizeInfo
    let speed: SpeedInfo
    let time: TimeInfo
    let peers: PeerCounts
    let pieces: PieceInfo
    let hash: String
}

struct WebTorrentPeerInfo: Decodable {
    struct SizeInfo: Decodable {
        let downloaded: UInt64
        let uploaded: UInt64
    }

    struct SpeedInfo: Decodable {
        let down: UInt64
        let up: UInt64
    }

    let ip: String
    let seeder: Bool
    let client: String
    let progress: Double
    let size: SizeInfo
    let speed: SpeedInfo
    let flags: [String]
    let time: TimeInterval
}

struct WebTorrentFileInfo: Decodable {
    let name: String
    let size: UInt64
    let progress: Double
    let selections: Int
}

struct WebTorrentLibraryEntry: Decodable {
    let mediaID: Int?
    let episode: Int?
    let files: Int
    let hash: String
    let progress: Double
    let date: TimeInterval?
    let size: UInt64
    let name: String
}

struct WebTorrentProtocolStatus: Decodable {
    let dht: Bool
    let lsd: Bool
    let pex: Bool
    let nat: Bool
    let forwarding: Bool
    let persisting: Bool
    let streaming: Bool
}
