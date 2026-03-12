//
//  TorrentStreamer.swift
//  TheAnimeTool
//

import Foundation
import LibTorrent

/// Manages torrent-based video streaming for a single file within a torrent.
///
/// Follows the Hayase streaming model — only downloads the data directly
/// needed for playback, down to the minute:
/// - Pure deadline-based piece management (no sequential download)
/// - Small buffer window: a few seconds of critical pieces + minimal look-ahead
/// - Stops requesting once the buffer is filled
/// - Resets deadlines for pieces outside the active window to save bandwidth
/// - Reduces strain on the peer swarm by requesting only what's needed
final class TorrentStreamer {

    // MARK: - Notifications

    static let bufferDidUpdate = Notification.Name("TorrentStreamerBufferDidUpdate")

    // MARK: - Configuration

    /// Target buffer in seconds of video. Once we have this many seconds
    /// buffered ahead we stop requesting more pieces.
    private let targetBufferSeconds: Double = 15.0

    /// Number of critical pieces to request with tight deadlines (immediate need).
    /// Kept small so we only fetch what's needed for the next few seconds.
    private let criticalPieceCount = 8

    /// Number of look-ahead pieces with relaxed deadlines. Together with the
    /// critical pieces this covers roughly `targetBufferSeconds` of video.
    private let lookAheadPieceCount = 12

    /// Deadline in milliseconds for the very first critical piece.
    private let criticalDeadlineBase: Int32 = 50

    /// Deadline step per piece in the critical range (ms).
    private let criticalDeadlineStep: Int32 = 150

    /// Deadline in milliseconds for the first look-ahead piece.
    private let lookAheadDeadlineBase: Int32 = 3000

    /// Deadline step per piece in the look-ahead range (ms).
    private let lookAheadDeadlineStep: Int32 = 500

    /// Minimum piece distance before we re-evaluate deadlines. Prevents
    /// excessive libtorrent calls when playback advances smoothly.
    private let minPieceUpdateDistance = 3

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

    /// Range of pieces that currently have active deadlines, so we can
    /// reset exactly those when the window moves.
    private var activeWindowStart: Int = -1
    private var activeWindowEnd: Int = -1

    /// Whether streaming has been set up.
    private(set) var isActive: Bool = false

    // MARK: - Init

    init(torrentHandle: TorrentHandle, fileIndex: UInt) {
        self.torrentHandle = torrentHandle
        self.fileIndex = Int(fileIndex)
    }

    // MARK: - Setup

    /// Reads file piece boundaries and sets aggressive deadlines on the
    /// first pieces so playback can start quickly.
    /// Sequential download is NOT used — we rely purely on piece deadlines
    /// so libtorrent only fetches the narrow window we request.
    func start() {
        guard !isActive else { return }
        isActive = true

        torrentHandle.updateSnapshot()
        guard let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }) else {
            print("TorrentStreamer: file index \(fileIndex) not found in snapshot")
            return
        }

        beginPiece = Int(entry.begin_idx)
        endPiece = Int(entry.end_idx)
        totalFilePieces = Int(entry.num_pieces)

        // Disable sequential download — deadline-based management is more
        // bandwidth-efficient because it only fetches the narrow buffer window.
        torrentHandle.setSequentialDownload(false)

        print("TorrentStreamer: start file=\(fileIndex) pieces=\(beginPiece)–\(endPiece) (\(totalFilePieces) total)")

        // Kick-start: request the first few pieces for fast playback start.
        setDeadlinesFrom(pieceIndex: beginPiece, force: true)
    }

    /// Stops streaming management and resets all outstanding deadlines.
    func stop() {
        guard isActive else { return }
        isActive = false
        resetActiveWindow()
        lastDeadlinePiece = -1
        print("TorrentStreamer: stopped")
    }

    // MARK: - Playback position update

    /// Called by the player as playback progresses. `fraction` is 0.0–1.0
    /// representing the current playback position within the video duration.
    func updatePlaybackPosition(fraction: Double, videoDuration: Double = 0) {
        guard isActive, totalFilePieces > 0 else { return }

        let clampedFraction = max(0, min(1, fraction))
        let currentPiece = beginPiece + Int(clampedFraction * Double(totalFilePieces))

        // If we already have enough buffer ahead, skip requesting more.
        if videoDuration > 0 {
            let bufSec = bufferedSeconds(fromFraction: clampedFraction, videoDuration: videoDuration)
            if bufSec >= targetBufferSeconds && lastDeadlinePiece >= 0 {
                return
            }
        }

        // Only update deadlines when the playback front has moved at least
        // minPieceUpdateDistance pieces since the last update.
        if lastDeadlinePiece >= 0 && abs(currentPiece - lastDeadlinePiece) < minPieceUpdateDistance {
            return
        }

        setDeadlinesFrom(pieceIndex: currentPiece)
    }

    /// Called when the user seeks to a new position. Always forces a deadline update.
    func seekTo(fraction: Double) {
        guard isActive, totalFilePieces > 0 else { return }

        let clampedFraction = max(0, min(1, fraction))
        let targetPiece = beginPiece + Int(clampedFraction * Double(totalFilePieces))

        // Force-update: reset the old window and request pieces around the seek target.
        setDeadlinesFrom(pieceIndex: targetPiece, force: true)
    }

    // MARK: - Buffer metrics

    /// Returns the number of consecutive pieces that are downloaded starting from
    /// the piece at `fraction` of the file.
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

    /// Sets piece deadlines for a narrow window starting at `pieceIndex`:
    /// - Critical pieces: tight deadlines for immediate playback need
    /// - Look-ahead pieces: relaxed deadlines for short-term buffer
    /// Pieces outside this window have their deadlines reset so libtorrent
    /// does not waste bandwidth fetching data far from playback.
    private func setDeadlinesFrom(pieceIndex: Int, force: Bool = false) {
        let start = max(pieceIndex, beginPiece)

        if !force && start == lastDeadlinePiece { return }
        lastDeadlinePiece = start

        // Reset deadlines for pieces that are no longer in the active window.
        resetActiveWindow()

        let totalWindow = criticalPieceCount + lookAheadPieceCount
        let windowEnd = min(start + totalWindow - 1, endPiece)

        // Critical buffer: pieces needed in the next few seconds of playback.
        for i in 0..<criticalPieceCount {
            let piece = start + i
            guard piece <= endPiece else { break }
            let deadline = criticalDeadlineBase + Int32(i) * criticalDeadlineStep
            torrentHandle.setPieceDeadline(piece, deadline: deadline)
        }

        // Look-ahead buffer: pieces needed in the near future.
        for i in criticalPieceCount..<totalWindow {
            let piece = start + i
            guard piece <= endPiece else { break }
            let deadline = lookAheadDeadlineBase + Int32(i - criticalPieceCount) * lookAheadDeadlineStep
            torrentHandle.setPieceDeadline(piece, deadline: deadline)
        }

        activeWindowStart = start
        activeWindowEnd = windowEnd
    }

    /// Resets piece deadlines for the previous active window so libtorrent stops
    /// prioritizing those pieces. This is critical for the Hayase approach:
    /// pieces behind playback or beyond the buffer window should not consume bandwidth.
    private func resetActiveWindow() {
        guard activeWindowStart >= 0, activeWindowEnd >= activeWindowStart else { return }
        for piece in activeWindowStart...activeWindowEnd {
            torrentHandle.resetPieceDeadline(piece)
        }
        activeWindowStart = -1
        activeWindowEnd = -1
    }
}
