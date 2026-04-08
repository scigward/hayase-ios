//
//  TrackerScrapeService.swift
//  Hayase
//
//  Implements BEP 15 (UDP Tracker Protocol) scrape to fetch live peer counts
//  (seeders/leechers/completed) for info-hashes.
//
//  Mirrors web's `native.updatePeerCounts(hashes)` which returns
//  `{ hash, complete, downloaded, incomplete }` per entry.
//
//  References:
//  - BEP 15: https://www.bittorrent.org/beps/bep_0015.html
//  - extensions.ts: `updatePeerCounts()` in hayase-app/interface

import Foundation
import Network

/// Result of a tracker scrape for a single info-hash.
struct ScrapeResult {
    let hash: String      // hex-encoded info-hash
    let complete: Int      // seeders
    let downloaded: Int    // completed downloads
    let incomplete: Int    // leechers
}

/// Lightweight UDP tracker scrape service (BEP 15).
///
/// Usage:
/// ```
/// let results = await TrackerScrapeService.scrape(
///     hashes: ["abcdef1234...", ...],
///     magnetLinks: ["magnet:?xt=urn:btih:...&tr=udp://...", ...]
/// )
/// ```
final class TrackerScrapeService {

    // MARK: - Public API

    /// Scrape peer counts for the given info-hashes.
    ///
    /// - Parameters:
    ///   - hashes: Hex-encoded v1 info-hashes (40 chars each).
    ///   - magnetLinks: Magnet URIs from which tracker URLs are extracted.
    /// - Returns: Best scrape results for each hash that was successfully scraped.
    static func scrape(hashes: [String], magnetLinks: [String]) async -> [ScrapeResult] {
        guard !hashes.isEmpty else { return [] }

        // 1. Collect unique UDP tracker endpoints from magnet links
        var trackerURLs = extractUDPTrackers(from: magnetLinks)

        // 2. Add well-known public trackers as fallback
        let publicTrackers = [
            "udp://tracker.opentrackr.org:1337",
            "udp://open.stealth.si:80",
            "udp://tracker.openbittorrent.com:6969",
            "udp://exodus.desync.com:6969",
            "udp://tracker.torrent.eu.org:451",
        ]
        for t in publicTrackers {
            trackerURLs.insert(t)
        }

        // 3. Convert hex hashes to raw 20-byte Data
        let hashPairs: [(hex: String, raw: Data)] = hashes.compactMap { hex in
            guard let raw = Data(hexString: hex), raw.count == 20 else { return nil }
            return (hex, raw)
        }
        guard !hashPairs.isEmpty else { return [] }

        // 4. Scrape each tracker concurrently (with timeout)
        // Collect per-hash results, keeping the best (highest seeders) from any tracker.
        var bestResults: [String: ScrapeResult] = [:]
        let lock = NSLock()

        await withTaskGroup(of: [ScrapeResult].self) { group in
            for trackerURL in trackerURLs {
                group.addTask {
                    await self.scrapeTracker(
                        url: trackerURL,
                        hashPairs: hashPairs,
                        timeout: 5.0
                    )
                }
            }
            for await results in group {
                lock.lock()
                for r in results {
                    if let existing = bestResults[r.hash] {
                        // Keep the result with more seeders
                        if r.complete > existing.complete {
                            bestResults[r.hash] = r
                        }
                    } else {
                        bestResults[r.hash] = r
                    }
                }
                lock.unlock()
            }
        }

        return Array(bestResults.values)
    }

    // MARK: - UDP Tracker Scrape (BEP 15)

    /// Scrape a single UDP tracker for all given hashes.
    private static func scrapeTracker(
        url: String,
        hashPairs: [(hex: String, raw: Data)],
        timeout: TimeInterval
    ) async -> [ScrapeResult] {
        guard let (host, port) = parseUDPURL(url) else { return [] }

        // BEP 15 limits scrape to ~74 hashes per request (1500 byte MTU).
        // For safety, batch at 50.
        let batchSize = 50
        var allResults: [ScrapeResult] = []

        for batchStart in stride(from: 0, to: hashPairs.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, hashPairs.count)
            let batch = Array(hashPairs[batchStart..<batchEnd])

            if let results = await scrapeBatch(host: host, port: port, batch: batch, timeout: timeout) {
                allResults.append(contentsOf: results)
            }
        }

