//
//  AniListOperationCache.swift
//  Hayase
//
//  Persistent AniList operation cache.
//  Mirrors: src/lib/modules/anilist/exchanges/defaultstorage.ts.
//

import CryptoKit
import Foundation

final class AniListOperationCache {
    static let shared = AniListOperationCache()

    private struct Entry: Codable {
        let storedAt: Date
        let data: Data
    }

    private let maxAge: TimeInterval = 21 * 24 * 60 * 60
    private let queue = DispatchQueue(label: "com.hayase.anilist.operationCache")
    private let directory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directory = caches.appendingPathComponent("AniListOperationCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cachedData(for key: String) -> Data? {
        queue.sync {
            guard let entry = readEntry(for: key) else { return nil }
            guard Date().timeIntervalSince(entry.storedAt) <= maxAge else {
                removeEntry(for: key)
                return nil
            }
            return entry.data
        }
    }

    func store(data: Data, for key: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let entry = Entry(storedAt: Date(), data: data)
            guard let encoded = try? JSONEncoder().encode(entry) else { return }
            try? encoded.write(to: self.fileURL(for: key), options: [.atomic])
        }
    }

    func purgeStaleEntries() {
        queue.async { [weak self] in
            guard let self else { return }
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in urls {
                guard let data = try? Data(contentsOf: url),
                      let entry = try? JSONDecoder().decode(Entry.self, from: data),
                      Date().timeIntervalSince(entry.storedAt) > maxAge else { continue }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func clearViewerScopedEntries() {
        queue.async { [weak self] in
            guard let self else { return }
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    private func readEntry(for key: String) -> Entry? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    private func removeEntry(for key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    private func fileURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("json")
    }
}
