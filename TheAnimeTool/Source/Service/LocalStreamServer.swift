//
//  LocalStreamServer.swift
//  TheAnimeTool
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
    private var connections: [NWConnection] = []
    private var isStopped = false

    /// Incremented each time a new GET request arrives. Old streamBody loops
    /// check this and exit early when it changes, preventing them from
    /// re-requesting pieces for the OLD position at priority 7 after a seek.
    private var requestGeneration: Int = 0

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
        let entry = torrentHandle.snapshot.files.first(where: { $0.index == idx })
        self.fileSize = entry?.size ?? 0
        self.pieceLength = Int(torrentHandle.snapshot.pieceLength)
        self.totalPieces = Int(entry?.num_pieces ?? 0)
        self.beginPiece = Int(entry?.begin_idx ?? 0)
        self.endPiece = Int(entry?.end_idx ?? 0)
        // endPiece - beginPiece may be 1 more than totalPieces when the file
        // doesn't end on a piece boundary (LibTorrent-Swift's num_pieces
        // uses integer division which truncates the partial last piece).
        self.maxLocalPiece = max(Int(entry?.end_idx ?? 0) - Int(entry?.begin_idx ?? 0), self.totalPieces > 0 ? self.totalPieces - 1 : 0)
    }

    // MARK: - Start / Stop

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Use port 0 to let the system assign an available port
        listener = try NWListener(using: params, on: .any)

        let readySemaphore = DispatchSemaphore(value: 0)

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener?.port?.rawValue {
                    self?.port = port
                    print("LocalStreamServer: listening on port \(port)")
                }
                readySemaphore.signal()
            case .failed(let error):
                print("LocalStreamServer: failed — \(error)")
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
        _ = readySemaphore.wait(timeout: .now() + 2.0)
    }

    func stop() {
        isStopped = true
        listener?.cancel()
        listener = nil
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        print("LocalStreamServer: stopped")
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        queue.async { [weak self] in
            self?.connections.append(connection)
        }
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
        queue.async { [weak self] in
            self?.connections.removeAll(where: { $0 === connection })
        }
    }

    private func receiveRequest(_ connection: NWConnection) {
        // Read up to 8KB — more than enough for an HTTP request header.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self = self, !self.isStopped else { return }
            if let error = error {
                print("LocalStreamServer: receive error — \(error)")
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

        for line in lines {
            if line.lowercased().hasPrefix("range:") {
                let value = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("bytes=") {
                    let rangeStr = value.dropFirst(6)
                    let rangeParts = rangeStr.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                    if let startStr = rangeParts.first, let start = UInt64(startStr) {
                        rangeStart = start
                        hasRange = true
                    }
                    if rangeParts.count > 1, let endStr = rangeParts.last, !endStr.isEmpty, let end = UInt64(endStr) {
                        rangeEnd = min(end, fileSize > 0 ? fileSize - 1 : 0)
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

        if method == "HEAD" {
            let contentLength = rangeEnd - rangeStart + 1
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
        let contentLength = bodyLength ?? (rangeEnd - rangeStart + 1)
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
                print("LocalStreamServer: header send error — \(error)")
            }
        })
    }

    private func serveRange(connection: NWConnection, rangeStart: UInt64, rangeEnd: UInt64, hasRange: Bool) {
        let contentLength = rangeEnd - rangeStart + 1
        sendHeaders(connection: connection, rangeStart: rangeStart, rangeEnd: rangeEnd, hasRange: hasRange, bodyLength: contentLength)

        // Increment the generation so any previous streamBody loop exits early.
        // This prevents old streams from re-requesting stale pieces at priority 7
        // after a seek, which would steal bandwidth from the new seek position.
        requestGeneration += 1
        let myGeneration = requestGeneration

        // Stream body in chunks. Each chunk is read from the file only after
        // the pieces covering those bytes are confirmed downloaded.
        // Use a background queue so we don't block the NWListener queue.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.streamBody(connection: connection, offset: rangeStart, end: rangeEnd, generation: myGeneration)
        }
    }

    /// Streams file bytes from `offset` to `end` in chunks, waiting for each
    /// chunk's pieces to be available before reading from disk.
    /// Exits early if a newer request arrives (generation mismatch) to avoid
    /// re-requesting stale pieces and stealing bandwidth after a seek.
    private func streamBody(connection: NWConnection, offset: UInt64, end: UInt64, generation: Int) {
        guard !isStopped else { return }

        // Open the file
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            print("LocalStreamServer: cannot open file at \(filePath)")
            connection.cancel()
            return
        }
        defer { fileHandle.closeFile() }

        // Use the actual torrent piece length for chunk sizing.
        // Previously this was approximated as fileSize/totalPieces which differs
        // from the real piece length and caused ±1 mapping errors at boundaries.
        let chunkSize = UInt64(pieceLength > 0 ? pieceLength : 65536)

        var currentOffset = offset
        while currentOffset <= end && !isStopped && generation == requestGeneration {
            let readEnd = min(currentOffset + chunkSize - 1, end)

            // Which local pieces cover this byte range?
            // Uses exact pieceLength for mapping: localPiece = offset / pieceLength.
            // This is exact for single-file torrents (fileOffset=0). For multi-file
            // torrents where the file starts mid-piece, the actual piece may be 1
            // higher than our estimate, so we add +1 to lastLocalPiece. This margin
            // is harmless for single-file torrents (just waits for one extra piece)
            // and is clamped in waitForLocalPieces so out-of-bounds indices are safe.
            let firstLocalPiece = localPieceIndex(forByteOffset: currentOffset)
            let lastLocalPiece = localPieceIndex(forByteOffset: readEnd) + 1

            // Wait for ALL required pieces to be downloaded.
            // Returns true if pieces were already on disk (no waiting needed).
            let alreadyOnDisk = waitForLocalPieces(from: firstLocalPiece, to: lastLocalPiece)

            // Exit if a newer request superseded this one during the wait.
            if isStopped || generation != requestGeneration { break }

            // Read from file. For freshly-downloaded pieces, verify data
            // stability with a double-read to detect partial flushes.
            let readLength = Int(readEnd - currentOffset + 1)
            fileHandle.seek(toFileOffset: currentOffset)
            var data = fileHandle.readData(ofLength: readLength)

            if !data.isEmpty && data.allSatisfy({ $0 == 0 }) {
                // All zeros: piece data not flushed at all. Retry with flush.
                for _ in 0..<5 {
                    torrentHandle.flushCache()
                    Thread.sleep(forTimeInterval: 0.05)
                    fileHandle.seek(toFileOffset: currentOffset)
                    data = fileHandle.readData(ofLength: readLength)
                    if data.isEmpty || !data.allSatisfy({ $0 == 0 }) { break }
                }
            }

            // Double-read verification for freshly-downloaded data.
            // If libtorrent's disk thread is still writing when we read,
            // a second read after a brief delay may return different (more
            // complete) data. Skip for pieces already on disk (stable).
            if !alreadyOnDisk && !data.isEmpty && !data.allSatisfy({ $0 == 0 }) {
                Thread.sleep(forTimeInterval: 0.015)
                fileHandle.seek(toFileOffset: currentOffset)
                let verifyData = fileHandle.readData(ofLength: readLength)
                if verifyData != data {
                    // Data changed — flush was still in progress. Use newer
                    // read and give one more chance for it to stabilize.
                    data = verifyData
                    torrentHandle.flushCache()
                    Thread.sleep(forTimeInterval: 0.03)
                    fileHandle.seek(toFileOffset: currentOffset)
                    let finalData = fileHandle.readData(ofLength: readLength)
                    if !finalData.isEmpty { data = finalData }
                }
            }

            if data.isEmpty { break }

            // Send synchronously (block until sent)
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

        // After serving the range, wait for next request (keep-alive)
        if !isStopped {
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
        return min(index, totalPieces - 1)
    }

    /// Checks if a local piece (0-based index within the file) has been downloaded.
    /// Thread-safe: uses snapshotQueue to serialize torrentHandle access.
    private func isLocalPieceDownloaded(_ localIndex: Int) -> Bool {
        snapshotQueue.sync {
            torrentHandle.updateSnapshot()
            guard let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }),
                  let pieces = entry.pieces as? [NSNumber],
                  localIndex >= 0, localIndex < pieces.count else { return false }
            return pieces[localIndex].boolValue
        }
    }

    /// Blocks the current thread until all pieces from `firstLocal` to `lastLocal`
    /// (inclusive, 0-based) are downloaded. For pieces not yet on disk, sets priority
    /// 7 AND deadline to ensure libtorrent fetches them with top urgency.
    /// Re-boosts priority every ~500ms to counter TorrentStreamer's resetActiveWindow()
    /// which may lower our pieces' priority during the wait.
    /// Thread-safe: uses snapshotQueue to serialize torrentHandle access.
    ///
    /// - Returns: `true` if all pieces were already downloaded (no waiting),
    ///   `false` if we had to wait for at least one piece.
    @discardableResult
    private func waitForLocalPieces(from firstLocal: Int, to lastLocal: Int) -> Bool {
        // Clamp to valid piece array range
        let safeFirst = max(firstLocal, 0)
        let safeLast = min(lastLocal, totalPieces > 0 ? totalPieces - 1 : 0)

        guard safeFirst <= safeLast else { return true }

        // Quick check: are all pieces already on disk?
        var alreadyReady = true
        snapshotQueue.sync {
            torrentHandle.updateSnapshot()
            if let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }),
               let pieces = entry.pieces as? [NSNumber] {
                for localIdx in safeFirst...safeLast {
                    guard localIdx < pieces.count else { continue }
                    if !pieces[localIdx].boolValue {
                        alreadyReady = false
                        break
                    }
                }
            } else {
                alreadyReady = false
            }
        }

        if alreadyReady {
            // All pieces already on disk — no flush needed, no priority changes.
            return true
        }

        // Set priority THEN deadline on the needed pieces.
        // Priority must be > 0 or libtorrent ignores the deadline entirely.
        for localIdx in safeFirst...safeLast {
            let globalIdx = beginPiece + localIdx
            torrentHandle.setPiecePriority(globalIdx, priority: 7) // top priority
            let offset = min(localIdx - safeFirst, 1000) // Clamp to avoid Int32 overflow
            let deadline = Int32(5 + offset * 20) // 5ms base + 20ms/piece
            torrentHandle.setPieceDeadline(globalIdx, deadline: deadline)
        }

        // Poll until all pieces are available
        let pollInterval: TimeInterval = 0.05 // 50ms
        let maxWait: TimeInterval = 120.0 // Must match MPV's network-timeout in VideoPlayerViewController
        let startTime = Date()
        var reboostCounter = 0

        while !isStopped {
            var allReady = true
            snapshotQueue.sync {
                torrentHandle.updateSnapshot()
                if let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }),
                   let pieces = entry.pieces as? [NSNumber] {
                    for localIdx in safeFirst...safeLast {
                        guard localIdx < pieces.count else { continue }
                        if !pieces[localIdx].boolValue {
                            allReady = false
                            break
                        }
                    }
                } else {
                    allReady = false
                }
            }

            if allReady {
                // Flush libtorrent's disk write cache so piece data is on the
                // filesystem before we read it with FileHandle.
                torrentHandle.flushCache()
                Thread.sleep(forTimeInterval: 0.05)
                return false
            }

            // Re-boost priority every ~500ms (every 10 poll iterations).
            // TorrentStreamer.resetActiveWindow() may have lowered the priority
            // of our pieces while we were waiting. Re-setting priority 7 ensures
            // libtorrent continues to fetch them with top urgency.
            reboostCounter += 1
            if reboostCounter % 10 == 0 {
                for localIdx in safeFirst...safeLast {
                    let globalIdx = beginPiece + localIdx
                    torrentHandle.setPiecePriority(globalIdx, priority: 7)
                    let offset = min(localIdx - safeFirst, 1000)
                    let deadline = Int32(5 + offset * 20)
                    torrentHandle.setPieceDeadline(globalIdx, deadline: deadline)
                }
            }

            if Date().timeIntervalSince(startTime) > maxWait {
                print("LocalStreamServer: timeout waiting for pieces \(firstLocal)-\(lastLocal)")
                return false
            }

            Thread.sleep(forTimeInterval: pollInterval)
        }
        return false
    }
}
