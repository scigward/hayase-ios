// PiPController.swift — System Picture-in-Picture support.
//
// Adapted from streamyfin (modules/mpv-player/ios/PiPController.swift).
// Uses AVPictureInPictureController with AVSampleBufferDisplayLayer content
// source to provide native system PiP when the app goes to background.

import AVKit
import AVFoundation

@available(iOS 15.0, *)
protocol PiPControllerDelegate: AnyObject {
    func pipController(_ controller: PiPController, willStartPictureInPicture: Bool)
    func pipController(_ controller: PiPController, didStartPictureInPicture: Bool)
    func pipController(_ controller: PiPController, willStopPictureInPicture: Bool)
    func pipController(_ controller: PiPController, didStopPictureInPicture: Bool)
    func pipController(_ controller: PiPController, restoreUserInterfaceForPictureInPictureStop completionHandler: @escaping (Bool) -> Void)
    func pipControllerPlay(_ controller: PiPController)
    func pipControllerPause(_ controller: PiPController)
    func pipController(_ controller: PiPController, skipByInterval interval: CMTime)
    func pipControllerIsPlaying(_ controller: PiPController) -> Bool
    func pipControllerDuration(_ controller: PiPController) -> Double
    func pipControllerCurrentPosition(_ controller: PiPController) -> Double
}

@available(iOS 15.0, *)
final class PiPController: NSObject {
    private var pipController: AVPictureInPictureController?
    private weak var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?
    
    weak var delegate: PiPControllerDelegate?
    
    // Timebase for PiP progress tracking
    private var timebase: CMTimebase?
    
    // Track current time for PiP progress
    private var currentTime: CMTime = .zero
    private var currentDuration: Double = 0
    
    /// The last rate written to the timebase, tracked to avoid redundant
    /// CMTimebaseSetRate calls that can disrupt the PiP auto-start observer.
    private var currentRate: Float64 = 0
    
    var isPictureInPictureSupported: Bool {
        return AVPictureInPictureController.isPictureInPictureSupported()
    }
    
    var isPictureInPictureActive: Bool {
        return pipController?.isPictureInPictureActive ?? false
    }
    
    var isPictureInPicturePossible: Bool {
        return pipController?.isPictureInPicturePossible ?? false
    }
    
    init(sampleBufferDisplayLayer: AVSampleBufferDisplayLayer) {
        self.sampleBufferDisplayLayer = sampleBufferDisplayLayer
        super.init()
        setupTimebase()
        setupPictureInPicture()
    }
    
    private func setupTimebase() {
        // Create a timebase for tracking playback time
        var newTimebase: CMTimebase?
        let status = CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &newTimebase
        )
        
        if status == noErr, let tb = newTimebase {
            timebase = tb
            CMTimebaseSetTime(tb, time: .zero)
            CMTimebaseSetRate(tb, rate: 0) // Start paused
            
            // Set the control timebase on the display layer
            sampleBufferDisplayLayer?.controlTimebase = tb
        }
    }
    
    private func setupPictureInPicture() {
        guard isPictureInPictureSupported,
              let displayLayer = sampleBufferDisplayLayer else {
            return
        }
        
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        
        pipController = AVPictureInPictureController(contentSource: contentSource)
        pipController?.delegate = self
        pipController?.requiresLinearPlayback = false
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true
    }
    
    func startPictureInPicture() {
        guard let pipController = pipController,
              pipController.isPictureInPicturePossible else {
            return
        }
        
        pipController.startPictureInPicture()
    }
    
    func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }
    
    func invalidate() {
        if Thread.isMainThread {
            pipController?.invalidatePlaybackState()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.pipController?.invalidatePlaybackState()
            }
        }
    }
    
    func updatePlaybackState() {
        // Only invalidate when PiP is active to avoid "no context menu visible" warnings
        guard isPictureInPictureActive else { return }
        
        if Thread.isMainThread {
            pipController?.invalidatePlaybackState()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.pipController?.invalidatePlaybackState()
            }
        }
    }
    
    /// Updates the current playback time for PiP progress display.
    ///
    /// The timebase runs at rate 1 in real-time, so it naturally stays in sync
    /// with playback. We only call CMTimebaseSetTime when the drift between
    /// the timebase and MPV exceeds a threshold (e.g. after a seek). Constant
    /// CMTimebaseSetTime calls would internally stop-and-restart the timebase,
    /// which can make the PiP system intermittently see the content as "not
    /// playing" and refuse to auto-start.
    func setCurrentTime(_ time: CMTime) {
        currentTime = time
        
        if let tb = timebase {
            let tbTime = CMTimebaseGetTime(tb)
            let drift = abs(CMTimeGetSeconds(time) - CMTimeGetSeconds(tbTime))
            if drift > 2.0 {
                CMTimebaseSetTime(tb, time: time)
                // Restore the rate after SetTime (SetTime preserves rate but
                // restarts internal timers — restore immediately to be safe).
                if currentRate != 0 {
                    CMTimebaseSetRate(tb, rate: currentRate)
                }
            }
        }
        
        // Only invalidate when PiP is active to avoid unnecessary updates
        if isPictureInPictureActive {
            updatePlaybackState()
        }
    }
    
    /// Updates the current playback time from seconds
    func setCurrentTimeFromSeconds(_ seconds: Double, duration: Double) {
        guard seconds >= 0 else { return }
        currentDuration = duration
        let time = CMTime(seconds: seconds, preferredTimescale: 1000)
        setCurrentTime(time)
    }
    
    /// Updates the playback rate on the timebase (1.0 = playing, 0.0 = paused).
    /// Skips the call when the rate is already at the desired value to avoid
    /// unnecessary timebase restarts.
    func setPlaybackRate(_ rate: Float) {
        let rate64 = Float64(rate)
        guard rate64 != currentRate else { return }
        currentRate = rate64
        if let tb = timebase {
            CMTimebaseSetRate(tb, rate: rate64)
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

@available(iOS 15.0, *)
extension PiPController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        delegate?.pipController(self, willStartPictureInPicture: true)
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        delegate?.pipController(self, didStartPictureInPicture: true)
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("Failed to start PiP: \(error)") }
        delegate?.pipController(self, didStartPictureInPicture: false)
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        delegate?.pipController(self, willStopPictureInPicture: true)
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        delegate?.pipController(self, didStopPictureInPicture: true)
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        delegate?.pipController(self, restoreUserInterfaceForPictureInPictureStop: completionHandler)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

@available(iOS 15.0, *)
extension PiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        if playing {
            delegate?.pipControllerPlay(self)
        } else {
            delegate?.pipControllerPause(self)
        }
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        delegate?.pipController(self, skipByInterval: skipInterval)
        completionHandler()
    }
    
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        let duration = delegate?.pipControllerDuration(self) ?? 0
        if duration > 0 {
            let cmDuration = CMTime(seconds: duration, preferredTimescale: 1000)
            return CMTimeRange(start: .zero, duration: cmDuration)
        }
        return CMTimeRange(start: .zero, duration: .positiveInfinity)
    }
    
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return !(delegate?.pipControllerIsPlaying(self) ?? false)
    }
}
