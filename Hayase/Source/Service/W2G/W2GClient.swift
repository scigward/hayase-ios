// W2GClient.swift — Watch-Together P2P client
// Mirrors: hayase-app/interface/src/lib/modules/w2g/index.ts (W2GClient class)
//
// This is the iOS equivalent of the web's P2PT-based W2GClient.
// It connects to WebTorrent trackers via WebSocket, discovers peers via
// WebRTC offer/answer exchange, and synchronises playback state + chat
// over WebRTC data channels — exactly like the web implementation.

import Foundation
import CommonCrypto
import WebRTC

// MARK: - W2GClientDelegate

/// Mirrors the web's EventEmitter events: `'index'` and `'player'`.
protocol W2GClientDelegate: AnyObject {
    /// Remote peer changed the media file index.
    func w2gClient(_ client: W2GClient, didReceiveIndexChange index: Int)
    /// Remote peer changed the playback state (pause / seek).
    func w2gClient(_ client: W2GClient, didReceivePlayerState state: W2GPlayerState)
    /// Remote peer changed media entirely (different torrent).
    func w2gClient(_ client: W2GClient, didReceiveMediaChange media: W2GMediaState)
    /// Peer list changed (join/leave).
    func w2gClientPeersDidChange(_ client: W2GClient)
    /// Messages list changed.
    func w2gClientMessagesDidChange(_ client: W2GClient)
}

// Allow optional delegate methods.
extension W2GClientDelegate {
    func w2gClient(_ client: W2GClient, didReceiveMediaChange media: W2GMediaState) {}
}

// MARK: - W2GClient

/// The main Watch-Together client.
/// Mirrors `interface/w2g/index.ts → class W2GClient extends EventEmitter`.
final class W2GClient {

    // MARK: - Public state (mirrors web properties)

    /// Current synchronised player state.
    var player = W2GPlayerState(paused: true, time: 0)

    /// Current file index within the torrent.
    var index: Int = 0

    /// Media the host is playing (torrent hash + AniList ID + episode).
    var media: W2GMediaState?

    /// Whether this client is the session host.
    var isHost: Bool

    /// 8-char hex lobby code (used as the WebTorrent info-hash identifier).
    let code: String

    /// Flag set by `destroy()`.
    private(set) var destroyed = false

    /// The local user.
    let selfUser: W2GChatUser

    /// Connected peers keyed by peerID hex. Mirrors `peers` writable in web.
    private(set) var peers: [String: PeerEntry] = [:]

    /// Chat messages. Mirrors `messages` writable in web.
    private(set) var messages: [W2GChatMessage] = []

    weak var delegate: W2GClientDelegate?

    /// Lightweight callback for player state updates (used by VideoPlayerViewController
    /// to receive remote state without being the full W2GClientDelegate).
    /// Mirrors player.svelte: `$w2globby?.on('player', updateState)`.
    var onPlayerStateReceived: ((W2GPlayerState) -> Void)?

    /// Invite link (mirrors web `get inviteLink()`).
    var inviteLink: String {
        "https://hayase.watch/w2g/\(code)"
    }

    // MARK: - Peer entry

    struct PeerEntry {
        let user: W2GChatUser
        var peer: W2GPeer?
    }

    // MARK: - Private networking state

    /// WebTorrent tracker URLs (base64-decoded, same as web).
    private static let announceURLs: [String] = [
        "wss://tracker.openwebtorrent.com",
        "wss://tracker.webtorrent.dev",
        "wss://tracker.files.fm:7073/announce",
        "wss://tracker.btorrent.xyz/"
    ]

    /// Our 20-byte peer ID (hex + binary-string forms).
    private let peerIDHex: String
    private let peerIDBinary: String

    /// SHA-1 info hash of the lobby code (hex + binary-string forms).
    private let infoHashHex: String
    private let infoHashBinary: String

    /// Active tracker connections.
    private var trackers: [W2GTrackerClient] = []

    /// Peers keyed by peerID hex → { channelName → W2GPeer }.
    /// Mirrors P2PT's `this.peers[peer.id][peer.channelName]`.
    private var peerChannels: [String: [String: W2GPeer]] = [:]

    /// Pending offers keyed by offerID hex → W2GPeer.
    private var pendingOffers: [String: W2GPeer] = [:]

    /// Message chunking state (mirrors P2PT `msgChunks`).
    private var msgChunks: [Int: [Int: String]] = [:]

