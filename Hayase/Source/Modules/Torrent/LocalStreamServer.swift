//
//  LocalStreamServer.swift
//  Hayase
//
//  A minimal local HTTP server that serves a partially-downloaded torrent
//  file to MPV. Instead of pointing MPV at a local file with "holes"
//  (undownloaded pieces = zeros), we serve it via HTTP. The server only
//  responds with bytes for pieces that have been downloaded, blocking
//  until they become available. MPV's native HTTP streaming handles
//  buffering and seeking automatically — no more waitForPiecesAndSeek.
//

import Foundation
import Network
import LibTorrent

final class LocalStreamServer {

    // MARK: - Properties

    private let torrentHandle: TorrentHandle
    private let fileIndex: Int
    private let filePath: String
    private let fileSize: UInt64

    /// Actual torrent piece length in bytes (from TorrentHandleSnapshot.pieceLength).
    /// This is the real value from libtorrent's torrent_info::piece_length(),
    /// not an approximation. Used for exact byte-offset-to-piece mapping.
    private let pieceLength: Int

    /// Number of pieces for this file (from FileEntry.num_pieces).
    private let totalPieces: Int

    /// Global piece index where this file starts (FileEntry.begin_idx).
    private let beginPiece: Int

    /// Global piece index for the end of the file (FileEntry.end_idx).
    /// May be the last piece containing file data (non-aligned) or one
    /// past it (aligned). Used to derive the maximum valid local piece index.
    private let endPiece: Int

