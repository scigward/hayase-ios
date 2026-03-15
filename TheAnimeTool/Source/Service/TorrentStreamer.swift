//
//  TorrentStreamer.swift
//  TheAnimeTool
//

import Foundation
import LibTorrent

/// Manages torrent-based video streaming for a single file within a torrent.
///
/// Follows the Hayase streaming model — sequential download + priority management:
/// - Sequential download ON (biases libtorrent to download from beginning → metadata first)
/// - All file pieces start at priority 1 (low but wanted) — every peer can contribute
/// - Head pieces (first 8) at priority 7 + tight deadlines (MKV SeekHead/Info/Tracks)
/// - Tail pieces (last 16) at priority 7 + tight deadlines (MKV Cues/seek index)
/// - Active window pieces get priority 7 + tight deadlines (current playback)
/// - Look-ahead pieces get priority 4 + relaxed deadlines (buffer ahead)
/// - Pieces outside the window stay at priority 1 (still downloaded, just lower priority)
/// - On seek: old window drops to priority 1, new window gets priority 7 + deadlines
///   → bandwidth shifts to the new position while all peers remain connected
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

    // -- Head pieces for MKV header --

    /// Target bytes from the START of the file to request for MKV header metadata.
    /// MKV SeekHead + Info + Tracks typically fit within the first 1–2 MB.
    /// The actual piece count is computed in `start()` based on the torrent's
    /// piece size: `max(1, min(8, headByteTarget / pieceLength))`. This adapts
    /// to piece size so large-piece torrents (2–4 MB pieces) don't require
    /// downloading 32–64 MB of head data before streaming can start.
    private static let headByteTarget = 2 * 1024 * 1024 // 2 MB

    /// Computed at `start()` — number of pieces from the START of the file.
    private var headPieceCount = 8

    // -- Tail pieces for MKV index --

    /// Target bytes from the END of the file to request for MKV Cues/seek index.
    /// MKV Cues are typically 100 KB–3 MB depending on file duration and keyframe
    /// density. The actual piece count is computed in `start()` based on the
    /// torrent's piece size: `max(1, min(16, tailByteTarget / pieceLength))`.
    private static let tailByteTarget = 4 * 1024 * 1024 // 4 MB

    /// Computed at `start()` — number of pieces from the END of the file.
    private var tailPieceCount = 16

    // MARK: - State

    private let torrentHandle: TorrentHandle
    private let fileIndex: Int

    /// When true, only download data needed for immediate playback.
    /// Non-window pieces get priority 0 (not wanted) and the buffer window
    /// is much smaller. Read from UserDefaults at start() time.
    private var streamedDownloadMode: Bool = false

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
    /// Enables sequential download and sets all pieces to low priority,
    /// then boosts head/tail pieces and initial window with tight deadlines
    /// so playback can start quickly and metadata is available immediately.
    func start() {
        guard !isActive else { return }
        isActive = true

        // Read streamed download mode at start time.
        streamedDownloadMode = UserDefaults.standard.bool(forKey: "pref_streamedDownload")

        torrentHandle.updateSnapshot()
        guard let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }) else {
            print("TorrentStreamer: file index \(fileIndex) not found in snapshot")
            return
        }

        beginPiece = Int(entry.begin_idx)
        totalFilePieces = Int(entry.num_pieces)

        // LibTorrent-Swift computes endIdx = (fileOffset+fileSize)/pieceLength
        // using integer division. For piece-aligned files this gives one PAST
        // the last piece (e.g. 1125 when valid pieces are 0–1124). Clamp to
        // the torrent's actual piece count to avoid setting priority/deadline
        // on non-existent piece indices.
        let rawEndPiece = Int(entry.end_idx)
        let totalTorrentPieces = torrentHandle.snapshot.pieces?.count ?? rawEndPiece
        endPiece = totalTorrentPieces > 0 ? min(rawEndPiece, totalTorrentPieces - 1) : rawEndPiece

        // Compute byte-aware metadata piece counts from the actual piece size.
        let pl = max(Int(torrentHandle.snapshot.pieceLength), 1)
        headPieceCount = max(1, min(8, Self.headByteTarget / pl))
        tailPieceCount = max(1, min(16, Self.tailByteTarget / pl))

        // Enable sequential download — Hayase streaming model.
        torrentHandle.setSequentialDownload(true)

        // Set non-metadata file pieces to a background priority.
        // In streamed download mode: priority 0 (not wanted) — only download
        // what's needed for playback to save bandwidth.
        // In normal mode: priority 1 (low but wanted) — keeps all peers
        // connected and contributing even for pieces not yet needed.
        // IMPORTANT: Skip head and tail pieces — VideoService's early
        // requestMetadataPieces() may have already set them to priority 7
        // with time-critical deadlines.
        let bgPriority: Int32 = streamedDownloadMode ? 0 : 1
        let headEnd = min(beginPiece + headPieceCount - 1, endPiece)
        let tailStart = max(endPiece - tailPieceCount + 1, beginPiece)
        for piece in beginPiece...endPiece {
            if piece <= headEnd || piece >= tailStart { continue }
            torrentHandle.setPiecePriority(piece, priority: bgPriority)
        }

        let plMB = String(format: "%.1f", Double(pl) / 1_048_576)
        let modeStr = streamedDownloadMode ? " [streamed]" : ""
        StreamingLogger.shared.info("Streaming: \(totalFilePieces) pieces × \(plMB) MB, head=\(headPieceCount) tail=\(tailPieceCount)\(modeStr)")
        print("TorrentStreamer: start file=\(fileIndex) pieces=\(beginPiece)–\(endPiece) (\(totalFilePieces) total) pieceLen=\(pl) head=\(headPieceCount) tail=\(tailPieceCount) streamedDownload=\(streamedDownloadMode)")

        // Force re-announce to all trackers so we discover peers immediately.
        // This is critical for low-seeder torrents: the torrent may have been
        // added minutes ago and trackers may have timed out. Hayase re-announces
        // on every play; libtorrent's forceReannounce() sends announce requests
        // to ALL trackers (including anime-specific ones we added via
        // addPublicTrackers) and the responses arrive asynchronously, bringing
        // in fresh peer connections for the pieces we need.
        torrentHandle.forceReannounce()

        // Request head pieces for MKV SeekHead/Info/Tracks (duration + subtitle defs).
        requestHeadPieces()

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
        // In streamed download mode, the threshold is smaller (critical buffer only).
        if videoDuration > 0 {
            let bufSec = bufferedSeconds(fromFraction: clampedFraction, videoDuration: videoDuration)
            let threshold = streamedDownloadMode ? criticalBufferSeconds : targetBufferSeconds
            if bufSec >= threshold && lastDeadlinePiece >= 0 {
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
    /// Pieces outside the window are reset to priority 1 (low but still wanted)
    /// so libtorrent continues downloading them at low priority while concentrating
    /// bandwidth on the active window. Head and tail pieces keep priority 7.
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
        } else if streamedDownloadMode {
            // Streamed download: minimal buffer — only a few seconds of playback.
            // No look-ahead beyond the critical window.
            critCount = max(4, piecesForSeconds(criticalBufferSeconds))
            bufTotal  = critCount
            critBase  = criticalDeadlineBase
            critStep  = criticalDeadlineStep
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

        // Always keep head + tail pieces active (MKV metadata).
        requestHeadPieces()
        requestTailPieces()
    }

    /// Requests the first few pieces of the file with tight deadlines.
    /// MKV containers store SeekHead, Info (video duration), and Track
    /// definitions (subtitle/audio codec info) in the first few pieces.
    /// Without these, MPV cannot determine the video length or discover
    /// subtitle tracks when the stream first opens.
    private func requestHeadPieces() {
        let headEnd = min(beginPiece + headPieceCount - 1, endPiece)
        for piece in beginPiece...headEnd {
            torrentHandle.setPiecePriority(piece, priority: 7) // top priority
            let offset = Int32(piece - beginPiece)
            let deadline = criticalDeadlineBase + offset * criticalDeadlineStep
            torrentHandle.setPieceDeadline(piece, deadline: deadline)
        }
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

    // MARK: - Metadata pre-wait

    /// Blocks the calling thread until the head pieces (first `headPieceCount`
    /// pieces of the file) are downloaded, or until `timeout` seconds elapse.
    /// This ensures MKV header data (SeekHead, Info, Tracks) is on disk before
    /// MPV opens the stream, so video duration and subtitle tracks are available
    /// immediately.
    ///
    /// For large-piece torrents (16+ MB pieces), also accepts byte-level progress
    /// as an alternative to piece hash verification. MKV headers typically fit
    /// within 2 MB, so if `file_progress()` reports enough downloaded bytes,
    /// the header data is on disk from libtorrent's block-level writes even
    /// though the piece hasn't been fully hash-verified. Sequential download
    /// mode ensures these bytes are contiguous from the file's start.
    ///
    /// Periodically re-boosts head piece priorities every ~1 second during the
    /// wait. This handles edge cases where libtorrent's internal recalculations
    /// (e.g., update_piece_priorities from set_file_priority) might reset our
    /// piece-level overrides back to the file-level default.
    ///
    /// - Returns: `true` if head pieces are ready, `false` on timeout or stop.
    func waitForMetadataPieces(timeout: TimeInterval = 60) -> Bool {
        guard isActive, totalFilePieces > 0 else { return false }

        let headEnd = min(headPieceCount - 1, totalFilePieces - 1) // local indices
        let startTime = Date()
        let pollInterval: TimeInterval = 0.25
        let reinforceInterval: TimeInterval = 1.0
        var lastReinforceTime = Date.distantPast // trigger immediate first reinforcement
        var lastPeerLog = Date.distantPast

        // Byte-level threshold: minimum bytes at the start of the file for MPV
        // to parse the MKV header (SeekHead + Info + Tracks). This is the
        // fallback for large-piece torrents where piece verification takes too
        // long. Sequential download mode guarantees these bytes are contiguous.
        let byteThreshold = UInt64(Self.headByteTarget) // 2 MB

        while isActive {
            let now = Date()

            // Re-boost head+tail piece priorities periodically.
            // libtorrent's update_piece_priorities (triggered by set_file_priority)
            // can reset our piece-level overrides back to the file-level default (4).
            // Re-requesting every second ensures head/tail stay at priority 7 with
            // time-critical deadlines.
            if now.timeIntervalSince(lastReinforceTime) >= reinforceInterval {
                requestHeadPieces()
                requestTailPieces()
                lastReinforceTime = now
            }

            torrentHandle.updateSnapshot()
            let snap = torrentHandle.snapshot
            guard let entry = snap.files.first(where: { $0.index == fileIndex }),
                  let pieces = entry.pieces as? [NSNumber] else {
                Thread.sleep(forTimeInterval: pollInterval)
                continue
            }

            // Log peer count periodically so the user can see connection status
            // for low-seeder torrents via the streaming logger.
            if now.timeIntervalSince(lastPeerLog) >= 5.0 {
                let peers = snap.numberOfPeers
                let seeds = snap.numberOfSeeds
                let dlMB = String(format: "%.1f", Double(entry.downloaded) / 1_048_576)
                StreamingLogger.shared.info("Waiting for metadata… peers=\(peers) seeds=\(seeds) dl=\(dlMB) MB")
                lastPeerLog = now
            }

            // Check 1: piece-level verification (most reliable).
            // If the pieces array is shorter than expected (snapshot not fully
            // populated or stale), treat the missing entries as NOT ready.
            var piecesReady = pieces.count > headEnd // array must cover all head pieces
            if piecesReady {
                for i in 0...headEnd {
                    if !pieces[i].boolValue {
                        piecesReady = false
                        break
                    }
                }
            }

            if piecesReady {
                StreamingLogger.shared.info("Head pieces ready (\(String(format: "%.1f", Date().timeIntervalSince(startTime)))s)")
                print("TorrentStreamer: head pieces ready (\(String(format: "%.1f", Date().timeIntervalSince(startTime)))s)")
                return true
            }

            // Check 2: byte-level progress (fallback for large-piece torrents).
            // file_progress() without flags includes bytes from partial (unverified)
            // pieces. If enough bytes have been downloaded at the start of the file,
            // the MKV header is on disk and MPV can parse it via the local HTTP
            // server (which has its own byte-level bypass). This prevents the
            // common scenario where a 16+ MB piece takes minutes to fully download
            // and verify, but the first 2 MB (containing the MKV header) arrives
            // in seconds.
            if entry.downloaded >= byteThreshold {
                let dlMB = String(format: "%.1f", Double(entry.downloaded) / 1_048_576)
                StreamingLogger.shared.info("Head bytes ready (\(dlMB) MB in \(String(format: "%.1f", Date().timeIntervalSince(startTime)))s)")
                print("TorrentStreamer: head bytes ready (downloaded=\(dlMB) MB, piece not yet verified)")
                return true
            }

            if now.timeIntervalSince(startTime) > timeout {
                let dlMB = String(format: "%.1f", Double(entry.downloaded) / 1_048_576)
                let peers = snap.numberOfPeers
                let seeds = snap.numberOfSeeds
                StreamingLogger.shared.error("Metadata timeout \(String(format: "%.0f", timeout))s — need \(headEnd + 1) pieces, dl=\(dlMB) MB, peers=\(peers) seeds=\(seeds)")
                print("TorrentStreamer: metadata wait timeout after \(String(format: "%.0f", timeout))s — pieces.count=\(pieces.count), need=\(headEnd + 1), downloaded=\(dlMB) MB, peers=\(peers), seeds=\(seeds)")
                return false
            }

            Thread.sleep(forTimeInterval: pollInterval)
        }
        return false
    }

    /// Resets piece priorities and deadlines for the previous active window.
    /// In normal mode: pieces are set to priority 1 (low but still wanted) so
    /// libtorrent continues downloading them at low priority.
    /// In streamed download mode: pieces are set to priority 0 (not wanted) so
    /// libtorrent stops downloading them entirely, saving bandwidth.
    /// Head and tail pieces are NOT reset — they must stay at priority 7 for MKV metadata.
    private func resetActiveWindow() {
        guard activeWindowStart >= 0, activeWindowEnd >= activeWindowStart else { return }
        let bgPriority: Int32 = streamedDownloadMode ? 0 : 1
        let headEnd = min(beginPiece + headPieceCount - 1, endPiece)
        let tailStart = max(endPiece - tailPieceCount + 1, beginPiece)
        for piece in activeWindowStart...activeWindowEnd {
            // Don't reset head pieces — they must stay active for MKV header.
            if piece <= headEnd { continue }
            // Don't reset tail pieces — they must stay active for MKV Cues/index.
            if piece >= tailStart { continue }
            torrentHandle.setPiecePriority(piece, priority: bgPriority)
            torrentHandle.resetPieceDeadline(piece)
        }
        activeWindowStart = -1
        activeWindowEnd = -1
    }
}
