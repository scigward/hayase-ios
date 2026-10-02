//
//  StreamingLogger.swift
//  Hayase
//
//  A lightweight in-app logger that captures streaming, torrent, and player
//  errors/warnings for export from the debug page. Older entries are evicted
//  when the maximum capacity is reached.
//

import Foundation

// MARK: - Log entry model

/// A single log entry with timestamp, severity, and message.
struct StreamingLogEntry {
    enum Level: String {
        case info  = "INFO"
        case warn  = "WARN"
        case error = "ERROR"
    }

    let timestamp: Date
    let level: Level
    let message: String

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }

    var displayString: String {
        "[\(formattedTime)] \(level.rawValue): \(message)"
    }
}

// MARK: - StreamingLogger

/// Thread-safe singleton logger that captures streaming/torrent/player events.
final class StreamingLogger {

    static let shared = StreamingLogger()

    /// Maximum number of retained entries. Oldest are evicted first.
    private let maxEntries = 200

    /// Thread-safe storage.
    private let lock = NSLock()
    private var _entries: [StreamingLogEntry] = []

    /// Current snapshot of all entries (newest last).
    var entries: [StreamingLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    private init() {}

    // MARK: - Public API

    func info(_ message: String) {
        append(.init(timestamp: Date(), level: .info, message: message))
    }

    func warn(_ message: String) {
        append(.init(timestamp: Date(), level: .warn, message: message))
    }

    func error(_ message: String) {
        append(.init(timestamp: Date(), level: .error, message: message))
    }

    func clear() {
        lock.lock()
        _entries.removeAll()
        lock.unlock()
    }

    /// Log text for sharing. Query strings, credentials in URLs and a magnet link's trackers
    /// are removed, since indexer and tracker URLs commonly carry passkeys and API keys.
    func exportText() -> String {
        let text = entries.map(\.displayString).joined(separator: "\n")
        // a pattern that failed to compile must not turn into an export that leaks what it should remove
        guard Self.redactions.count == Self.redactionPatterns.count else { return "" }
        return Self.redactions.reduce(text) { partial, redaction in
            redaction.pattern.stringByReplacingMatches(in: partial, range: NSRange(partial.startIndex..., in: partial),
                                                       withTemplate: redaction.template)
        }
    }

    private static let redactionPatterns: [(pattern: String, template: String)] = [
        (#"(magnet:\?)[^\s"'<>]*?(xt=urn:bt(?:ih|mh):[0-9A-Za-z]+)[^\s"'<>]*"#, "$1$2&…"),
        (#"(https?://)[^\s/@"'<>]+@"#, "$1"),
        (#"(https?://[^\s"'<>?#]*)\?[^\s"'<>]*"#, "$1?…"),
    ]

    private static let redactions: [(pattern: NSRegularExpression, template: String)] = redactionPatterns.compactMap { entry in
        (try? NSRegularExpression(pattern: entry.pattern)).map { (pattern: $0, template: entry.template) }
    }

    // MARK: - Private

    private func append(_ entry: StreamingLogEntry) {
        lock.lock()
        _entries.append(entry)
        if _entries.count > maxEntries {
            _entries.removeFirst(_entries.count - maxEntries)
        }
        lock.unlock()
    }
}