    /// Maximum valid local piece index (0-based). This is `endPiece - beginPiece`,
    /// which may be equal to `totalPieces` when LibTorrent-Swift's num_pieces
    /// underestimates by 1 for files that don't end on a piece boundary.
    private let maxLocalPiece: Int

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "LocalStreamServer", qos: .userInitiated)
    /// Serial queue to protect torrentHandle.updateSnapshot() calls.
    private let snapshotQueue = DispatchQueue(label: "LocalStreamServer.snapshot")
    /// Lock that protects the `connections` array.  `stop()` can be called from
    /// any thread (typically main) while `handleConnection`/`removeConnection`
    /// run on `queue`, so a lock is required to prevent concurrent array mutations.
    private let connectionsLock = NSLock()
    private var connections: [NWConnection] = []
    /// `isStopped` is written in `stop()` (any thread) and read from
    /// DispatchQueue.global inside streamBody/waitForLocalPieces.
    /// `stoppedLock` ensures proper synchronisation across threads.
    private let stoppedLock = NSLock()
    private var _isStopped = false
    private var isStopped: Bool {
        get {
            stoppedLock.lock()
            defer { stoppedLock.unlock() }
            return _isStopped
        }
        set {
            stoppedLock.lock()
            defer { stoppedLock.unlock() }
            _isStopped = newValue
        }
    }

    /// The port the server is listening on.
    private(set) var port: UInt16 = 0

    /// The HTTP URL that MPV should use to play the file.
    var url: URL {
        URL(string: "http://127.0.0.1:\(port)/video.mkv")!
    }

    // MARK: - Init

    init(torrentHandle: TorrentHandle, fileIndex: UInt, filePath: String) {
        self.torrentHandle = torrentHandle
        let idx = Int(fileIndex)
        self.fileIndex = idx
        self.filePath = filePath

        torrentHandle.updateSnapshot()
        let snap = torrentHandle.snapshot
        let entry = snap.files.first(where: { $0.index == idx })
        self.fileSize = entry?.size ?? 0
        self.pieceLength = Int(snap.pieceLength)
        self.totalPieces = Int(entry?.num_pieces ?? 0)
        self.beginPiece = Int(entry?.begin_idx ?? 0)

        // LibTorrent-Swift computes endIdx = (fileOffset+fileSize)/pieceLength
        // using integer division. For piece-aligned files this gives one PAST
        // the last piece (e.g. 1125 when valid pieces are 0–1124). Clamp to
        // the torrent's actual piece count so we never set priority/deadline
        // on a non-existent piece index.
        let rawEndPiece = Int(entry?.end_idx ?? 0)
        let snapshotPieceCount = Int(snap.numberOfPieces)
        let totalTorrentPieces = snapshotPieceCount > 0 ? snapshotPieceCount : rawEndPiece
        self.endPiece = totalTorrentPieces > 0 ? min(rawEndPiece, totalTorrentPieces - 1) : rawEndPiece

        // endPiece - beginPiece may be 1 more than totalPieces when the file
        // doesn't end on a piece boundary (LibTorrent-Swift's num_pieces
        // uses integer division which truncates the partial last piece).
        self.maxLocalPiece = max(self.endPiece - self.beginPiece, self.totalPieces > 0 ? self.totalPieces - 1 : 0)
    }

    // MARK: - Start / Stop

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Use port 0 to let the system assign an available port
        listener = try NWListener(using: params, on: .any)

        let readySemaphore = DispatchSemaphore(value: 0)
        var startError: Error?

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener?.port?.rawValue {
                    self?.port = port
                    if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("LocalStreamServer: listening on port \(port)") }
                }
                readySemaphore.signal()
            case .failed(let error):
                if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("LocalStreamServer: failed — \(error)") }
                startError = error
                self?.stop()
                readySemaphore.signal()
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)

        // Wait up to 2s for the listener to be ready and port to be assigned.
        // If start() is called from UIKit, keep the main run loop pumping while
        // the NWListener reports readiness instead of blocking UI input outright.
        let waitResult: DispatchTimeoutResult
        if Thread.isMainThread {
            let deadline = Date().addingTimeInterval(2.0)
            var didSignal = false
            while Date() < deadline {
                if readySemaphore.wait(timeout: .now()) == .success {
                    didSignal = true
                    break
                }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            waitResult = didSignal ? .success : .timedOut
        } else {
            waitResult = readySemaphore.wait(timeout: .now() + 2.0)
        }
        if waitResult == .timedOut {
            stop()
            throw NSError(domain: "LocalStreamServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Timed out while starting local stream server"])
        }
        if let startError {
            throw startError
        }
        guard port != 0 else {
            stop()
            throw NSError(domain: "LocalStreamServer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Local stream server did not receive a valid port"])
        }
    }

    func stop() {
        isStopped = true
        listener?.cancel()
        listener = nil
        // Snapshot and clear the connections array under the lock so we don't
        // race with handleConnection / removeConnection which also hold the lock.
        connectionsLock.lock()
        let snapshot = connections
        connections.removeAll()
        connectionsLock.unlock()
        for conn in snapshot { conn.cancel() }
        if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("LocalStreamServer: stopped") }
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connectionsLock.lock()
        connections.append(connection)
        connectionsLock.unlock()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(connection)
    }

    private func removeConnection(_ connection: NWConnection) {
        connectionsLock.lock()
        connections.removeAll(where: { $0 === connection })
        connectionsLock.unlock()
    }

    private func receiveRequest(_ connection: NWConnection) {
        // Read up to 8KB — more than enough for an HTTP request header.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self = self, !self.isStopped else { return }
            if let error = error {
                if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("LocalStreamServer: receive error — \(error)") }
                connection.cancel()
                return
            }
            guard let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""
            self.processRequest(request, connection: connection)
        }
    }

    // MARK: - HTTP request parsing

    private func processRequest(_ request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }

        let method = String(parts[0])

        // Parse Range header
        var rangeStart: UInt64 = 0
        var rangeEnd: UInt64 = fileSize > 0 ? fileSize - 1 : 0
        var hasRange = false
        var invalidRange = false

        for line in lines {
            if line.lowercased().hasPrefix("range:") {
                let value = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("bytes=") {
                    let rangeStr = value.dropFirst(6)
                    let rangeParts = rangeStr.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                    let startStr = rangeParts.first.map(String.init) ?? ""
                    let endStr = rangeParts.count > 1 ? String(rangeParts[1]) : ""
                    hasRange = true

                    if startStr.isEmpty {
                        // Suffix range: "bytes=-65536" means the last 65536 bytes.
                        guard fileSize > 0, let suffixLength = UInt64(endStr), suffixLength > 0 else {
                            invalidRange = true
                            break
                        }
                        let length = min(suffixLength, fileSize)
                        rangeStart = fileSize - length
                        rangeEnd = fileSize - 1
                    } else if let start = UInt64(startStr) {
                        guard fileSize > 0, start < fileSize else {
                            invalidRange = true
                            break
                        }
                        rangeStart = start
                        if !endStr.isEmpty {
                            guard let end = UInt64(endStr), end >= start else {
                                invalidRange = true
                                break
                            }
                            rangeEnd = min(end, fileSize - 1)
                        } else {
                            rangeEnd = fileSize - 1
                        }
                    } else {
                        invalidRange = true
                    }
                }
                break
            }
        }

        // Clamp
        if fileSize > 0 {
            rangeStart = min(rangeStart, fileSize - 1)
            rangeEnd = min(rangeEnd, fileSize - 1)
        }

        if invalidRange {
            sendRangeNotSatisfiable(connection: connection)
            return
        }

        if method == "HEAD" {
            let contentLength = fileSize > 0 ? rangeEnd - rangeStart + 1 : 0
            sendHeaders(connection: connection, rangeStart: rangeStart, rangeEnd: rangeEnd, hasRange: hasRange, bodyLength: contentLength)
            // After HEAD, wait for next request on this connection (keep-alive)
            receiveRequest(connection)
            return
        }

        if method == "GET" {
            serveRange(connection: connection, rangeStart: rangeStart, rangeEnd: rangeEnd, hasRange: hasRange)
            return
        }

        // Unsupported method
        let response = "HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - HTTP response

    private func sendHeaders(connection: NWConnection, rangeStart: UInt64, rangeEnd: UInt64, hasRange: Bool, bodyLength: UInt64?) {
        let contentLength = bodyLength ?? (fileSize > 0 ? rangeEnd - rangeStart + 1 : 0)
        var header: String

        if hasRange {
            header = "HTTP/1.1 206 Partial Content\r\n"
            header += "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(fileSize)\r\n"
        } else {
            header = "HTTP/1.1 200 OK\r\n"
        }
        header += "Content-Type: application/octet-stream\r\n"
        header += "Content-Length: \(contentLength)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Connection: keep-alive\r\n"
        header += "\r\n"

        connection.send(content: header.data(using: .utf8), completion: .contentProcessed { error in
            if let error = error {
                if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("LocalStreamServer: header send error — \(error)") }
            }
        })
    }

    private func sendRangeNotSatisfiable(connection: NWConnection) {
        let response = """
        HTTP/1.1 416 Range Not Satisfiable\r
        Content-Range: bytes */\(fileSize)\r
        Content-Length: 0\r
        Connection: close\r
        \r
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func serveRange(connection: NWConnection, rangeStart: UInt64, rangeEnd: UInt64, hasRange: Bool) {
        let contentLength = fileSize > 0 ? rangeEnd - rangeStart + 1 : 0
        sendHeaders(connection: connection, rangeStart: rangeStart, rangeEnd: rangeEnd, hasRange: hasRange, bodyLength: contentLength)

        guard contentLength > 0 else {
            receiveRequest(connection)
            return
        }

        // Stream body in chunks on a background queue so we don't block
        // the NWListener queue. Each chunk is read from the file only after
        // the pieces covering those bytes are confirmed downloaded.
        // Each connection's streamBody runs independently — MPV may open
        // multiple connections for parallel range requests (e.g., one for
        // the beginning of the file and one for the end to probe MKV Cues).
        // Using a global "generation" counter to cancel old streams would
        // kill the main data stream when the probe request arrives.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.streamBody(connection: connection, offset: rangeStart, end: rangeEnd)
        }
    }

    /// Streams file bytes from `offset` to `end` in chunks, waiting for each
    /// chunk's pieces to be available before reading from disk.
    /// Exits when the full range has been sent, the connection is closed by
    /// the client, or the server is stopped.
    private func streamBody(connection: NWConnection, offset: UInt64, end: UInt64) {
        guard !isStopped else { return }

        // Open the file
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            StreamingLogger.shared.error("Cannot open file at \(filePath)")
            if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("LocalStreamServer: cannot open file at \(filePath)") }
            connection.cancel()
            return
        }
        defer { fileHandle.closeFile() }

        // Cap chunk size to avoid serving huge responses. With 16+ MB pieces,
        // using pieceLength as chunkSize means the server sends up to 16 MB per
        // chunk — wasteful for seeks and unnecessary for streaming. Capping at
        // 512 KB lets us serve data incrementally once a piece is hash-verified:
        // the first chunk within a verified piece is served immediately, followed
        // by the remaining chunks from the same verified piece without re-waiting.
        let maxChunkSize = 512 * 1024
        let chunkSize = UInt64(pieceLength > 0 ? min(pieceLength, maxChunkSize) : 65536)

        var currentOffset = offset
        while currentOffset <= end && !isStopped {
            let readEnd = min(currentOffset + chunkSize - 1, end)

            // Which local pieces cover this byte range?
            // Uses exact pieceLength for mapping: localPiece = offset / pieceLength.
            //
            // For single-file torrents (beginPiece == 0, fileOffset == 0), the
            // mapping is exact: file-local byte N is always in piece N/pieceLength.
            // WebTorrent's FileIterator computes _startPiece as
            //   (start + file.offset) / pieceLength | 0
            // which equals start/pieceLength when file.offset==0 — identical to
            // localPieceIndex. Adding +1 here is WRONG for single-file torrents:
            // it forces every chunk to wait for the piece AFTER the one being
            // served (WebTorrent never waits for more than the current piece).
            //
            // For multi-file torrents (beginPiece > 0, fileOffset != 0), the file
            // may start mid-piece so localPieceIndex (which ignores fileOffset) can
            // underestimate by 1. The +1 margin is required only in that case.
            let firstLocalPiece = localPieceIndex(forByteOffset: currentOffset)
            let lastLocalPiece = localPieceIndex(forByteOffset: readEnd) + (beginPiece > 0 ? 1 : 0)

            // Wait for ALL required pieces to be downloaded and hash-verified.
            // Returns true if pieces were already on disk (no waiting needed).
            // We MUST wait for piece-level verification — serving data from
            // unverified pieces causes H264 decode errors when a peer sends
            // corrupted blocks (the piece will fail hash check and be
            // re-downloaded, but we'd have already served the bad data to MPV).
            let alreadyOnDisk = waitForLocalPieces(from: firstLocalPiece, to: lastLocalPiece)

            if isStopped { break }

            // Read from file. For freshly-downloaded pieces, verify data
            // stability with a double-read to detect partial flushes.
            let readLength = Int(readEnd - currentOffset + 1)
            fileHandle.seek(toFileOffset: currentOffset)
            var data = fileHandle.readData(ofLength: readLength)

            if !data.isEmpty && data.allSatisfy({ $0 == 0 }) {
                // All zeros: piece data not flushed at all. Retry with flush.
                for _ in 0..<5 {
                    guard !isStopped else { break }
                    torrentHandle.flushCache()
                    Thread.sleep(forTimeInterval: 0.05)
                    fileHandle.seek(toFileOffset: currentOffset)
                    data = fileHandle.readData(ofLength: readLength)
                    if data.isEmpty || !data.allSatisfy({ $0 == 0 }) { break }
                }
            }

            // Double-read verification for freshly-downloaded data.
            // If libtorrent's disk thread is still writing when we read,
            // a second read may return different (more complete) data.
            // Skip for pieces already on disk (stable).
            // Removed unconditional 30ms pre-sleep: WebTorrent's store.get()
            // callback fires with ready data and never sleeps. We do the second
            // read immediately; only if the data actually changed do we flush
            // and wait — this eliminates the 30ms penalty on the common path.
            if !alreadyOnDisk && !data.isEmpty && !data.allSatisfy({ $0 == 0 }) {
                fileHandle.seek(toFileOffset: currentOffset)
                let verifyData = fileHandle.readData(ofLength: readLength)
                if verifyData != data {
                    // Data changed — flush was still in progress. Use newer
                    // read and give one more chance for it to stabilize.
                    data = verifyData
                    if !isStopped { torrentHandle.flushCache() }
                    Thread.sleep(forTimeInterval: 0.05)
                    fileHandle.seek(toFileOffset: currentOffset)
                    let finalData = fileHandle.readData(ofLength: readLength)
                    if !finalData.isEmpty { data = finalData }
                }
            }

            if data.isEmpty { break }

            // Send synchronously (block until sent).
            // If the client (MPV) closes the connection (e.g., on seek),
            // the send will fail and we exit the loop naturally.
            let semaphore = DispatchSemaphore(value: 0)
            var sendError: NWError?

            connection.send(content: data, completion: .contentProcessed { error in
                sendError = error
                semaphore.signal()
            })

            semaphore.wait()
            if sendError != nil { break }

            currentOffset = readEnd + 1
        }

        // Only wait for the next request if we successfully served the full
        // range. If we exited early (send error, server stopped, empty read),
        // the response is incomplete and the client won't send another request
        // on this connection — trying to receiveRequest would hang.
        let completedFullRange = currentOffset > end
        if !isStopped && completedFullRange {
            queue.async { [weak self] in
                self?.receiveRequest(connection)
            }
        }
    }

    // MARK: - Piece mapping & availability

    /// Maps a byte offset within the file to a local piece index (0-based).
    /// Uses the actual torrent piece length for exact mapping.
    /// For single-file torrents (beginPiece == 0), this is exact.
    /// For multi-file torrents, the result may be off by +1 when the file
    /// starts mid-piece; callers should add a +1 margin on lastLocalPiece.
    private func localPieceIndex(forByteOffset offset: UInt64) -> Int {
        guard pieceLength > 0 else { return 0 }
        let index = Int(offset / UInt64(pieceLength))
        if maxLocalPiece <= 0 {
            return max(0, min(index, totalPieces - 1))
        }
        return min(index, maxLocalPiece)
    }

    /// Checks if a local piece (0-based index within the file) has been downloaded.
    /// Thread-safe: uses snapshotQueue to serialize torrentHandle access.
    private func isLocalPieceDownloaded(_ localIndex: Int) -> Bool {
        guard !isStopped else { return false }
        return snapshotQueue.sync {
            torrentHandle.updateSnapshot()
            guard let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }),
                  let pieces = entry.pieces as? [NSNumber],
                  localIndex >= 0, localIndex < pieces.count else { return false }
            return pieces[localIndex].boolValue
        }
    }

    /// Blocks the current thread until all pieces from `firstLocal` to `lastLocal`
    /// (inclusive, 0-based) are downloaded and hash-verified.
    ///
    /// Sets priority 7 AND deadline to ensure libtorrent fetches them urgently.
    /// TorrentStreamer starts all pieces at priority 1 (low), so this boosts
    /// the needed pieces to top priority.
    ///
    /// Thread-safe: uses snapshotQueue to serialize torrentHandle access.
    ///
    /// - Parameters:
    ///   - firstLocal: First local piece index (0-based within file).
    ///   - lastLocal: Last local piece index (inclusive).
    /// - Returns: `true` if all pieces were already downloaded (no waiting),
    ///   `false` if we had to wait for at least one piece.
    @discardableResult
    private func waitForLocalPieces(from firstLocal: Int, to lastLocal: Int) -> Bool {
        // Clamp to valid piece array range
        let safeFirst = max(firstLocal, 0)
        let lastBound: Int
        if maxLocalPiece > 0 {
            lastBound = maxLocalPiece
        } else if totalPieces > 0 {
            lastBound = totalPieces - 1
        } else {
            lastBound = 0
        }
        let safeLast = min(lastLocal, lastBound)

        guard safeFirst <= safeLast else { return true }

        // Number of extra pieces to boost beyond the requested range so
        // libtorrent downloads them in parallel. In streamed download mode,
        // reduce this to minimize bandwidth usage beyond immediate playback.
        let streamedMode = UserDefaults.standard.bool(forKey: "pref_streamedDownload")
        let readAheadCount = streamedMode ? 5 : 50

        func applyPriorityBoost() {
            // Set priority + deadlines on the immediately-needed pieces.
            // These are the "critical" pieces — equivalent to WebTorrent's
            // critical() marking. Only these get deadlines, so libtorrent's
            // cancel_non_critical() focuses ALL bandwidth on them.
            // Priority must be > 0 or libtorrent ignores the deadline.
            //
            // Deadline values: 10 ms base + 50 ms/piece — identical to
            // TorrentStreamer.criticalDeadlineBase/Step. Using the same values
            // ensures applyPriorityBoost never overrides TorrentStreamer's
            // tighter seek deadlines (seekDeadlineBase = 5 ms + 30 ms/piece)
            // with a much looser value. Previously 500 ms + 200 ms/piece
            // was used but this was far too loose, overriding seek deadlines
            // and delaying resume by ~500 ms after each 1-second reboost tick.
            for localIdx in safeFirst...safeLast {
                let globalIdx = beginPiece + localIdx
                torrentHandle.setPiecePriority(globalIdx, priority: 7)
                let offset = min(localIdx - safeFirst, 1000) // clamp: avoid Int32 overflow
                let deadline = Int32(10 + offset * 50)   // 10 ms base + 50 ms/piece
                torrentHandle.setPieceDeadline(globalIdx, deadline: deadline)
            }

            // Read-ahead: boost priority on pieces beyond the current chunk
            // so libtorrent downloads them via sequential ordering. Priority
            // only, NO deadlines — this matches WebTorrent's approach where
            // only the critical 1–2 pieces get deadline treatment. Read-ahead
            // pieces are downloaded by sequential mode + elevated priority
            // without competing for deadline-driven bandwidth.
            let upperBound: Int
            if maxLocalPiece > 0 {
                upperBound = maxLocalPiece
            } else if totalPieces > 0 {
                upperBound = totalPieces - 1
            } else {
                upperBound = safeLast
            }
            let readAheadEnd = min(safeLast + readAheadCount, upperBound)
            if readAheadEnd > safeLast {
                for localIdx in (safeLast + 1)...readAheadEnd {
                    let globalIdx = beginPiece + localIdx
                    torrentHandle.setPiecePriority(globalIdx, priority: 7)
                }
            }
        }
        applyPriorityBoost()

        // Poll until all pieces are available
        let pollInterval: TimeInterval = 0.05 // 50ms
        let startTime = Date()
        var lastPriorityBoost = startTime
        var lastStatusLog = startTime
        var lastReannounce = startTime
        let reboostInterval: TimeInterval = 1.0
        let statusInterval: TimeInterval = 5.0
        let reannounceInterval: TimeInterval = 30.0
        var lastPeerLog = startTime
        var isFirstCheck = true
        var didLogInitialWait = false

        while !isStopped {
            var allReady = true
            var missingPieces = 0
            guard !isStopped else { break }
            snapshotQueue.sync {
                guard !isStopped else { return }
                torrentHandle.updateSnapshot()
                if let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }),
                   let pieces = entry.pieces as? [NSNumber] {

                    for localIdx in safeFirst...safeLast {
                        if localIdx < pieces.count {
                            // Normal case: check the file's local piece array.
                            if !pieces[localIdx].boolValue {
                                allReady = false
                                missingPieces += 1
                                break
                            }
                        } else {
                            // Beyond the file's local piece array. This happens
                            // for multi-file/batch torrents where the file doesn't
                            // end on a piece boundary — the boundary piece is shared
                            // with the next file and num_pieces (integer division)
                            // underestimates by 1. Fall back to the GLOBAL torrent
                            // piece status array to check if it's downloaded.
                            // Without this fallback, the server would block forever
                            // on the boundary piece (pieces[OOB] → allReady=false).
                            let globalIdx = beginPiece + localIdx
                            if let globalPieces = torrentHandle.snapshot.pieces as? [NSNumber],
                               globalIdx >= 0, globalIdx < globalPieces.count {
                                if !globalPieces[globalIdx].boolValue {
                                    allReady = false
                                    missingPieces += 1
                                    break
                                }
                            } else {
                                // Can't verify via global array either — not ready.
                                allReady = false
                                missingPieces += 1
                                break
                            }
                        }
                    }
                } else {
                    // Can't read piece status — not ready.
                    allReady = false
                }
            }

            if allReady {
                guard !isStopped else { break }
                if !isFirstCheck {
                    // Pieces may not yet be flushed to disk — flush libtorrent's
                    // write cache so the data is visible to FileHandle before we
                    // read it. Skip when isFirstCheck (pieces were already on disk
                    // before we entered the wait loop): no flush is needed and the
                    // 50ms sleep wastes time for every chunk served from a file
                    // that is already buffered (WebTorrent: zero delay for cached
                    // reads via store.get callback).
                    torrentHandle.flushCache()
                    // Give libtorrent's disk I/O thread time to complete the flush.
                    // flushCache() posts a job asynchronously — data may not be in
                    // the OS page cache yet when it returns. 50ms handles typical
                    // I/O latency; the double-read in streamBody catches edge cases.
                    Thread.sleep(forTimeInterval: 0.05)
                }
                return isFirstCheck
            }

            isFirstCheck = false

            // Log which pieces we're waiting for on the first failed check.
            if !didLogInitialWait {
                didLogInitialWait = true
                StreamingLogger.shared.info("Buffering pieces \(safeFirst)–\(safeLast)…")
            }

            let now = Date()
            if now.timeIntervalSince(lastPriorityBoost) >= reboostInterval {
                guard !isStopped else { break }
                applyPriorityBoost()
                lastPriorityBoost = now
            }
            // Re-announce to trackers periodically to discover new peers.
            // Critical for low-seeder torrents: peers may come and go, and
            // the initial announce at TorrentStreamer.start() may have found
            // zero or few seeds. Re-announcing brings in fresh connections
            // that can supply the pieces we're stuck on.
            if now.timeIntervalSince(lastReannounce) >= reannounceInterval {
                guard !isStopped else { break }
                torrentHandle.forceReannounce()
                lastReannounce = now
            }
            if now.timeIntervalSince(lastStatusLog) >= statusInterval {
                let waited = String(format: "%.1f", now.timeIntervalSince(startTime))
                let missingDesc = missingPieces > 0 ? " missing~\(missingPieces)" : ""
                StreamingLogger.shared.warn("Waiting \(waited)s for pieces \(safeFirst)–\(safeLast)\(missingDesc)")
                if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("LocalStreamServer: waiting \(waited)s for pieces \(safeFirst)-\(safeLast)\(missingDesc)") }
                lastStatusLog = now
            }
            // Log peer/seed count every 5 s so users can see connection status
            // for low-seeder torrents via the streaming logger overlay.
            if now.timeIntervalSince(lastPeerLog) >= 5.0 {
                var peers = 0
                var seeds = 0
                var dlMB = "0.0"
                snapshotQueue.sync {
                    guard !isStopped else { return }
                    let snap = torrentHandle.snapshot
                    peers = Int(snap.numberOfPeers)
                    seeds = Int(snap.numberOfSeeds)
                    if let entry = snap.files.first(where: { $0.index == fileIndex }) {
                        dlMB = String(format: "%.1f", Double(entry.downloaded) / 1_048_576)
                    }
                }
                StreamingLogger.shared.info("Waiting for pieces… peers=\(peers) seeds=\(seeds) dl=\(dlMB) MB")
                lastPeerLog = now
            }

            Thread.sleep(forTimeInterval: pollInterval)
        }
        return false
    }
}
