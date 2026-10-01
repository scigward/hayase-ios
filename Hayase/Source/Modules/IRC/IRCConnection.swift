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
//  Reconnecting lives in the library's client, not in connections.ts, and so in
//  IRCClient here; this reports every closure through `onClose`. What this does
//  do, as connections.ts does, is retry a first attempt that failed before it
//  opened without the WebSocket subprotocol, which a gateway may reject.

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
    private var host = ""
    private var port = 0
    private var usesSubprotocol = true
    private var triedWithoutSubprotocol = false
    private let queue = DispatchQueue(label: "app.hayase.irc.connection")

    /// Wire-protocol convention from `onSocketMessage`: a single WebSocket
    /// text frame may contain more than one IRC line, so incoming data is
    /// buffered and split on `\n` rather than assumed to be one line per
    /// frame. Only ever touched on `queue`.
    private var incomingBuffer = ""

    func connect(host: String, port: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            self.host = host
            self.port = port
            self.usesSubprotocol = true
            self.triedWithoutSubprotocol = false
            self.connectLocked()
        }
    }

    private func connectLocked() {
        disposeLocked()
        guard var components = URLComponents(string: "wss://\(host)") else {
            callOnClose(IRCConnectionError.invalidHost, from: nil)
            return
        }
        components.port = port
        guard let url = components.url else {
            callOnClose(IRCConnectionError.invalidHost, from: nil)
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
        let task = usesSubprotocol
            ? session.webSocketTask(with: url, protocols: ["text.ircv3.net"])
            : session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()
        receiveLoop(on: task)
    }

    /// Sends one already-serialized IRC line as a single WebSocket text
    /// frame. Mirrors `writeLine`/`socket.send(line)` — no `\r\n` is
    /// appended here, matching upstream, since the frame boundary already
    /// delimits the message.
    func send(line: String) {
        guard let task, isConnected else { return }
        task.send(.string(line)) { [weak self] error in
            if let error {
                self?.callOnClose(error, from: task)
            }
        }
    }

    func close() {
        queue.async { [weak self] in
            self?.disposeLocked()
        }
    }

    private func receiveLoop(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.callOnClose(error, from: task)
            case .success(let message):
                switch message {
                case .string(let text):
                    self.queue.async { self.handleIncoming(text) }
                    self.receiveLoop(on: task)
                case .data:
                    // Mirrors onSocketMessage's rejection of binary frames —
                    // this protocol is text-only.
                    self.callOnClose(IRCConnectionError.unexpectedBinaryFrame, from: task)
                @unknown default:
                    self.receiveLoop(on: task)
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

    /// Only the current socket may close the connection: what a socket that was replaced or
    /// closed on purpose still reports must not take down its successor.
    private func callOnClose(_ error: Error?, from closing: URLSessionWebSocketTask?) {
        queue.async { [weak self] in
            guard let self else { return }
            if let closing, closing !== self.task { return }
            // `possible_protocol_error`: a first attempt that failed before it opened is tried
            // once more without the subprotocol.
            if closing != nil, !self.isConnected, self.usesSubprotocol, !self.triedWithoutSubprotocol {
                self.triedWithoutSubprotocol = true
                self.usesSubprotocol = false
                self.connectLocked()
                return
            }
            self.disposeLocked()
            let callback = self.onClose
            DispatchQueue.main.async { callback?(error) }
        }
    }
}

extension IRCConnection: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                     didOpenWithProtocol protocol: String?) {
        queue.async { [weak self] in
            guard let self, webSocketTask === self.task else { return }
            self.isConnected = true
        }
        let callback = onOpen
        DispatchQueue.main.async { callback?() }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                     didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                     reason: Data?) {
        callOnClose(nil, from: webSocketTask)
    }
}

enum IRCConnectionError: Error {
    case invalidHost
    case unexpectedBinaryFrame
}
