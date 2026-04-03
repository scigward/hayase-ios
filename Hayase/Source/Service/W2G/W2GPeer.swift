// W2GPeer.swift — WebRTC peer connection + data channel wrapper
// Mirrors the role of simple-peer in P2PT: manages a single RTCPeerConnection
// with a data channel for JSON messaging, plus ICE candidate handling.
//
// Uses stasel/WebRTC SPM package (https://github.com/stasel/WebRTC).

import Foundation
import WebRTC

// MARK: - W2GPeerDelegate

protocol W2GPeerDelegate: AnyObject {
    /// A local ICE candidate was generated (trickle ICE disabled — this fires once
    /// gathering completes with the full SDP, mirroring simple-peer `trickle: false`).
    func peer(_ peer: W2GPeer, didGenerateLocalSDP sdp: RTCSessionDescription)

    /// The peer connection was established and the data channel is open.
    func peerDidConnect(_ peer: W2GPeer)

    /// The peer sent us a JSON-encoded message over the data channel.
    func peer(_ peer: W2GPeer, didReceiveMessage data: Data)

    /// The peer connection closed or errored.
    func peerDidDisconnect(_ peer: W2GPeer)
}

// MARK: - W2GPeer

/// Wraps a single RTCPeerConnection + RTCDataChannel.
/// Models the same lifecycle as one `simple-peer` instance used by P2PT.
final class W2GPeer: NSObject {
    /// Peer ID (hex) assigned once the tracker identifies the remote peer.
    /// Empty until the tracker provides the ID via offer/answer exchange.
    var id: String
    weak var delegate: W2GPeerDelegate?

    /// Whether this side creates the offer (initiator = true) or waits for one.
    let isInitiator: Bool

    /// Unique offer ID used by the tracker to match offer↔answer.
    let offerID: String

    private let peerConnection: RTCPeerConnection
    private var localDataChannel: RTCDataChannel?
    private var remoteDataChannel: RTCDataChannel?
    private var hasConnected = false

    /// Track whether gathering is complete (trickle disabled).
    private var gatheringComplete = false

    // MARK: - Factory

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    // MARK: - Init

    init(isInitiator: Bool, offerID: String, iceServers: [String] = []) {
        self.id = ""
        self.isInitiator = isInitiator
        self.offerID = offerID

        let config = RTCConfiguration()
        config.iceServers = iceServers.isEmpty ? [] : [RTCIceServer(urlStrings: iceServers)]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherOnce  // trickle: false

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue]
        )
        guard let pc = W2GPeer.factory.peerConnection(with: config, constraints: constraints, delegate: nil) else {
            fatalError("W2GPeer: failed to create RTCPeerConnection")
        }
        self.peerConnection = pc
        super.init()
        self.peerConnection.delegate = self

        if isInitiator {
            // Create the data channel on the initiator side (like simple-peer).
            let dcConfig = RTCDataChannelConfiguration()
            dcConfig.isOrdered = true
            if let dc = peerConnection.dataChannel(forLabel: "p2pt", configuration: dcConfig) {
                localDataChannel = dc
                dc.delegate = self
            }
        }
    }

    // MARK: - Signalling helpers (mirror simple-peer signal())

    /// For an initiator: create an SDP offer. The offer fires via delegate once
    /// ICE gathering completes (trickle disabled).
    func createOffer() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection.offer(for: constraints) { [weak self] sdp, error in
            guard let self, let sdp else { return }
            self.peerConnection.setLocalDescription(sdp) { _ in }
            // The actual full SDP (with candidates) fires in
            // peerConnection(_:didChange:) when gathering state == complete.
        }
    }

    /// Feed a remote SDP (offer or answer) into this peer connection.
    func signal(remoteSDP: RTCSessionDescription) {
        peerConnection.setRemoteDescription(remoteSDP) { [weak self] error in
            guard let self else { return }
            if remoteSDP.type == .offer {
                // Create an answer.
                let c = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                self.peerConnection.answer(for: c) { sdp, _ in
                    guard let sdp else { return }
                    self.peerConnection.setLocalDescription(sdp) { _ in }
                }
            }
        }
    }

    // MARK: - Send data

    func send(_ data: Data) {
        let buffer = RTCDataBuffer(data: data, isBinary: false)
        let dc = remoteDataChannel ?? localDataChannel
        dc?.sendData(buffer)
    }

    func sendString(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        send(data)
    }

    /// Whether the data channel is currently open.
    var isConnected: Bool {
        let dc = remoteDataChannel ?? localDataChannel
        return dc?.readyState == .open
    }

    // MARK: - Teardown

    func destroy() {
        localDataChannel?.close()
        remoteDataChannel?.close()
        peerConnection.close()
    }
}

// MARK: - RTCPeerConnectionDelegate

extension W2GPeer: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .disconnected, .failed, .closed:
            delegate?.peerDidDisconnect(self)
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        // trickle: false — wait until gathering is complete, then fire the full SDP.
        if newState == .complete, !gatheringComplete, let localDesc = peerConnection.localDescription {
            gatheringComplete = true
            delegate?.peer(self, didGenerateLocalSDP: localDesc)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // Candidates are gathered internally; we fire the full SDP on gathering complete.
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        // Remote side opened a data channel (non-initiator receives this).
        remoteDataChannel = dataChannel
        dataChannel.delegate = self
    }
}

// MARK: - RTCDataChannelDelegate

extension W2GPeer: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        if dataChannel.readyState == .open, !hasConnected {
            hasConnected = true
            delegate?.peerDidConnect(self)
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        delegate?.peer(self, didReceiveMessage: buffer.data)
    }
}
