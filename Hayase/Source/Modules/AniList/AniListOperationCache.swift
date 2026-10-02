//
//  AniListOperationCache.swift
//  Hayase
//
//  Persistent AniList operation cache.
//  Mirrors: src/lib/modules/anilist/exchanges/defaultstorage.ts.
//

import CryptoKit
import Foundation

/// An answer per file, the answer itself: how old it is, is how old the file is. Nothing has to be
/// opened to know that, which `purgeStaleEntries` (run after every answer, as the interface runs it)
/// would otherwise do for every file there is, megabytes of JSON each.
final class AniListOperationCache {
    static let shared = AniListOperationCache()

    private let maxAge: TimeInterval = 21 * 24 * 60 * 60
    /// The most the answers may take on disk; the oldest go first, down to three quarters of it.
    private let maxBytes = 160 * 1024 * 1024
    private let queue = DispatchQueue(label: "com.hayase.anilist.operationCache", qos: .utility)
    private let directory: URL
    private var lastPurge = Date.distantPast

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directory = caches.appendingPathComponent("AniListOperationCache-v2", isDirectory: true)
        // the first format wrapped every answer in JSON of its own, and was read whole to tell its age
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("AniListOperationCache", isDirectory: true))
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The answer stored for `key`, if it is not older than `maxAge` (21 days when there is none).
    func cachedData(for key: String, maxAge limit: TimeInterval? = nil) -> Data? {
        queue.sync {
            let url = fileURL(for: key)
            guard let stored = modificationDate(of: url) else { return nil }
            let age = Date().timeIntervalSince(stored)
            guard age <= maxAge else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            if let limit, age > limit { return nil }
            return try? Data(contentsOf: url)
        }
    }

    func store(data: Data, for key: String) {
        queue.async { [weak self] in
            guard let self else { return }
            try? data.write(to: self.fileURL(for: key), options: [.atomic])
        }
    }

    /// `storage.purgeStaleEntries()`: what is older than 21 days goes, and the oldest of the rest when
    /// the answers take too much room. Looked at once a minute at most, by the files' own dates.
    func purgeStaleEntries() {
        queue.async { [weak self] in
            guard let self, Date().timeIntervalSince(self.lastPurge) > 60 else { return }
            self.lastPurge = Date()
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
            let urls = (try? FileManager.default.contentsOfDirectory(at: self.directory,
                                                                     includingPropertiesForKeys: keys)) ?? []
            var kept: [(url: URL, modified: Date, size: Int)] = []
            for url in urls {
                let values = try? url.resourceValues(forKeys: Set(keys))
                let modified = values?.contentModificationDate ?? .distantPast
                if Date().timeIntervalSince(modified) > self.maxAge {
                    try? FileManager.default.removeItem(at: url)
                } else {
                    kept.append((url, modified, values?.fileSize ?? 0))
                }
            }
            var total = kept.reduce(0) { $0 + $1.size }
            guard total > self.maxBytes else { return }
            for entry in kept.sorted(by: { $0.modified < $1.modified }) where total > self.maxBytes / 4 * 3 {
                try? FileManager.default.removeItem(at: entry.url)
                total -= entry.size
            }
        }
    }

    func clearViewerScopedEntries() {
        queue.async { [weak self] in
            guard let self else { return }
            let urls = (try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)) ?? []
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func fileURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("json")
    }
}