        return allResults
    }

    /// Scrape a single batch of hashes from one tracker.
    private static func scrapeBatch(
        host: String,
        port: UInt16,
        batch: [(hex: String, raw: Data)],
        timeout: TimeInterval
    ) async -> [ScrapeResult]? {
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .udp
            )

            let queue = DispatchQueue(label: "scrape.\(host):\(port)", qos: .utility)
            var resumed = false
            let resumeLock = NSLock()

            func finish(_ results: [ScrapeResult]?) {
                resumeLock.lock()
                guard !resumed else { resumeLock.unlock(); return }
                resumed = true
                resumeLock.unlock()
                connection.cancel()
                continuation.resume(returning: results)
            }

            // Timeout
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Step 1: Send connect request
                    let transactionId = UInt32.random(in: 0...UInt32.max)
                    let connectData = buildConnectRequest(transactionId: transactionId)
                    connection.send(content: connectData, completion: .contentProcessed({ _ in }))

                    // Step 2: Receive connect response
                    connection.receive(minimumIncompleteLength: 16, maximumLength: 16) { data, _, _, _ in
                        guard let data = data, data.count >= 16 else { finish(nil); return }

                        let action = data.readUInt32(at: 0)
                        let respTxId = data.readUInt32(at: 4)
                        guard action == 0, respTxId == transactionId else { finish(nil); return }

                        let connectionId = data.readUInt64(at: 8)

                        // Step 3: Send scrape request
                        let scrapeTxId = UInt32.random(in: 0...UInt32.max)
                        let scrapeData = buildScrapeRequest(
                            connectionId: connectionId,
                            transactionId: scrapeTxId,
                            hashes: batch.map(\.raw)
                        )
                        connection.send(content: scrapeData, completion: .contentProcessed({ _ in }))

                        // Step 4: Receive scrape response
                        let expectedSize = 8 + batch.count * 12
                        connection.receive(minimumIncompleteLength: expectedSize, maximumLength: expectedSize + 100) { data, _, _, _ in
                            guard let data = data, data.count >= 8 + batch.count * 12 else { finish(nil); return }

                            let scrapeAction = data.readUInt32(at: 0)
                            let scrapeRespTxId = data.readUInt32(at: 4)
                            guard scrapeAction == 2, scrapeRespTxId == scrapeTxId else { finish(nil); return }

                            // Parse results: 12 bytes per hash (complete, downloaded, incomplete)
                            var results: [ScrapeResult] = []
                            for (i, pair) in batch.enumerated() {
                                let offset = 8 + i * 12
                                guard offset + 12 <= data.count else { break }
                                let complete   = Int(data.readUInt32(at: offset))
                                let downloaded = Int(data.readUInt32(at: offset + 4))
                                let incomplete = Int(data.readUInt32(at: offset + 8))
                                results.append(ScrapeResult(
                                    hash: pair.hex,
                                    complete: complete,
                                    downloaded: downloaded,
                                    incomplete: incomplete
                                ))
                            }
                            finish(results)
                        }
                    }

                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    // MARK: - Packet builders

    /// BEP 15 connect request: 16 bytes
    /// [8: protocol_id (0x41727101980), 4: action (0=connect), 4: transaction_id]
    private static func buildConnectRequest(transactionId: UInt32) -> Data {
        var data = Data(capacity: 16)
        data.appendUInt64(0x41727101980)  // protocol_id
        data.appendUInt32(0)                    // action = connect
        data.appendUInt32(transactionId)
        return data
    }

    /// BEP 15 scrape request: 16 + 20*N bytes
    /// [8: connection_id, 4: action (2=scrape), 4: transaction_id, 20*N: info_hashes]
    private static func buildScrapeRequest(connectionId: UInt64, transactionId: UInt32, hashes: [Data]) -> Data {
        var data = Data(capacity: 16 + hashes.count * 20)
        data.appendUInt64(connectionId)
        data.appendUInt32(2)                    // action = scrape
        data.appendUInt32(transactionId)
        for hash in hashes {
            data.append(hash)
        }
        return data
    }

    // MARK: - URL parsing

    /// Extract unique UDP tracker URLs from magnet links.
    private static func extractUDPTrackers(from magnetLinks: [String]) -> Set<String> {
        var trackers = Set<String>()
        for magnet in magnetLinks {
            // Parse &tr= parameters
            let components = magnet.components(separatedBy: "&")
            for comp in components {
                if comp.hasPrefix("tr=") || comp.hasPrefix("TR=") {
                    let encoded = String(comp.dropFirst(3))
                    let url = encoded.removingPercentEncoding ?? encoded
                    if url.lowercased().hasPrefix("udp://") {
                        trackers.insert(url)
                    }
                }
            }
        }
        return trackers
    }

    /// Parse a UDP tracker URL into (host, port).
    /// e.g. "udp://tracker.opentrackr.org:1337" → ("tracker.opentrackr.org", 1337)
    private static func parseUDPURL(_ url: String) -> (host: String, port: UInt16)? {
        var cleaned = url
        if cleaned.lowercased().hasPrefix("udp://") {
            cleaned = String(cleaned.dropFirst(6))
        }
        // Remove path (e.g. /announce)
        if let slashIdx = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[..<slashIdx])
        }
        // Split host:port
        guard let colonIdx = cleaned.lastIndex(of: ":") else { return nil }
        let host = String(cleaned[..<colonIdx])
        let portStr = String(cleaned[cleaned.index(after: colonIdx)...])
        guard let port = UInt16(portStr), !host.isEmpty else { return nil }
        return (host, port)
    }
}

// MARK: - Data helpers

private extension Data {
    /// Initialize from a hex-encoded string ("abcdef01..." → Data bytes).
    init?(hexString: String) {
        let hex = hexString.lowercased()
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }

    /// Read a big-endian UInt32 at the given byte offset.
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    /// Read a big-endian UInt64 at the given byte offset.
    func readUInt64(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        return subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
    }

    /// Append a big-endian UInt32.
    mutating func appendUInt32(_ value: UInt32) {
        var be = value.bigEndian
        append(Data(bytes: &be, count: 4))
    }

    /// Append a big-endian UInt64.
    mutating func appendUInt64(_ value: UInt64) {
        var be = value.bigEndian
        append(Data(bytes: &be, count: 8))
    }
}
