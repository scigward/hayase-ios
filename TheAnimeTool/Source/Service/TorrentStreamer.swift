//
//  TorrentStreamer.swift
//  TheAnimeTool
//

import Foundation
import LibTorrent

/// Manages torrent-based video streaming for a single file within a torrent.
///
/// Follows the Hayase streaming model — priority + deadline piece management:
/// - NO sequential download flag (it fights with seeking to undownloaded regions)
/// - All file pieces start at priority 0 (don't download)
/// - Active window pieces get priority > 0 THEN deadline set
/// - Critical pieces (~10s ahead of playback) get priority 7 + tight deadlines
/// - Look-ahead pieces (~60s buffer) get priority 4 + relaxed deadlines
/// - Pieces outside the window get priority 0 + deadline reset → truly stopped
/// - Tail pieces requested early for MKV Cues/SeekHead (enables seeking + subtitles)
/// - On seek: old pieces get priority 0 (stops downloading), new pieces activated
///   → all bandwidth immediately shifts to the new position
final class TorrentStreamer {

    // MARK: - Notifications

    static let bufferDidUpdate = Notification.Name("TorrentStreamerBufferDidUpdate")

    // MARK: - Configuration

    /// Target ongoing buffer in seconds of video.
    /// Hayase: "Maintains 30-60 seconds or more ahead of playback"
    private let targetBufferSeconds: Double = 60.0

    /// Critical buffer in seconds — pieces needed RIGHT NOW for playback.
    /// Hayase: "Critical (immediate): Pieces needed in next 10 seconds"
    private let criticalBufferSeconds: Double = 10.0

    /// Minimum number of critical pieces (floor when video duration is unknown).
    private let minCriticalPieces = 8

    /// Minimum total buffer pieces (critical + look-ahead floor).
    private let minBufferPieces = 30

    /// Deadline in milliseconds for the very first critical piece.
    private let criticalDeadlineBase: Int32 = 10

    /// Deadline step per piece in the critical range (ms).
    private let criticalDeadlineStep: Int32 = 50

    /// Deadline in milliseconds for the first look-ahead piece.
    private let lookAheadDeadlineBase: Int32 = 1000

    /// Deadline step per piece in the look-ahead range (ms).
    private let lookAheadDeadlineStep: Int32 = 200

    /// Minimum piece distance before we re-evaluate deadlines. Prevents
    /// excessive libtorrent calls when playback advances smoothly.
    private let minPieceUpdateDistance = 3

    // -- Seek-specific settings --

    /// Number of critical pieces to request after a seek. Enough for MPV to
    /// start decoding at the new position quickly without requesting too many
    /// pieces that would dilute per-peer request bandwidth.
    private let seekCriticalPieceCount = 12

    /// Very tight deadline base for seek operations (ms).
    private let seekDeadlineBase: Int32 = 5

    /// Deadline step per piece during seek (ms).
    private let seekDeadlineStep: Int32 = 30

    // -- Tail pieces for MKV index --

    /// Number of pieces from the END of the file to request with tight deadlines.
    /// MKV containers store Cues (seek index) and subtitle track index near the
    /// end. Without these, MPV cannot seek properly and cannot discover subtitle
    /// tracks until the file is fully downloaded.
    private let tailPieceCount = 16

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

    /// Last known video duration, updated from `updatePlaybackPosition`.
    /// Used to dynamically compute piece window sizes.
    private var lastKnownDuration: Double = 0

    // MARK: - Init

    init(torrentHandle: TorrentHandle, fileIndex: UInt) {
        self.torrentHandle = torrentHandle
        self.fileIndex = Int(fileIndex)
    }

    // MARK: - Setup

    /// Reads file piece boundaries and configures streaming.
    /// Disables sequential download so libtorrent only fetches pieces with
    /// active deadlines. Then sets aggressive deadlines on the first pieces
    /// + tail pieces so playback can start quickly and seeking works immediately.
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

        // Disable sequential download — Hayase streaming model.
        // Sequential download fights with seeking: libtorrent keeps requesting
        // hundreds of sequential pieces from the beginning, starving the seek
        // target of bandwidth. With sequential OFF and priority-based control,
        // only pieces with priority > 0 and active deadlines are requested.
        torrentHandle.setSequentialDownload(false)

        // Set ALL file pieces to priority 0 (don't download) initially.
        // Only the active window + tail pieces get priority > 0 + deadline.
        // This ensures libtorrent's rarest-first picker ignores pieces we
        // don't need yet — resetPieceDeadline alone doesn't stop downloading.
        for piece in beginPiece...endPiece {
            torrentHandle.setPiecePriority(piece, priority: 0)
        }

        print("TorrentStreamer: start file=\(fileIndex) pieces=\(beginPiece)–\(endPiece) (\(totalFilePieces) total)")

