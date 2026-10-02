//
//  TrackerScrapeService.swift
//  Hayase
//
//  Implements HTTP tracker scrape protocol to fetch live peer counts
//  (seeders/leechers/completed) for info-hashes.
//
//  Mirrors web's `native.updatePeerCounts(hashes)` which calls
//  `torrentClient.scrape(hashes)` in hayase-app/torrent-client.
//  The web uses HTTP tracker scraping via nyaa.tracker.wf:7777/scrape
//  with bencoded responses, batching hashes to stay under URL length limits.
//
//  References:
//  - BEP 48: https://www.bittorrent.org/beps/bep_0048.html (HTTP scrape)
//  - torrent-client/index.ts: `scrape()` in hayase-app/torrent-client

import Foundation

/// Result of a tracker scrape for a single info-hash.
struct ScrapeResult {
    let hash: String      // hex-encoded info-hash
    let complete: Int      // seeders
    let downloaded: Int    // completed downloads
    let incomplete: Int    // leechers
}

/// HTTP tracker scrape service.
///
/// Mirrors the web's torrent-client scrape implementation exactly:
/// - Uses the same HTTP tracker (nyaa.tracker.wf:7777)
/// - Batches hashes to stay under MAX_ANNOUNCE_LENGTH (1300 bytes)
/// - Rate-limits between batches (200ms)
/// - Parses bencoded scrape responses
///
/// Usage:
/// ```
/// let results = await TrackerScrapeService.scrape(hashes: ["abcdef1234...", ...])
/// ```
final class TrackerScrapeService {

    // MARK: - Constants (matching web torrent-client)

    /// Base scrape URL — derived from the web's announce URL
    /// `http://nyaa.tracker.wf:7777/announce` → `/scrape`
    private static let scrapeBaseURL = "http://nyaa.tracker.wf:7777/scrape"

    /// Maximum URL length for a single scrape request (web: MAX_ANNOUNCE_LENGTH = 1300)
    private static let maxAnnounceLength = 1300

    /// Rate limit between batch requests in seconds (web: RATE_LIMIT = 200ms)
    private static let rateLimitSeconds: TimeInterval = 0.2

    // MARK: - Public API

    /// Scrape peer counts for the given info-hashes.
    ///
    /// - Parameter hashes: Hex-encoded v1 info-hashes (40 chars each).
    /// - Returns: Scrape results for each hash that was successfully scraped.
    static func scrape(hashes: [String]) async -> [ScrapeResult] {
        guard !hashes.isEmpty else { return [] }

        // Convert hex hashes to binary and URL-encode them (matching web's hex2bin + querystringStringify)
        let binaryHashes: [(hex: String, encoded: String)] = hashes.compactMap { hex in
            guard let raw = hexToRawBytes(hex), raw.count == 20 else { return nil }
            return (hex, urlEncodeInfoHash(raw))
        }
        guard !binaryHashes.isEmpty else { return [] }

        // Shuffle to distribute load (matching web: infoHashes.sort(() => 0.5 - Math.random()))
        let shuffled = binaryHashes.shuffled()

        // Batch hashes to stay under URL length limit (matching web batching logic)
        var results: [ScrapeResult] = []
        var batch: [(hex: String, encoded: String)] = []
        var currentLength = scrapeBaseURL.count

        for hashPair in shuffled {
            // Each info_hash param adds: "&info_hash=" (11 chars) + encoded hash
            let paramLength = (batch.isEmpty ? "?info_hash=".count : "&info_hash=".count) + hashPair.encoded.count

            if currentLength + paramLength > maxAnnounceLength && !batch.isEmpty {
                // Scrape current batch
                if !results.isEmpty {
                    try? await Task.sleep(nanoseconds: UInt64(rateLimitSeconds * 1_000_000_000))
                }
                let batchResults = await scrapeBatch(batch)
                results.append(contentsOf: batchResults)
                batch = []
                currentLength = scrapeBaseURL.count
            }

            batch.append(hashPair)
            currentLength += paramLength
        }

        // Scrape remaining batch
        if !batch.isEmpty {
            if !results.isEmpty {
                try? await Task.sleep(nanoseconds: UInt64(rateLimitSeconds * 1_000_000_000))
            }
            let batchResults = await scrapeBatch(batch)
            results.append(contentsOf: batchResults)
        }

        return results
    }

    // MARK: - HTTP Scrape

    /// Scrape a batch of hashes from the HTTP tracker.
    private static func scrapeBatch(_ batch: [(hex: String, encoded: String)]) async -> [ScrapeResult] {
        // Build scrape URL with info_hash query parameters
        let queryParams = batch.map { "info_hash=\($0.encoded)" }.joined(separator: "&")
        let urlString = "\(scrapeBaseURL)?\(queryParams)"

        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }

            return parseScrapeResponse(data, batch: batch)
        } catch {
            return []
        }
    }

    // MARK: - Bencode parsing

    /// Parse a bencoded scrape response.
    ///
    /// Response format: `d5:filesd<20-byte-hash>d8:completei<N>e10:downloadedi<N>e10:incompletei<N>eeee`
    private static func parseScrapeResponse(_ data: Data, batch: [(hex: String, encoded: String)]) -> [ScrapeResult] {
        guard let parsed = bencodeDecode(data),
              let root = parsed as? [Data: Any],
              let files = root[Data("files".utf8)] as? [Data: Any] else {
            return []
        }

        // Build a lookup from raw 20-byte hash → hex string
        var rawToHex: [Data: String] = [:]
        for pair in batch {
            if let raw = hexToRawBytes(pair.hex) {
                rawToHex[raw] = pair.hex
            }
        }

        var results: [ScrapeResult] = []
        for (key, value) in files {
            guard let stats = value as? [Data: Any] else { continue }

            // The key is the raw 20-byte info-hash
            let hex: String
            if key.count == 20, let h = rawToHex[key] {
                hex = h
            } else if key.count == 40 {
                // Sometimes returned as hex string
                hex = String(data: key, encoding: .utf8) ?? ""
            } else {
                continue
            }

            guard !hex.isEmpty else { continue }

            let complete   = bencodeInt(stats[Data("complete".utf8)])
            let downloaded = bencodeInt(stats[Data("downloaded".utf8)])
            let incomplete = bencodeInt(stats[Data("incomplete".utf8)])

            results.append(ScrapeResult(
                hash: hex.lowercased(),
                complete: complete,
                downloaded: downloaded,
                incomplete: incomplete
            ))
        }

        return results
    }

    /// Extract an integer from a bencoded value (may be Int or String).
    private static func bencodeInt(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let s = value as? String, let i = Int(s) { return i }
        return 0
    }

    // MARK: - Bencode decoder

    /// Minimal bencoded data decoder.
    /// Supports: integers (i<N>e), byte strings (<len>:<data>), lists (l...e), dicts (d...e).
    /// Dict keys are Data (raw bytes), values can be Int, Data, [Any], or [Data: Any].
    private static func bencodeDecode(_ data: Data) -> Any? {
        var index = data.startIndex
        return bencodeParse(data, index: &index, depth: 0)
    }

    /// A reply nested deeper than this is not a scrape reply; parsing it recursively would only
    /// run the stack out on a tracker that sends `llll…`.
    private static let maxBencodeDepth = 32

    private static func bencodeParse(_ data: Data, index: inout Data.Index, depth: Int) -> Any? {
        guard index < data.endIndex, depth <= maxBencodeDepth else { return nil }

        let byte = data[index]

        if byte == UInt8(ascii: "i") {
            // Integer: i<number>e
            index = data.index(after: index)
            return bencodeParseInt(data, index: &index)
        } else if byte == UInt8(ascii: "l") {
            // List: l<items>e
            index = data.index(after: index)
            var list: [Any] = []
            while index < data.endIndex && data[index] != UInt8(ascii: "e") {
                if let item = bencodeParse(data, index: &index, depth: depth + 1) {
                    list.append(item)
                } else {
                    return nil
                }
            }
            if index < data.endIndex { index = data.index(after: index) } // skip 'e'
            return list
        } else if byte == UInt8(ascii: "d") {
            // Dictionary: d<key><value>...e
            index = data.index(after: index)
            var dict: [Data: Any] = [:]
            while index < data.endIndex && data[index] != UInt8(ascii: "e") {
                guard let key = bencodeParse(data, index: &index, depth: depth + 1) as? Data,
                      let value = bencodeParse(data, index: &index, depth: depth + 1) else {
                    return nil
                }
                dict[key] = value
            }
            if index < data.endIndex { index = data.index(after: index) } // skip 'e'
            return dict
        } else if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
            // Byte string: <length>:<data>
            return bencodeParseString(data, index: &index)
        }

        return nil
    }

    private static func bencodeParseInt(_ data: Data, index: inout Data.Index) -> Int? {
        var numStr = ""
        while index < data.endIndex && data[index] != UInt8(ascii: "e") {
            numStr.append(Character(UnicodeScalar(data[index])))
            index = data.index(after: index)
        }
        if index < data.endIndex { index = data.index(after: index) } // skip 'e'
        return Int(numStr)
    }

    private static func bencodeParseString(_ data: Data, index: inout Data.Index) -> Data? {
        var lenStr = ""
        while index < data.endIndex && data[index] != UInt8(ascii: ":") {
            lenStr.append(Character(UnicodeScalar(data[index])))
            index = data.index(after: index)
        }
        guard let length = Int(lenStr), length >= 0 else { return nil }
        if index < data.endIndex { index = data.index(after: index) } // skip ':'
        let end = data.index(index, offsetBy: length, limitedBy: data.endIndex) ?? data.endIndex
        let result = data[index..<end]
        index = end
        return Data(result)
    }

    // MARK: - Hash encoding helpers

    /// Convert a hex string to raw bytes.
    private static func hexToRawBytes(_ hex: String) -> Data? {
        let hex = hex.lowercased()
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let next = hex.index(i, offsetBy: 2)
            guard let byte = UInt8(hex[i..<next], radix: 16) else { return nil }
            data.append(byte)
            i = next
        }
        return data
    }

    /// URL-encode a raw 20-byte info-hash for use in HTTP tracker scrape URLs.
    ///
    /// Mirrors the web's `querystringStringify({ info_hash: hex2bin(infoHash) })`.
    /// Uses percent-encoding for all bytes except unreserved characters (RFC 3986).
    private static func urlEncodeInfoHash(_ rawHash: Data) -> String {
        // Unreserved chars that don't need encoding: A-Z a-z 0-9 - . _ ~
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var encoded = ""
        for byte in rawHash {
            let scalar = Unicode.Scalar(byte)
            if unreserved.contains(scalar) {
                encoded.append(Character(scalar))
            } else {
                encoded.append(String(format: "%%%02X", byte))
            }
        }
        return encoded
    }
}