    /// P2PT JSON message identifier character.
    private static let jsonMessageIdentifier: Character = "^"
    /// Max data channel message length (16 KB).
    private static let maxMessageLength = 16000

    /// Re-announce timer.
    private var announceTimer: Timer?

    // MARK: - Init (mirrors web constructor)

    init(code: String, isHost: Bool, media: W2GMediaState? = nil) {
        self.code = code
        self.isHost = isHost
        self.media = media
        self.selfUser = W2GChatUser.fromLocalViewer()

        // Generate 20 random bytes for peer ID (mirrors P2PT).
        self.peerIDHex = Self.generateRandomHex(length: 40)
        self.peerIDBinary = W2GTrackerClient.hexToBinary(peerIDHex)

        // SHA-1 hash of the lobby code → info hash (mirrors P2PT `hash(identifierString)`).
        self.infoHashHex = Self.sha1Hex(code).lowercased()
        self.infoHashBinary = W2GTrackerClient.hexToBinary(infoHashHex)

        // Add self to peers list.
        peers[selfUser.id] = PeerEntry(user: selfUser, peer: nil)

        // Connect to all trackers and start discovering peers.
        start()
    }

    // MARK: - Start / Stop

    private func start() {
        for url in Self.announceURLs {
            let tracker = W2GTrackerClient(
                announceURL: url,
                peerIDBinary: peerIDBinary,
                infoHashBinary: infoHashBinary
            )
            tracker.delegate = self
            trackers.append(tracker)
            tracker.connect()
        }

        // Re-announce every 30s (mirrors DEFAULT_ANNOUNCE_INTERVAL).
        announceTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.announceToAllTrackers()
        }
    }

    func destroy() {
        guard !destroyed else { return }
        destroyed = true
        announceTimer?.invalidate()
        announceTimer = nil

        // Destroy all peers.
        for (_, channels) in peerChannels {
            for (_, peer) in channels {
                peer.destroy()
            }
        }
        peerChannels.removeAll()
        pendingOffers.removeAll()
        msgChunks.removeAll()
        offerCallbacks.removeAll()
        answerCallbacks.removeAll()
        temporaryPeerIDs.removeAll()

        // Destroy all trackers.
        for tracker in trackers {
            tracker.destroy()
        }
        trackers.removeAll()

        isHost = false
        peers.removeAll()
    }

    // MARK: - Public API (mirrors web methods)

    /// Called when the local user changes media (torrent).
    /// Mirrors web `mediaChange(media)`.
    func mediaChange(_ media: W2GMediaState) {
        if self.media?.torrent != media.torrent {
            self.media = media
            self.isHost = true
            sendToPeers(W2GEvent.mediaEvent(media))
        }
    }

    /// Called when the local file index changes within the torrent.
    /// Mirrors web `mediaIndexChanged(index)`.
    func mediaIndexChanged(_ index: Int) {
        if self.index != index {
            self.index = index
            sendToPeers(W2GEvent.indexEvent(index))
        }
    }

    /// Called when local playback state changes (pause/seek).
    /// Mirrors web `playerStateChanged(state)`.
    func playerStateChanged(_ state: W2GPlayerState) {
        if playerStateDidChange(state) {
            sendToPeers(W2GEvent.playerEvent(state))
        }
    }

    /// Send a chat message.
    /// Mirrors web `message(message)`.
    func sendMessage(_ text: String) {
        let msg = W2GChatMessage(message: text, user: selfUser, type: .outgoing, date: Date())
        messages.append(msg)
        delegate?.w2gClientMessagesDidChange(self)
        sendToPeers(W2GEvent.messageEvent(text))
    }

    // MARK: - Player state helpers (mirrors web)

    /// Returns true if state actually changed. Mirrors `_playerStateChanged`.
    private func playerStateDidChange(_ state: W2GPlayerState) -> Bool {
        if player.paused != state.paused || player.time != state.time {
            player = state
            return true
        }
        return false
    }

    /// Checks remote state with 2-second tolerance. Mirrors `_remotePlayerStateChanged`.
    private func remotePlayerStateDidChange(_ state: W2GPlayerState) -> Bool {
        if abs(player.time - state.time) > 2 || player.paused != state.paused {
            player = state
            return true
        }
        return false
    }

    // MARK: - Send to peers (mirrors web `_sendToPeers` / `_sendEvent`)

    private func sendToPeers(_ event: W2GEvent) {
        for (peerID, channels) in peerChannels {
            if peerID == selfUser.id { continue }
            for (_, peer) in channels where peer.isConnected {
                sendP2PTMessage(to: peer, event: event)
                break // only need one connected channel per peer
            }
        }
    }

    private func sendEvent(to peer: W2GPeer, event: W2GEvent) {
        sendP2PTMessage(to: peer, event: event)
    }

    /// Send initial session state to a newly connected peer.
    /// Mirrors web `_sendInitialSessionState(peer)`.
    private func sendInitialSessionState(to peer: W2GPeer) {
        sendEvent(to: peer, event: W2GEvent.mediaEvent(media))
        sendEvent(to: peer, event: W2GEvent.indexEvent(index))
        sendEvent(to: peer, event: W2GEvent.playerEvent(player))
    }

    // MARK: - P2PT message protocol (mirrors p2pt.js send/receive)

    /// Encode and send a W2GEvent over a peer's data channel using P2PT framing.
    private func sendP2PTMessage(to peer: W2GPeer, event: W2GEvent, msgID: Int? = nil) {
        guard let eventData = try? JSONEncoder().encode(event),
              var msgString = String(data: eventData, encoding: .utf8) else { return }

        let id = msgID ?? Int.random(in: 100000...199999)
        var chunk = 0

        while !msgString.isEmpty {
            let end = msgString.index(msgString.startIndex,
                                       offsetBy: min(Self.maxMessageLength, msgString.count))
            let slice = String(msgString[msgString.startIndex..<end])
            msgString = String(msgString[end...])

            var envelope: [String: Any] = [
                "id": id,
                "msg": slice,
                "c": chunk,
                "o": 1  // indicating object payload
            ]
            if msgString.isEmpty {
                envelope["last"] = true
            }

            if let json = try? JSONSerialization.data(withJSONObject: envelope),
               let jsonStr = String(data: json, encoding: .utf8) {
                peer.sendString(String(Self.jsonMessageIdentifier) + jsonStr)
            }
            chunk += 1
        }
    }

    // MARK: - Receive message handling (mirrors p2pt.js data handler + W2GClient._onMsg)

    private func handleDataFromPeer(_ peer: W2GPeer, data: Data) {
        guard let text = String(data: data, encoding: .utf8),
              text.first == Self.jsonMessageIdentifier else { return }

        let jsonString = String(text.dropFirst())
        guard let jsonData = jsonString.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let msgID = envelope["id"] as? Int,
              let chunkIndex = envelope["c"] as? Int,
              let msgSlice = envelope["msg"] as? String else { return }

        // Chunk assembly (mirrors P2PT `_chunkHandler`).
        if msgChunks[msgID] == nil {
            msgChunks[msgID] = [:]
        }
        msgChunks[msgID]?[chunkIndex] = msgSlice

        guard envelope["last"] != nil else { return }  // wait for last chunk

        // Assemble full message — verify all chunks 0..N are present.
        let chunks = msgChunks[msgID] ?? [:]
        let totalChunks = chunkIndex + 1  // last chunk's index + 1
        // Verify sequential: every index from 0 to totalChunks-1 must exist.
        for i in 0..<totalChunks {
            guard chunks[i] != nil else {
                // Missing intermediate chunk; discard incomplete message.
                msgChunks.removeValue(forKey: msgID)
                return
            }
        }
        let fullMsg = (0..<totalChunks).map { chunks[$0]! }.joined()
        msgChunks.removeValue(forKey: msgID)

        // The payload is a JSON-encoded W2GEvent (o=1 means it was an object).
        guard let fullData = fullMsg.data(using: .utf8),
              let event = try? JSONDecoder().decode(W2GEvent.self, from: fullData) else { return }

        handleW2GEvent(event, from: peer)
    }

    /// Process a decoded W2GEvent. Mirrors web `_onMsg`.
    private func handleW2GEvent(_ event: W2GEvent, from peer: W2GPeer) {
        switch event.type {
        case .`init`:
            // Decode ChatUser from payload.
            if let userData = try? JSONSerialization.data(withJSONObject: event.payload.value),
               let user = try? JSONDecoder().decode(W2GChatUser.self, from: userData) {
                peers[peer.id] = PeerEntry(user: user, peer: peer)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.w2gClientPeersDidChange(self)
                }
            }

        case .media:
            guard let dict = event.payload.value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let mediaState = try? JSONDecoder().decode(W2GMediaState.self, from: data) else { return }
            if mediaState.torrent != self.media?.torrent {
                self.isHost = false
                self.media = mediaState
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.w2gClient(self, didReceiveMediaChange: mediaState)
                }
            }

        case .index:
            guard let newIndex = event.payload.value as? Int else { return }
            if self.index != newIndex {
                self.index = newIndex
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.w2gClient(self, didReceiveIndexChange: newIndex)
                }
            }

        case .player:
            guard let dict = event.payload.value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let state = try? JSONDecoder().decode(W2GPlayerState.self, from: data) else { return }
            if remotePlayerStateDidChange(state) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.w2gClient(self, didReceivePlayerState: state)
                    self.onPlayerStateReceived?(state)
                }
            }

        case .message:
            guard let text = event.payload.value as? String else { return }
            let user = peers[peer.id]?.user ?? W2GChatUser(id: peer.id, name: "Unknown", avatarURL: nil)
            let msg = W2GChatMessage(message: text, user: user, type: .incoming, date: Date())
            messages.append(msg)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.w2gClientMessagesDidChange(self)
            }
        }
    }

    // MARK: - Announce / Offer generation

    /// Generate SDP offers and send them to all connected trackers.
    private func announceToAllTrackers() {
        guard !destroyed else { return }
        let numwant = 5
        generateOffers(count: numwant) { [weak self] offers in
            guard let self, !self.destroyed else { return }
            for tracker in self.trackers where !tracker.destroyed {
                tracker.announce(offers: offers)
            }
        }
    }

    /// Create `count` WebRTC peer connections with SDP offers.
    /// Mirrors P2PT `_generateOffers`.
    private func generateOffers(count: Int, completion: @escaping ([[String: Any]]) -> Void) {
        var offers: [[String: Any]] = []
        var remaining = count
        let lock = NSLock()

        for _ in 0..<count {
            let offerID = Self.generateRandomHex(length: 40)
            let peer = W2GPeer(isInitiator: true, offerID: offerID)
            peer.delegate = self
            pendingOffers[offerID] = peer
            peer.createOffer()

            // The offer SDP will fire asynchronously via W2GPeerDelegate.
            // We store a temporary callback to collect offers.
            offerCallbacks[offerID] = { sdp in
                let offerDict: [String: Any] = [
                    "offer": ["type": "offer", "sdp": sdp.sdp],
                    "offer_id": W2GTrackerClient.hexToBinary(offerID)
                ]
                lock.lock()
                offers.append(offerDict)
                remaining -= 1
                let done = remaining == 0
                lock.unlock()

                if done {
                    completion(offers)
                }
            }

            // Timeout: if this offer doesn't complete within 50s, skip it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 50) { [weak self] in
                guard let self else { return }
                if self.pendingOffers[offerID] != nil && self.offerCallbacks[offerID] != nil {
                    self.offerCallbacks.removeValue(forKey: offerID)
                    self.pendingOffers[offerID]?.destroy()
                    self.pendingOffers.removeValue(forKey: offerID)
                    lock.lock()
                    remaining -= 1
                    let done = remaining == 0
                    lock.unlock()
                    if done { completion(offers) }
                }
            }
        }
    }

    /// Temporary storage for offer SDP callbacks (offerID → callback).
    private var offerCallbacks: [String: (RTCSessionDescription) -> Void] = [:]

    /// Temporary storage for answer SDP callbacks.
    private var answerCallbacks: [String: (RTCSessionDescription) -> Void] = [:]
    /// Temporary peer ID assignments (offerID → peerID hex).
    private var temporaryPeerIDs: [String: String] = [:]

    // MARK: - Peer lifecycle helpers (mirrors P2PT._removePeer)

    private func handlePeerConnect(_ peer: W2GPeer) {
        let peerID = peer.id
        let isNew = peerChannels[peerID] == nil || peerChannels[peerID]?.isEmpty == true

        if peerChannels[peerID] == nil {
            peerChannels[peerID] = [:]
        }
        peerChannels[peerID]?[peer.offerID] = peer

        if isNew {
            // Send init event.
            sendEvent(to: peer, event: W2GEvent.initEvent(user: selfUser))
            // If host, send full session state.
            if isHost {
                sendInitialSessionState(to: peer)
            }
            delegate?.w2gClientPeersDidChange(self)
        }
    }

    private func handlePeerDisconnect(_ peer: W2GPeer) {
        let peerID = peer.id
        peerChannels[peerID]?.removeValue(forKey: peer.offerID)

        // If all channels for this peer are gone, remove the peer entirely.
        if peerChannels[peerID]?.isEmpty == true {
            peerChannels.removeValue(forKey: peerID)
            peers.removeValue(forKey: peerID)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.w2gClientPeersDidChange(self)
            }
        }

        // Clean up any pending offers for this peer.
        peer.destroy()
    }

    // MARK: - Utilities

    /// Generate random hex string of given length.
    static func generateRandomHex(length: Int) -> String {
        (0..<length).map { _ in String(format: "%x", Int.random(in: 0...15)) }.joined()
    }

    /// SHA-1 hex digest of a string (used to turn lobby code → info hash).
    private static func sha1Hex(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA1(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - W2GTrackerClientDelegate

extension W2GClient: W2GTrackerClientDelegate {

    func trackerDidConnect(_ tracker: W2GTrackerClient) {
        // Once connected, announce with offers.
        announceToAllTrackers()
    }

    func trackerDidUpdate(_ tracker: W2GTrackerClient) {
        // Could log tracker stats here.
    }

    func trackerDidDisconnect(_ tracker: W2GTrackerClient) {
        // Reconnect is handled internally by the tracker client.
    }

    func tracker(_ tracker: W2GTrackerClient,
                 didReceiveOffer sdp: [String: Any],
                 fromPeerID peerID: String, offerID: String) {
        // A remote peer sent us an offer → create a non-initiator peer, signal the offer,
        // and send back an answer through the tracker.
        guard let sdpString = sdp["sdp"] as? String else { return }

        let peer = W2GPeer(isInitiator: false, offerID: offerID)
        peer.delegate = self

        // Store temporarily so we can route the answer back.
        answerCallbacks[offerID] = { [weak self] answerSDP in
            guard let self else { return }
            let answerDict: [String: Any] = ["type": "answer", "sdp": answerSDP.sdp]
            tracker.sendAnswer(
                answerSDP: answerDict,
                toPeerIDBinary: W2GTrackerClient.hexToBinary(peerID),
                offerIDBinary: W2GTrackerClient.hexToBinary(offerID)
            )
        }

        // Feed the remote offer SDP to the peer.
        let rtcSDP = RTCSessionDescription(type: .offer, sdp: sdpString)
        peer.signal(remoteSDP: rtcSDP)

        // The peer will be stored when it fires peerDidConnect.
        // Temporarily assign its ID from the tracker data.
        temporaryPeerIDs[peer.offerID] = peerID
    }

    func tracker(_ tracker: W2GTrackerClient,
                 didReceiveAnswer sdp: [String: Any],
                 fromPeerID peerID: String, offerID: String) {
        // An answer to one of our pending offers.
        guard let sdpString = sdp["sdp"] as? String,
              let peer = pendingOffers[offerID] else { return }

        // Assign the peer ID now that we know who answered.
        temporaryPeerIDs[peer.offerID] = peerID

        let rtcSDP = RTCSessionDescription(type: .answer, sdp: sdpString)
        peer.signal(remoteSDP: rtcSDP)

        pendingOffers.removeValue(forKey: offerID)
    }
}

// MARK: - W2GPeerDelegate

extension W2GClient: W2GPeerDelegate {

    func peer(_ peer: W2GPeer, didGenerateLocalSDP sdp: RTCSessionDescription) {
        // For initiator peers: the SDP offer is ready → pass to the offer callback.
        if peer.isInitiator {
            offerCallbacks[peer.offerID]?(sdp)
            offerCallbacks.removeValue(forKey: peer.offerID)
        } else {
            // For answerer peers: the SDP answer is ready → pass to the answer callback.
            answerCallbacks[peer.offerID]?(sdp)
            answerCallbacks.removeValue(forKey: peer.offerID)
        }
    }

    func peerDidConnect(_ peer: W2GPeer) {
        // Assign the peer's ID from the tracker data.
        if let peerID = temporaryPeerIDs[peer.offerID] {
            peer.id = peerID
            temporaryPeerIDs.removeValue(forKey: peer.offerID)
        }
        handlePeerConnect(peer)
    }

    func peer(_ peer: W2GPeer, didReceiveMessage data: Data) {
        handleDataFromPeer(peer, data: data)
    }

    func peerDidDisconnect(_ peer: W2GPeer) {
        handlePeerDisconnect(peer)
    }
}
