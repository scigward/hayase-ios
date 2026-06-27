//
//  TorrentClientPeerRow.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation
import LibTorrent

struct TorrentClientPeerRow {
    enum Flag: String, CaseIterable {
        case incoming
        case outgoing
        case utp
        case encrypted
    }

    let ip: String
    let client: String
    let isSeeder: Bool
    let progress: Double
    let downloadSpeed: UInt64
    let uploadSpeed: UInt64
    let downloaded: UInt64
    let uploaded: UInt64
    let flags: [Flag]

    var totalSpeed: UInt64 {
        downloadSpeed + uploadSpeed
    }

    init(peer: PeerInfo) {
        self.ip = peer.ip
        self.client = peer.client
        self.isSeeder = peer.progress >= 0.999
        self.progress = Double(max(0, min(peer.progress, 1)))
        self.downloadSpeed = UInt64(max(0, peer.downloadSpeed))
        self.uploadSpeed = UInt64(max(0, peer.uploadSpeed))
        self.downloaded = UInt64(max(0, peer.totalDownload))
        self.uploaded = UInt64(max(0, peer.totalUpload))
        self.flags = Self.normalizedFlags(peer.connectionFlags)
    }

    init(peer: WebTorrentPeerInfo) {
        self.ip = peer.ip
        self.client = peer.client
        self.isSeeder = peer.seeder
        self.progress = max(0, min(peer.progress, 1))
        self.downloadSpeed = peer.speed.down
        self.uploadSpeed = peer.speed.up
        self.downloaded = peer.size.downloaded
        self.uploaded = peer.size.uploaded
        self.flags = Self.normalizedFlags(peer.flags)
    }

    private static func normalizedFlags(_ values: [String]) -> [Flag] {
        var result: [Flag] = []
        for value in values {
            let flag = value
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")
                .lowercased()

            let resolved: Flag?
            if flag.contains("incoming") || flag == "in" {
                resolved = .incoming
            } else if flag.contains("outgoing") || flag == "out" {
                resolved = .outgoing
            } else if flag.contains("utp") || flag.contains("udp") {
                resolved = .utp
            } else if flag.contains("encrypted") || flag.contains("encrypt") || flag == "e" {
                resolved = .encrypted
            } else {
                resolved = nil
            }

            if let resolved, !result.contains(resolved) {
                result.append(resolved)
            }
        }
        return result
    }
}
