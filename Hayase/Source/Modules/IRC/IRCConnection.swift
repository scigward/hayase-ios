//
//  IRCConnection.swift
//  Hayase
//
//  Created by scigward.
//
//  Ported from src/lib/modules/irc/connections.ts. That file is a custom
//  transport handed to the JS IRC client — interface connects over a
//  WebSocket (`wss://host:port`), not a raw TCP socket, which is why this
//  uses `URLSessionWebSocketTask` rather than the `Network` framework.
//
//  Scope note: interface's `Connection` also implements auto-reconnect via
//  the underlying library's own retry logic (not shown here, since it lives
//  in client.js, not connections.ts). This port does a single connection
//  attempt and reports failure/closure via `onClose` rather than retrying
//  automatically — reconnection is a reasonable next increment, not
//  included here.

import Foundation

/// A minimal line-oriented WebSocket transport for IRC.
///
/// Security notes:
/// - Always connects over `wss://` (TLS). There is no plaintext fallback,
///   matching interface hardcoding `tls: true` for this network.
/// - `URLSession`'s default App Transport Security policy validates the
///   server's certificate chain; this type does not disable or override
///   that.
final class IRCConnection: NSObject {
    private(set) var isConnected = false

    var onOpen: (() -> Void)?
    var onLine: ((String) -> Void)?
    var onClose: ((Error?) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private let queue = DispatchQueue(label: "app.hayase.irc.connection")

    /// Wire-protocol convention from `onSocketMessage`: a single WebSocket
    /// text frame may contain more than one IRC line, so incoming data is
    /// buffered and split on `\n` rather than assumed to be one line per
    /// frame. Only ever touched on `queue`.
    private var incomingBuffer = ""

    func connect(host: String, port: Int) {
        queue.async { [weak self] in
            self?.connectLocked(host: host, port: port)
        }
    }

    private func connectLocked(host: String, port: Int) {
        disposeLocked()
        guard var components = URLComponents(string: "wss://\(host)") else {
            callOnClose(IRCConnectionError.invalidHost)
            return
        }
        components.port = port
        guard let url = components.url else {
            callOnClose(IRCConnectionError.invalidHost)
            return
        }

        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        // Mirrors `new WebSocket(ws_addr, this.protocol)` where `this.protocol`
        // defaults to `options.websocket_protocol`, which interface's connect()
        // call never overrides — so it falls through to the library's own
        // default, `'text.ircv3.net'`. This was missing from the first pass
        // of this file entirely; some IRC-over-WebSocket gateways key off the
        // subprotocol to know how to frame the connection.
        let task = session.webSocketTask(with: url, protocols: ["text.ircv3.net"])
        self.session = session
        self.task = task
        task.resume()
        receiveLoop()
    }

    /// Sends one already-serialized IRC line as a single WebSocket text
    /// frame. Mirrors `writeLine`/`socket.send(line)` — no `\r\n` is
    /// appended here, matching upstream, since the frame boundary already
    /// delimits the message.
    func send(line: String) {
        guard let task, isConnected else { return }
        task.send(.string(line)) { [weak self] error in
            if let error {
                self?.callOnClose(error)
            }
        }
    }

    func close() {
        queue.async { [weak self] in
            self?.disposeLocked()
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.callOnClose(error)
            case .success(let message):
                switch message {
                case .string(let text):
                    self.queue.async { self.handleIncoming(text) }
                    self.receiveLoop()
                case .data:
                    // Mirrors onSocketMessage's rejection of binary frames —
                    // this protocol is text-only.
                    self.callOnClose(IRCConnectionError.unexpectedBinaryFrame)
                @unknown default:
                    self.receiveLoop()
                }
            }
        }
    }

    /// Must only be called on `queue`. Mirrors `onSocketMessage`'s
    /// buffer-and-split-on-newline handling.
    private func handleIncoming(_ text: String) {
        incomingBuffer += text + "\n"
        var lines = incomingBuffer.components(separatedBy: "\n")
        if lines.last != "" {
            incomingBuffer = lines.removeLast()
        } else {
            lines.removeLast()
            incomingBuffer = ""
        }
        for line in lines {
            let callback = onLine
            DispatchQueue.main.async { callback?(line) }
        }
    }

    private func disposeLocked() {
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
        isConnected = false
        incomingBuffer = ""
    }

    private func callOnClose(_ error: Error?) {
        queue.async { [weak self] in
            self?.disposeLocked()
        }
        let callback = onClose
        DispatchQueue.main.async { callback?(error) }
    }
}

extension IRCConnection: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                     didOpenWithProtocol protocol: String?) {
        queue.async { [weak self] in
            self?.isConnected = true
        }
        let callback = onOpen
        DispatchQueue.main.async { callback?() }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                     didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                     reason: Data?) {
        callOnClose(nil)
    }
}

enum IRCConnectionError: Error {
    case invalidHost
    case unexpectedBinaryFrame
}
