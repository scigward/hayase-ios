//
//  ParseTorrent.swift
//  Hayase
//
//  Mirrors: what lib/modules/torrent/client.ts `playIdentifier` and SearchModal.svelte take from the
//  `parse-torrent` package: the info hash of a magnet link, of a hash, and of the bytes of a `.torrent` file.
//

import CryptoKit
import Foundation

enum ParseTorrent {
    /// SearchModal.svelte `torrentRx`: what the filter field, a paste or a drop is taken to name a torrent by.
    static func isIdentifier(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        let pattern = #"(^magnet:)|(^[A-F\d]{8,40}$)|(.*\.torrent$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: text, range: range) != nil
    }

    // MARK: - Magnet links and hashes

    /// The info hash of a magnet link: `xt=urn:btih:` followed by 40 hex digits or 32 base32 characters.
    static func infoHash(magnet: String) -> String? {
        guard magnet.lowercased().hasPrefix("magnet:"), let question = magnet.firstIndex(of: "?") else { return nil }
        for pair in magnet[magnet.index(after: question)...].split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0] == "xt" else { continue }
            let value = parts[1].removingPercentEncoding ?? parts[1]
            guard value.lowercased().hasPrefix("urn:btih:") else { continue }
            return infoHash(hash: String(value.dropFirst("urn:btih:".count)))
        }
        return nil
    }

    /// A hash in the form a torrent knows it by: 40 hex digits, or 32 base32 characters, as lower case hex.
    static func infoHash(hash: String) -> String? {
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        if hash.count == 40, hash.unicodeScalars.allSatisfy({ hex.contains($0) }) { return hash.lowercased() }
        if hash.count == 32 { return hexFromBase32(hash) }
        return nil
    }

    private static func hexFromBase32(_ text: String) -> String? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits = 0
        var value = 0
        var bytes: [UInt8] = []
        for character in text.uppercased() {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((value >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        guard bytes.count == 20 else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - .torrent files

    /// The info hash of the bytes of a `.torrent` file: the SHA-1 of its bencoded `info` dictionary, as it
    /// is written in the file.
    static func infoHash(file data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.first == UInt8(ascii: "d") else { return nil }
        var index = 1
        while index < bytes.count, bytes[index] != UInt8(ascii: "e") {
            guard let keyEnd = skipString(bytes, at: index),
                  let key = string(bytes, from: index, to: keyEnd) else { return nil }
            index = keyEnd
            guard let valueEnd = skipValue(bytes, at: index) else { return nil }
            if key == "info" {
                let digest = Insecure.SHA1.hash(data: Data(bytes[index..<valueEnd]))
                return digest.map { String(format: "%02x", $0) }.joined()
            }
            index = valueEnd
        }
        return nil
    }

    /// The end of the bencoded value that starts at `start`.
    private static func skipValue(_ bytes: [UInt8], at start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        switch bytes[start] {
        case UInt8(ascii: "i"):
            guard let end = bytes[start...].firstIndex(of: UInt8(ascii: "e")) else { return nil }
            return end + 1
        case UInt8(ascii: "l"):
            var index = start + 1
            while index < bytes.count, bytes[index] != UInt8(ascii: "e") {
                guard let next = skipValue(bytes, at: index) else { return nil }
                index = next
            }
            return index < bytes.count ? index + 1 : nil
        case UInt8(ascii: "d"):
            var index = start + 1
            while index < bytes.count, bytes[index] != UInt8(ascii: "e") {
                guard let keyEnd = skipString(bytes, at: index), let next = skipValue(bytes, at: keyEnd) else { return nil }
                index = next
            }
            return index < bytes.count ? index + 1 : nil
        default:
            return skipString(bytes, at: start)
        }
    }

    /// The end of the bencoded string `<length>:<bytes>` that starts at `start`.
    private static func skipString(_ bytes: [UInt8], at start: Int) -> Int? {
        guard let colon = bytes[start...].firstIndex(of: UInt8(ascii: ":")),
              let length = Int(String(decoding: bytes[start..<colon], as: UTF8.self)), length >= 0,
              colon + 1 + length <= bytes.count else { return nil }
        return colon + 1 + length
    }

    private static func string(_ bytes: [UInt8], from start: Int, to end: Int) -> String? {
        guard let colon = bytes[start..<end].firstIndex(of: UInt8(ascii: ":")) else { return nil }
        return String(decoding: bytes[(colon + 1)..<end], as: UTF8.self)
    }
}
