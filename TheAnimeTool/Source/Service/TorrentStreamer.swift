//
//  TorrentStreamer.swift
//  TheAnimeTool
//

import Foundation
import LibTorrent

/// Manages torrent-based video streaming for a single file within a torrent.
///
/// Follows the Hayase streaming model:
/// - Sequential piece downloading from the file's beginning
/// - Piece deadline management to prioritize pieces near playback position
/// - Buffer tracking ahead of the current playback position
/// - Aggressive initial buffering before playback begins
final class TorrentStreamer {

    // MARK: - Notifications

    static let BufferDidUpdateNotification = "TorrentStreamerBufferDidUpdateNotification"

    // MARK: - Configuration

    /// Number of pieces to set with tight deadlines (critical buffer — needed immediately).
    private let criticalPieceCount = 20

    /// Number of pieces to set with relaxed deadlines (look-ahead buffer).
    private let highPriorityPieceCount = 80

    /// Deadline in milliseconds for the very first critical piece.
    private let criticalDeadlineBase: Int32 = 50

    /// Deadline step per piece in the critical range (ms).
    private let criticalDeadlineStep: Int32 = 100

    /// Deadline in milliseconds for the first high-priority piece.
    private let highPriorityDeadlineBase: Int32 = 5000

    /// Deadline step per piece in the high-priority range (ms).
    private let highPriorityDeadlineStep: Int32 = 500

    // MARK: - State

    private let torrentHandle: TorrentHandle
    private let fileIndex: Int

    /// First piece index belonging to the target file.
    private(set) var beginPiece: Int = 0

    /// Last piece index belonging to the target file.
    private(set) var endPiece: Int = 0

    /// Total number of pieces for the target file.
    private(set) var totalFilePieces: Int = 0

    /// The last piece index for which deadlines were set (avoids redundant work).
    private var lastDeadlinePiece: Int = -1

    /// Whether streaming has been set up.
    private(set) var isActive: Bool = false

    // MARK: - Init

    init(torrentHandle: TorrentHandle, fileIndex: UInt) {
        self.torrentHandle = torrentHandle
        self.fileIndex = Int(fileIndex)
    }

    // MARK: - Setup

    /// Enables sequential download, reads file piece boundaries, and
    /// sets aggressive deadlines on the first pieces so playback can start quickly.
    func start() {
        guard !isActive else { return }
        isActive = true

        // Enable sequential piece picking so libtorrent fetches pieces in order.
        torrentHandle.setSequentialDownload(true)

        // Read piece range from the snapshot's file entry.
        torrentHandle.updateSnapshot()
        guard let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }) else {
            print("TorrentStreamer: file index \(fileIndex) not found in snapshot")
            return
        }

        beginPiece = Int(entry.begin_idx)
        endPiece = Int(entry.end_idx)
        totalFilePieces = Int(entry.num_pieces)

        print("TorrentStreamer: start file=\(fileIndex) pieces=\(beginPiece)–\(endPiece) (\(totalFilePieces) total)")

        // Set deadlines on the first pieces for a fast startup.
        setDeadlinesFrom(pieceIndex: beginPiece)
    }

    /// Stops streaming management and disables sequential download.
    func stop() {
        guard isActive else { return }
        isActive = false
        torrentHandle.setSequentialDownload(false)
        lastDeadlinePiece = -1
        print("TorrentStreamer: stopped")
    }

    // MARK: - Playback position update

    /// Called by the player as playback progresses. `fraction` is 0.0–1.0 representing
    /// the current playback position within the video duration.
    func updatePlaybackPosition(fraction: Double) {
        guard isActive, totalFilePieces > 0 else { return }

        let clampedFraction = max(0, min(1, fraction))
        let currentPiece = beginPiece + Int(clampedFraction * Double(totalFilePieces))

        // Only update deadlines when the playback front has moved at least 5 pieces
        // since the last update to avoid excessive libtorrent calls.
        if lastDeadlinePiece >= 0 && abs(currentPiece - lastDeadlinePiece) < 5 {
            return
        }

        setDeadlinesFrom(pieceIndex: currentPiece)
    }

    /// Called when the user seeks to a new position. Always forces a deadline update.
    func seekTo(fraction: Double) {
        guard isActive, totalFilePieces > 0 else { return }

        let clampedFraction = max(0, min(1, fraction))
        let targetPiece = beginPiece + Int(clampedFraction * Double(totalFilePieces))

        // Force-update deadlines regardless of distance from last update.
        lastDeadlinePiece = -1
        setDeadlinesFrom(pieceIndex: targetPiece)
    }

    // MARK: - Buffer metrics

    /// Returns the number of consecutive pieces that are downloaded starting from
    /// the piece at `fraction` of the file. This represents how far ahead the buffer extends.
    func consecutiveBufferedPieces(fromFraction fraction: Double) -> Int {
        guard isActive, totalFilePieces > 0 else { return 0 }

        torrentHandle.updateSnapshot()
        guard let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }),
              let pieces = entry.pieces as? [NSNumber] else { return 0 }

        let clampedFraction = max(0, min(1, fraction))
        let startLocal = Int(clampedFraction * Double(totalFilePieces))

        var count = 0
        for i in startLocal..<pieces.count {
            if pieces[i].boolValue {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    /// Returns an estimated number of seconds of buffered video ahead of the current position.
    /// Requires the video duration (from MPV) for an accurate estimate.
    func bufferedSeconds(fromFraction fraction: Double, videoDuration: Double) -> Double {
        guard totalFilePieces > 0, videoDuration > 0 else { return 0 }
        let pieces = consecutiveBufferedPieces(fromFraction: fraction)
        let secondsPerPiece = videoDuration / Double(totalFilePieces)
        return Double(pieces) * secondsPerPiece
    }

    /// Returns the fraction (0–1) of the file that has been downloaded.
    func downloadedFraction() -> Double {
        guard isActive, totalFilePieces > 0 else { return 0 }

        torrentHandle.updateSnapshot()
        guard let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }) else { return 0 }
        return entry.size > 0 ? Double(entry.downloaded) / Double(entry.size) : 0
    }

    // MARK: - Private

    /// Sets piece deadlines from `pieceIndex` onwards:
    /// - Critical pieces (the next `criticalPieceCount`): tight deadlines
    /// - High-priority pieces (next `highPriorityPieceCount`): relaxed deadlines
    private func setDeadlinesFrom(pieceIndex: Int) {
        let start = max(pieceIndex, beginPiece)
        lastDeadlinePiece = start

        // Critical buffer: pieces needed in the next ~10 seconds of playback.
        for i in 0..<criticalPieceCount {
            let piece = start + i
            guard piece <= endPiece else { break }
            let deadline = criticalDeadlineBase + Int32(i) * criticalDeadlineStep
            torrentHandle.setPieceDeadline(piece, deadline: deadline)
        }

        // High-priority buffer: pieces needed in the next ~30–60 seconds.
        for i in criticalPieceCount..<(criticalPieceCount + highPriorityPieceCount) {
            let piece = start + i
            guard piece <= endPiece else { break }
            let deadline = highPriorityDeadlineBase + Int32(i - criticalPieceCount) * highPriorityDeadlineStep
            torrentHandle.setPieceDeadline(piece, deadline: deadline)
        }
    }
}
