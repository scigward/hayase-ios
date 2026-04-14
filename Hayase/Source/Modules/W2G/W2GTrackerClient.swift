// W2GTrackerClient.swift — WebSocket client for a single WebTorrent tracker
// Mirrors: bittorrent-tracker/lib/client/websocket-tracker.js
//
// WebTorrent tracker protocol (JSON over WebSocket):
//   Client → Tracker: { action: "announce", info_hash, peer_id, offers: [{ offer, offer_id }], numwant }
//   Tracker → Client: { action: "announce", offer/answer, peer_id, offer_id, info_hash }
//
// Uses Starscream for WebSocket (https://github.com/daltoniam/Starscream).

import Foundation
import Starscream

// MARK: - Delegate

protocol W2GTrackerClientDelegate: AnyObject {
    /// Tracker relayed a remote offer — create a peer and send an answer back.
    func tracker(_ tracker: W2GTrackerClient,
                 didReceiveOffer sdp: [String: Any],
                 fromPeerID peerID: String,
                 offerID: String)

    /// Tracker relayed an answer to one of our pending offers.
    func tracker(_ tracker: W2GTrackerClient,
                 didReceiveAnswer sdp: [String: Any],
                 fromPeerID peerID: String,
                 offerID: String)

    /// Tracker responded with an update (peer count etc.).
    func trackerDidUpdate(_ tracker: W2GTrackerClient)

    /// Tracker socket connected / reconnected.
    func trackerDidConnect(_ tracker: W2GTrackerClient)

    /// Tracker socket disconnected or errored.
    func trackerDidDisconnect(_ tracker: W2GTrackerClient)
}

// MARK: - W2GTrackerClient

/// Manages a single WebSocket connection to a WebTorrent tracker for signalling.
/// Mirrors the lifecycle of `bittorrent-tracker/websocket-tracker.js`.
final class W2GTrackerClient: NSObject {

    let announceURL: String
    weak var delegate: W2GTrackerClientDelegate?

    /// The client's peer ID binary string (20 random bytes → hex → binary string).
    private let peerIDBinary: String
    /// The info hash binary string derived from the lobby code (SHA-1 hex → binary string).
    private let infoHashBinary: String

    private var socket: WebSocket?
    private var isConnected = false
    private(set) var destroyed = false

    // Reconnect state (mirrors websocket-tracker.js)
    private var reconnecting = false
    private var retries = 0
    private var reconnectWork: DispatchWorkItem?

    private static let reconnectMinimum: TimeInterval = 10
    private static let reconnectMaximum: TimeInterval = 3600
    private static let reconnectVariance: TimeInterval = 300

    // MARK: - Init

    init(announceURL: String, peerIDBinary: String, infoHashBinary: String) {
        self.announceURL = announceURL
        self.peerIDBinary = peerIDBinary
        self.infoHashBinary = infoHashBinary
        super.init()
    }

    // MARK: - Connect

    func connect() {
        guard !destroyed, let url = URL(string: announceURL) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let ws = WebSocket(request: request)
        ws.delegate = self
        self.socket = ws
        ws.connect()
    }

    // MARK: - Announce with SDP offers

    /// Send an announce with SDP offers so the tracker can pair us with peers.
    /// Mirrors `websocket-tracker.js → announce()` with `_generateOffers`.
    func announce(offers: [[String: Any]]) {
        guard !destroyed, isConnected else { return }
        let params: [String: Any] = [
            "action": "announce",
            "info_hash": infoHashBinary,
            "peer_id": peerIDBinary,
            "numwant": offers.count,
            "uploaded": 0,
            "downloaded": 0,
            "offers": offers
        ]
        send(params)
    }

    /// Send an SDP answer back through the tracker for a specific offer.
    /// Mirrors the answer path in `websocket-tracker.js → _onAnnounceResponse`.
    func sendAnswer(answerSDP: [String: Any], toPeerIDBinary: String, offerIDBinary: String) {
        guard !destroyed, isConnected else { return }
        let params: [String: Any] = [
            "action": "announce",
            "info_hash": infoHashBinary,
            "peer_id": peerIDBinary,
            "to_peer_id": toPeerIDBinary,
            "answer": answerSDP,
            "offer_id": offerIDBinary
        ]
        send(params)
    }

    // MARK: - Send

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else { return }
        socket?.write(string: string)
    }

    // MARK: - Handle incoming message

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String, action == "announce" else { return }

        // Verify info_hash matches ours.
        if let ih = json["info_hash"] as? String, ih != infoHashBinary { return }
        // Ignore our own messages.
        if let pid = json["peer_id"] as? String, pid == peerIDBinary { return }

        // Tracker update (peer count).
        if json["complete"] != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.trackerDidUpdate(self)
            }
        }

        // Remote OFFER → we need to create a peer and answer.
        if let offerDict = json["offer"] as? [String: Any],
           let remotePeerIDBin = json["peer_id"] as? String,
           let offerIDBin = json["offer_id"] as? String {
            let remotePeerIDHex = Self.binaryToHex(remotePeerIDBin)
            let offerIDHex = Self.binaryToHex(offerIDBin)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.tracker(self, didReceiveOffer: offerDict,
                                       fromPeerID: remotePeerIDHex, offerID: offerIDHex)
            }
        }

        // Remote ANSWER to one of our pending offers.
        if let answerDict = json["answer"] as? [String: Any],
           let remotePeerIDBin = json["peer_id"] as? String,
           let offerIDBin = json["offer_id"] as? String {
            let remotePeerIDHex = Self.binaryToHex(remotePeerIDBin)
            let offerIDHex = Self.binaryToHex(offerIDBin)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.tracker(self, didReceiveAnswer: answerDict,
                                       fromPeerID: remotePeerIDHex, offerID: offerIDHex)
            }
        }
    }

    // MARK: - Reconnect (mirrors websocket-tracker.js)

    private func startReconnect() {
        guard !destroyed else { return }
        reconnecting = true
        let variance = Double.random(in: 0...Self.reconnectVariance)
        let delay = min(pow(2.0, Double(retries)) * Self.reconnectMinimum,
                        Self.reconnectMaximum) + variance
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.destroyed else { return }
            self.retries += 1
            self.connect()
        }
        reconnectWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Destroy

    func destroy() {
        destroyed = true
        reconnectWork?.cancel()
        socket?.disconnect()
        socket = nil
    }

    // MARK: - Hex ↔ Binary-string utilities
    // The WebTorrent tracker protocol transmits peer_id and info_hash as
    // "binary strings" (one byte per character). These helpers convert.

    /// Hex → binary string (one character per byte).
    static func hexToBinary(_ hex: String) -> String {
        var result = ""
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[idx..<next], radix: 16) {
                result.append(Character(UnicodeScalar(byte)))
            }
            idx = next
        }
        return result
    }

    /// Binary string → hex.
    static func binaryToHex(_ binary: String) -> String {
        binary.unicodeScalars.map { String(format: "%02x", $0.value) }.joined()
    }
}

// MARK: - Starscream WebSocketDelegate

extension W2GTrackerClient: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: any WebSocketClient) {
        switch event {
        case .connected:
            isConnected = true
            if reconnecting {
                reconnecting = false
                retries = 0
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.trackerDidConnect(self)
            }

        case .disconnected, .cancelled:
            isConnected = false
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.trackerDidDisconnect(self)
            }
            startReconnect()

        case .text(let text):
            handleMessage(text)

        case .binary(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleMessage(text)
            }

        case .error:
            isConnected = false
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.trackerDidDisconnect(self)
            }
            startReconnect()

        default:
            break
        }
    }
}
