//
//  PlayerAudioDiagnostics.swift
//  Hayase
//
//  Logs AVAudioSession and mpv audio state to StreamingLogger whenever the
//  system volume, route, category or interruption state changes. Meant to show
//  why output gets quieter than one hardware volume step until playback is
//  paused and resumed. Only active while the streaming logger is enabled.
//

import AVFoundation

final class PlayerAudioDiagnostics {
    private let session = AVAudioSession.sharedInstance()
    private let mpvState: () -> String
    private var volumeObservation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []

    init?(mpvState: @escaping () -> String) {
        guard UserDefaults.standard.bool(forKey: "pref_showLogger") else { return nil }
        self.mpvState = mpvState

        volumeObservation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
            guard let old = change.oldValue, let new = change.newValue else { return }
            self?.log(String(format: "system volume %.4f -> %.4f", old, new))
        }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) { [weak self] note in
                self?.log("route change: \(Self.reason(in: note, key: AVAudioSessionRouteChangeReasonKey, as: AVAudioSession.RouteChangeReason.self))")
            },
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { [weak self] note in
                self?.log("interruption: \(Self.reason(in: note, key: AVAudioSessionInterruptionTypeKey, as: AVAudioSession.InterruptionType.self))")
            },
            center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: session, queue: nil) { [weak self] _ in
                self?.log("silence secondary audio hint")
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: nil) { [weak self] _ in
                self?.log("media services were reset")
            },
        ]
        log("diagnostics started")
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func log(_ event: String) {
        StreamingLogger.shared.info("[audio] \(event) | \(sessionState()) | \(mpvState())")
    }

    private func sessionState() -> String {
        let options = session.categoryOptions
        let outputs = session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        let fields = [
            "session=\(session.category.rawValue)/\(session.mode.rawValue)",
            "mix=\(options.contains(.mixWithOthers))",
            "duck=\(options.contains(.duckOthers))",
            "sysVol=\(String(format: "%.4f", session.outputVolume))",
            "out=\(outputs)",
            "ch=\(session.outputNumberOfChannels)",
            "rate=\(Int(session.sampleRate))",
            "otherAudio=\(session.isOtherAudioPlaying)",
        ]
        return fields.joined(separator: " ")
    }

    private static func reason<T: RawRepresentable>(in note: Notification, key: String, as type: T.Type) -> String
        where T.RawValue == UInt {
        guard let raw = note.userInfo?[key] as? UInt, let value = T(rawValue: raw) else { return "unknown" }
        return "\(value)"
    }
}
