//
//  MediaSession.swift
//  Hayase
//
//  Mirrors: what src/lib/components/ui/player/player.svelte tells the host through the `native` API:
//    native.setMediaSession(session, mediaId, duration)    the title, description and picture of what plays
//    native.setPositionState({ duration, position, playbackRate }, state)
//    native.setPlayBackState(state)                         'none' | 'paused' | 'playing'
//    native.setActionHandler(action, handler)               play, pause, seekto, seekbackward, seekforward,
//                                                           previoustrack, nexttrack
//  On iOS those are the lock screen, Control Centre and the remote controls of headphones and cars:
//  `MPNowPlayingInfoCenter` shows the media and `MPRemoteCommandCenter` carries the actions back. The
//  interface's `enterpictureinpicture` handler has no counterpart here: system Picture in Picture starts
//  from the player itself.
//

import AVFoundation
import MediaPlayer
import UIKit

final class MediaSession {
    /// `setPlayBackState`'s `'none' | 'paused' | 'playing'`
    enum PlaybackState {
        case none
        case paused
        case playing
    }

    /// The `setActionHandler` calls of player.svelte. The handlers of previous and next track are there only
    /// when the episode has one (`prev?.()`, `next?.()`).
    struct Handlers {
        var play: (() -> Void)?
        var pause: (() -> Void)?
        var seekTo: ((Double) -> Void)?
        var seekBackward: (() -> Void)?
        var seekForward: (() -> Void)?
        var previousTrack: (() -> Void)?
        var nextTrack: (() -> Void)?
    }

    static let shared = MediaSession()

    /// The player the session belongs to; the one that was set up last owns it.
    private weak var owner: AnyObject?
    private var handlers = Handlers()
    private var state = PlaybackState.none
    private var info: [String: Any] = [:]
    private var artwork: (url: String, image: UIImage)?
    private var artworkTask: URLSessionDataTask?
    private var commandsInstalled = false
    private var lastPosition: (position: Double, at: Date)?

    private init() {}

    // MARK: - native.setMediaSession

    /// `native.setMediaSession({ title, description, image }, mediaId, duration)`
    func setMediaSession(owner: AnyObject, title: String, description: String, imageURL: String?, duration: Double) {
        self.owner = owner
        activateAudioSession()
        installCommandsIfNeeded()
        info = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: description,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 0.0,
        ]
        if duration.isFinite, duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        lastPosition = nil
        loadArtwork(imageURL)
        publish()
    }

    // MARK: - native.setPositionState and native.setPlayBackState

    /// `native.setPositionState({ duration, position, playbackRate }, state)`. The lock screen runs its own clock
    /// from the position and the rate, so a report is sent on a change of state and then now and then, and
    /// when the position is not where the clock would have it.
    func setPositionState(owner: AnyObject, duration: Double, position: Double, playbackRate: Double, state: PlaybackState) {
        guard self.owner === owner else { return }
        let now = Date()
        if let last = lastPosition, state == self.state, now.timeIntervalSince(last.at) < 1 { return }
        if let last = lastPosition, state == self.state, state == .playing {
            let expected = last.position + now.timeIntervalSince(last.at) * playbackRate
            if abs(expected - position) < 1.5, now.timeIntervalSince(last.at) < 5 { return }
        }
        lastPosition = (position, now)
        if duration.isFinite, duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, position)
        info[MPNowPlayingInfoPropertyPlaybackRate] = state == .playing ? playbackRate : 0
        self.state = state
        publish()
    }

    /// `native.setPlayBackState(state)`
    func setPlayBackState(owner: AnyObject, state: PlaybackState) {
        guard self.owner === owner, self.state != state else { return }
        self.state = state
        info[MPNowPlayingInfoPropertyPlaybackRate] = state == .playing ? (info[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 1) : 0
        // the clock stops where the media is, which is the last position told
        lastPosition = nil
        publish()
    }

    // MARK: - native.setActionHandler

    func setActionHandlers(owner: AnyObject, _ handlers: Handlers) {
        guard self.owner === owner else { return }
        self.handlers = handlers
        installCommandsIfNeeded()
        updateCommands()
    }

    /// The player is gone: nothing is shown any more and the actions answer nobody.
    func clear(owner: AnyObject) {
        guard self.owner === owner else { return }
        self.owner = nil
        handlers = Handlers()
        state = .none
        info = [:]
        lastPosition = nil
        artworkTask?.cancel()
        artworkTask = nil
        artwork = nil
        updateCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    /// The lock screen and the remote controls belong to the app that has an active playback session while it
    /// plays. The session that the app made when it opened can have been ended since (an interruption, the audio
    /// output closing when a file ended), so it is made active again for each episode.
    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    // MARK: - Lock screen

    private func publish() {
        var shown = info
        if let artwork {
            let image = artwork.image
            shown[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = shown
        switch state {
        case .none: center.playbackState = .stopped
        case .paused: center.playbackState = .paused
        case .playing: center.playbackState = .playing
        }
    }

    private func loadArtwork(_ urlString: String?) {
        artworkTask?.cancel()
        artworkTask = nil
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
            artwork = nil
            return
        }
        if artwork?.url == urlString { return }
        artwork = nil
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.artworkTask != nil else { return }
                self.artwork = (urlString, image)
                self.publish()
            }
        }
        artworkTask = task
        task.resume()
    }

    // MARK: - Remote commands

    private func installCommandsIfNeeded() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in self?.run { $0.play } ?? .noActionableNowPlayingItem }
        center.pauseCommand.addTarget { [weak self] _ in self?.run { $0.pause } ?? .noActionableNowPlayingItem }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .noActionableNowPlayingItem }
            return self.run { self.state == .playing ? $0.pause : $0.play }
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            guard let seekTo = self.handlers.seekTo else { return .noActionableNowPlayingItem }
            DispatchQueue.main.async { seekTo(event.positionTime) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in self?.run { $0.seekBackward } ?? .noActionableNowPlayingItem }
        center.skipForwardCommand.addTarget { [weak self] _ in self?.run { $0.seekForward } ?? .noActionableNowPlayingItem }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.run { $0.previousTrack } ?? .noActionableNowPlayingItem }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.run { $0.nextTrack } ?? .noActionableNowPlayingItem }
    }

    /// Calls the handler `pick` finds, on the main queue; there is none when no player is up.
    private func run(_ pick: (Handlers) -> (() -> Void)?) -> MPRemoteCommandHandlerStatus {
        guard let action = pick(handlers) else { return .noActionableNowPlayingItem }
        DispatchQueue.main.async(execute: action)
        return .success
    }

    /// Only what has a handler is offered, as the interface registers the handlers it has.
    private func updateCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = handlers.play != nil
        center.pauseCommand.isEnabled = handlers.pause != nil
        center.togglePlayPauseCommand.isEnabled = handlers.play != nil && handlers.pause != nil
        center.changePlaybackPositionCommand.isEnabled = handlers.seekTo != nil
        let interval = NSNumber(value: Double(Settings.seekDuration) ?? 2)   // `playerSeek`
        center.skipBackwardCommand.preferredIntervals = [interval]
        center.skipForwardCommand.preferredIntervals = [interval]
        center.skipBackwardCommand.isEnabled = handlers.seekBackward != nil
        center.skipForwardCommand.isEnabled = handlers.seekForward != nil
        center.previousTrackCommand.isEnabled = handlers.previousTrack != nil
        center.nextTrackCommand.isEnabled = handlers.nextTrack != nil
    }
}
