//
//  WebTorrentBridgeStatus.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

struct WebTorrentBridgeEvent: Decodable {
    let time: TimeInterval?
    let level: String
    let message: String
    let source: String?
}

struct WebTorrentBridgeStatus: Decodable {
    let version: String?
    let phase: String
    let sourceKind: String?
    let source: String?
    let infoHash: String?
    let ready: Bool
    let metadata: Bool
    let peers: Int
    let wires: Int
    let files: Int
    let dht: Bool?
    let pex: Bool?
    let webRTC: Bool?
    let lastWarning: String?
    let lastError: String?
    let updatedAt: TimeInterval?
    let events: [WebTorrentBridgeEvent]?

    var hudMessage: String {
        var message: String
        switch phase {
        case "booting", "listening", "loading-client":
            message = "Starting WebTorrent backend…"
        case "resolving-source":
            message = "Resolving torrent source…"
        case "fetching-torrent-file":
            message = "Downloading .torrent metadata…"
        case "using-torrent-file":
            message = "Loading .torrent metadata…"
        case "adding-torrent", "metadata-pending", "peer-connected":
            message = metadata ? "Preparing file list…" : "Connecting to peers…"
        case "metadata-received":
            message = "Preparing file list…"
        case "ready", "done":
            message = "Preparing playback…"
        case "failed":
            return lastError ?? "WebTorrent backend failed."
        default:
            message = "Connecting to peers…"
        }

        if !ready && !metadata {
            if peers > 0 || wires > 0 {
                message += " (peers: \(peers), wires: \(wires))"
            } else if let sourceKind {
                message += " (\(sourceKind))"
            }
        }

        if let warning = lastWarning, !warning.isEmpty {
            message += "\nLast warning: \(warning)"
        }

        return message
    }

    static var unavailable: WebTorrentBridgeStatus {
        WebTorrentBridgeStatus(version: nil,
                               phase: "unavailable",
                               sourceKind: nil,
                               source: nil,
                               infoHash: nil,
                               ready: false,
                               metadata: false,
                               peers: 0,
                               wires: 0,
                               files: 0,
                               dht: nil,
                               pex: nil,
                               webRTC: nil,
                               lastWarning: nil,
                               lastError: nil,
                               updatedAt: nil,
                               events: nil)
    }
}