        // Request tail pieces for MKV Cues/SeekHead/subtitle index.
        requestTailPieces()

        // Kick-start: request the first pieces for fast playback start.
        setDeadlinesFrom(pieceIndex: beginPiece, force: true)
    }

    /// Stops streaming management and restores piece priorities.
    /// All file pieces are restored to default priority so libtorrent
    /// resumes normal downloading and the torrent's progress metrics
    /// (snap.progress, snap.isFinished) return to accuracy. Without
    /// this, the Downloads view shows 100% even when barely downloaded
    /// because only "wanted" (priority > 0) pieces count toward progress.
    func stop() {
        guard isActive else { return }
        isActive = false
        resetActiveWindow()
        // Restore all file pieces to default priority so libtorrent resumes
        // normal downloading. This fixes the false "100% downloaded" display
        // in the Downloads view caused by most pieces being at priority 0
        // (which makes libtorrent's progress metric count only the few
        // high-priority pieces that were downloaded).
        for piece in beginPiece...endPiece {
            torrentHandle.setPiecePriority(piece, priority: 4) // default
            torrentHandle.resetPieceDeadline(piece)
        }
        lastDeadlinePiece = -1
        print("TorrentStreamer: stopped")
    }

    // MARK: - Playback position update

    /// Called by the player as playback progresses. `fraction` is 0.0–1.0
    /// representing the current playback position within the video duration.
    func updatePlaybackPosition(fraction: Double, videoDuration: Double = 0) {
        guard isActive, totalFilePieces > 0 else { return }

        if videoDuration > 0 { lastKnownDuration = videoDuration }

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

    /// Called when the user seeks to a new position. Always forces a deadline
    /// update with more aggressive deadlines than normal playback, so pieces
    /// at the seek target arrive quickly.
    func seekTo(fraction: Double) {
        guard isActive, totalFilePieces > 0 else { return }

        let clampedFraction = max(0, min(1, fraction))
        let targetPiece = beginPiece + Int(clampedFraction * Double(totalFilePieces))

        // Force-update with aggressive seek deadlines and a larger window.
        setDeadlinesFrom(pieceIndex: targetPiece, force: true, isSeek: true)
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

    /// Returns true if at least `minimumCount` consecutive pieces starting from
    /// `fraction` of the file have been downloaded. Used to check whether MPV
    /// can safely read data at a seek target. Defaults to 2 pieces because MPV's
    /// MKV demuxer typically needs at least one full cluster (which may span 2
    /// pieces) to parse valid data and begin decoding at a seek position.
    func hasPiecesAt(fraction: Double, minimumCount: Int = 2) -> Bool {
        return consecutiveBufferedPieces(fromFraction: fraction) >= minimumCount
    }

    /// Returns an estimated number of seconds of buffered video ahead of the current position.
    func bufferedSeconds(fromFraction fraction: Double, videoDuration: Double) -> Double {
        guard totalFilePieces > 0, videoDuration > 0 else { return 0 }
        let pieces = consecutiveBufferedPieces(fromFraction: fraction)
        let secondsPerPiece = videoDuration / Double(totalFilePieces)
        return Double(pieces) * secondsPerPiece
    }

    /// Returns true if the tail pieces of the file (which contain MKV Cues,
    /// seek index, and subtitle track info) have been downloaded. These pieces
    /// are critical for seeking: without them MPV's MKV demuxer cannot seek
    /// forward to unvisited positions.
    func areTailPiecesReady() -> Bool {
        guard isActive, totalFilePieces > 0 else { return false }

        torrentHandle.updateSnapshot()
        guard let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }),
              let pieces = entry.pieces as? [NSNumber], !pieces.isEmpty else { return false }

        // Check the last `tailPieceCount` entries in the file's local piece array.
        // Using pieces.count directly avoids any ambiguity with endPiece being
        // inclusive vs exclusive.
        let count = pieces.count
        let tailStart = max(0, count - tailPieceCount)
        for i in tailStart..<count {
            if !pieces[i].boolValue { return false }
        }
        return true
    }

    /// Returns the fraction (0–1) of the file that has been downloaded.
    func downloadedFraction() -> Double {
        guard isActive, totalFilePieces > 0 else { return 0 }

        torrentHandle.updateSnapshot()
        guard let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }) else { return 0 }
        return entry.size > 0 ? Double(entry.downloaded) / Double(entry.size) : 0
    }

    // MARK: - Private

    /// Returns the number of pieces that correspond to `seconds` of video,
    /// based on the last known video duration. Returns 0 when duration is unknown.
    private func piecesForSeconds(_ seconds: Double) -> Int {
        guard lastKnownDuration > 0, totalFilePieces > 0 else { return 0 }
        let secondsPerPiece = lastKnownDuration / Double(totalFilePieces)
        return secondsPerPiece > 0 ? Int(ceil(seconds / secondsPerPiece)) : 0
    }

    /// Sets piece deadlines for a window starting at `pieceIndex`.
    /// - Normal playback: ~10s critical + ~60s look-ahead (dynamically computed)
    /// - Seek mode: larger critical window with tighter deadlines
    /// Pieces outside the window have their deadlines reset so libtorrent stops
    /// requesting them entirely (no sequential download to fall back on).
    /// This is the core of Hayase streaming: only deadline-managed pieces are fetched.
    private func setDeadlinesFrom(pieceIndex: Int, force: Bool = false, isSeek: Bool = false) {
        let start = max(pieceIndex, beginPiece)

        if !force && start == lastDeadlinePiece { return }
        lastDeadlinePiece = start

        // Reset deadline boosts for the previous active window.
        resetActiveWindow()

        // Compute dynamic piece counts from video duration.
        let critCount: Int
        let bufTotal: Int
        let critBase: Int32
        let critStep: Int32

        if isSeek {
            critCount = seekCriticalPieceCount
            // On seek, minimize look-ahead to concentrate all bandwidth on the
            // critical pieces MPV needs to resume playback. The normal look-ahead
            // will kick in once playback advances past the critical window.
            bufTotal  = seekCriticalPieceCount
            critBase  = seekDeadlineBase
            critStep  = seekDeadlineStep
        } else {
            critCount = max(minCriticalPieces, piecesForSeconds(criticalBufferSeconds))
            bufTotal  = max(minBufferPieces, piecesForSeconds(targetBufferSeconds))
            critBase  = criticalDeadlineBase
            critStep  = criticalDeadlineStep
        }

        // Look-ahead count is the total buffer minus critical pieces.
        let lookCount = max(0, bufTotal - critCount)
        let totalWindow = critCount + lookCount
        let windowEnd = min(start + totalWindow - 1, endPiece)

        // Critical buffer: pieces needed for immediate playback.
        // Priority must be set BEFORE deadline — libtorrent ignores deadlines
        // on priority-0 pieces.
        for i in 0..<critCount {
            let piece = start + i
            guard piece <= endPiece else { break }
            torrentHandle.setPiecePriority(piece, priority: 7) // top priority
            let deadline = critBase + Int32(i) * critStep
            torrentHandle.setPieceDeadline(piece, deadline: deadline)
        }

        // Look-ahead buffer: pieces needed in the near future.
        for i in critCount..<totalWindow {
            let piece = start + i
            guard piece <= endPiece else { break }
            torrentHandle.setPiecePriority(piece, priority: 4) // default priority
            let deadline = lookAheadDeadlineBase + Int32(i - critCount) * lookAheadDeadlineStep
            torrentHandle.setPieceDeadline(piece, deadline: deadline)
        }

        activeWindowStart = start
        activeWindowEnd = windowEnd

        // Always keep tail pieces active (MKV Cues/index).
        requestTailPieces()
    }

    /// Requests the last few pieces of the file with tight deadlines.
    /// MKV containers store their Cues (seek index) and subtitle track index
    /// near the end. Without these, MPV cannot seek to arbitrary positions
    /// and cannot discover subtitle tracks until the entire file is downloaded.
    private func requestTailPieces() {
        let tailStart = max(endPiece - tailPieceCount + 1, beginPiece)
        for piece in tailStart...endPiece {
            torrentHandle.setPiecePriority(piece, priority: 7) // top priority
            let offset = Int32(piece - tailStart)
            let deadline = criticalDeadlineBase + offset * criticalDeadlineStep
            torrentHandle.setPieceDeadline(piece, deadline: deadline)
        }
    }

    /// Resets piece priorities and deadlines for the previous active window so
    /// libtorrent truly stops downloading those pieces. setPiecePriority(0) is
    /// required because resetPieceDeadline alone only removes urgency — pieces
    /// would still be downloaded via libtorrent's rarest-first picker.
    /// Tail pieces are NOT reset — they must stay active for MKV index access.
    private func resetActiveWindow() {
        guard activeWindowStart >= 0, activeWindowEnd >= activeWindowStart else { return }
        let tailStart = max(endPiece - tailPieceCount + 1, beginPiece)
        for piece in activeWindowStart...activeWindowEnd {
            // Don't reset tail pieces — they must stay active for MKV Cues/index.
            if piece >= tailStart { continue }
            torrentHandle.setPiecePriority(piece, priority: 0)
            torrentHandle.resetPieceDeadline(piece)
        }
        activeWindowStart = -1
        activeWindowEnd = -1
    }
}
