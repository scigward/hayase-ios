//
//  WebTorrentBridgeStatus.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

struct WebTorrentBridgeEvent: Decodable {
    let id: Int?
    let userFacing: Bool?
    let title: String?
    let time: TimeInterval?
    let level: String
    let message: String
    let source: String?
}

/// A Chromecast/DLNA session the bridge started: `playing`, `ended` or `error`.
struct WebTorrentCastSession: Decodable {
    let state: String
    let error: String?
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
    let discoveredPeers: Int?
    let wires: Int
    let files: Int
    let downloaded: UInt64?
    let uploaded: UInt64?
    let total: UInt64?
    let downloadSpeed: UInt64?
    let uploadSpeed: UInt64?
    let progress: Double?
    let dht: Bool?
    let pex: Bool?
    let webRTC: Bool?
    let lastWarning: String?
    let lastError: String?
    let updatedAt: TimeInterval?
    let events: [WebTorrentBridgeEvent]?
    let cast: [String: WebTorrentCastSession]?

    var hudMessage: String {
        var message: String
        switch phase {
        case "booting", "listening", "loading-client":
            message = "Starting WebTorrent backend…"
        case "idle":
            message = "WebTorrent backend is idle."
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
            if wires > 0 {
                message += " (connected: \(wires))"
            } else if peers > 0 {
                message += " (peers: \(peers))"
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
                               discoveredPeers: nil,
                               wires: 0,
                               files: 0,
                               downloaded: nil,
                               uploaded: nil,
                               total: nil,
                               downloadSpeed: nil,
                               uploadSpeed: nil,
                               progress: nil,
                               dht: nil,
                               pex: nil,
                               webRTC: nil,
                               lastWarning: nil,
                               lastError: nil,
                               updatedAt: nil,
                               events: nil,
                               cast: nil)
    }
}
