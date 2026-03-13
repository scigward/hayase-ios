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

    /// Number of pieces for this file (from FileEntry.num_pieces).
    private let totalPieces: Int

    /// Global piece index where this file starts (FileEntry.begin_idx).
    private let beginPiece: Int

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "LocalStreamServer", qos: .userInitiated)
    /// Serial queue to protect torrentHandle.updateSnapshot() calls.
    private let snapshotQueue = DispatchQueue(label: "LocalStreamServer.snapshot")
    private var connections: [NWConnection] = []
    private var isStopped = false

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
        self.totalPieces = Int(entry?.num_pieces ?? 0)
        self.beginPiece = Int(entry?.begin_idx ?? 0)
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

        // Stream body in chunks. Each chunk is read from the file only after
        // the pieces covering those bytes are confirmed downloaded.
        // Use a background queue so we don't block the NWListener queue.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.streamBody(connection: connection, offset: rangeStart, end: rangeEnd)
        }
    }

    /// Streams file bytes from `offset` to `end` in chunks, waiting for each
    /// chunk's pieces to be available before reading from disk.
    private func streamBody(connection: NWConnection, offset: UInt64, end: UInt64) {
        guard !isStopped else { return }

        // Open the file
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            print("LocalStreamServer: cannot open file at \(filePath)")
            connection.cancel()
            return
        }
        defer { fileHandle.closeFile() }

        // Approximate piece length (bytes per piece for this file)
        let approxPieceLength: UInt64 = totalPieces > 0 ? max(fileSize / UInt64(totalPieces), 1) : 65536
        // Read in chunks of ~1 piece
        let chunkSize = approxPieceLength

        var currentOffset = offset
        while currentOffset <= end && !isStopped {
            let readEnd = min(currentOffset + chunkSize - 1, end)

            // Which pieces cover this byte range?
            let firstLocalPiece = localPieceIndex(forByteOffset: currentOffset)
            let lastLocalPiece = localPieceIndex(forByteOffset: readEnd)

            // Wait for ALL required pieces to be downloaded
            waitForLocalPieces(from: firstLocalPiece, to: lastLocalPiece)

            if isStopped { break }

            // Read from file — flushCache() in waitForLocalPieces ensures data
            // is on disk. Keep a single retry as a safety net.
            let readLength = Int(readEnd - currentOffset + 1)
            fileHandle.seek(toFileOffset: currentOffset)
            var data = fileHandle.readData(ofLength: readLength)
            if !data.isEmpty && data.allSatisfy({ $0 == 0 }) {
                // Safety retry: flush again and re-read
                torrentHandle.flushCache()
                Thread.sleep(forTimeInterval: 0.05)
                fileHandle.seek(toFileOffset: currentOffset)
                data = fileHandle.readData(ofLength: readLength)
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
    private func localPieceIndex(forByteOffset offset: UInt64) -> Int {
        guard totalPieces > 0, fileSize > 0 else { return 0 }
        // localIndex = offset * totalPieces / fileSize
        // Using integer math to avoid overflow
        let index = Int((offset * UInt64(totalPieces)) / fileSize)
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
    /// (inclusive, 0-based) are downloaded. Sets urgent deadlines to prioritize them.
    /// Thread-safe: uses snapshotQueue to serialize torrentHandle access.
    private func waitForLocalPieces(from firstLocal: Int, to lastLocal: Int) {
        // Set urgent deadlines on the needed pieces (clamped to avoid overflow)
        for localIdx in firstLocal...lastLocal {
            let globalIdx = beginPiece + localIdx
            let offset = min(localIdx - firstLocal, 1000) // Clamp to avoid Int32 overflow
            let deadline = Int32(5 + offset * 20) // 5ms base + 20ms/piece
            torrentHandle.setPieceDeadline(globalIdx, deadline: deadline)
        }

        // Poll until all pieces are available
        let pollInterval: TimeInterval = 0.05 // 50ms
        let maxWait: TimeInterval = 120.0 // Must match MPV's network-timeout in VideoPlayerViewController
        let startTime = Date()

        while !isStopped {
            var allReady = true
            snapshotQueue.sync {
                torrentHandle.updateSnapshot()
                if let entry = torrentHandle.snapshot.files.first(where: { $0.index == fileIndex }),
                   let pieces = entry.pieces as? [NSNumber] {
                    for localIdx in firstLocal...lastLocal {
                        if localIdx < pieces.count && !pieces[localIdx].boolValue {
                            allReady = false
                            break
                        }
                    }
                } else {
                    // Can't read piece status — not ready.
                    allReady = false
                }
            }

            if allReady {
                // Flush libtorrent's disk write cache so piece data is on the
                // filesystem before we read it with FileHandle. Without this,
                // hash-verified pieces may still be in memory, causing zero reads.
                torrentHandle.flushCache()
                return
            }

            if Date().timeIntervalSince(startTime) > maxWait {
                print("LocalStreamServer: timeout waiting for pieces \(firstLocal)-\(lastLocal)")
                return
            }

            Thread.sleep(forTimeInterval: pollInterval)
        }
    }
}
