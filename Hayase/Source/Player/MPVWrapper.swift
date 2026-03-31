import UIKit
import MPVKit
import CoreMedia
import CoreVideo
import AVFoundation

protocol MPVWrapperDelegate: AnyObject {
    func renderer(_ renderer: MPVWrapper, didUpdatePosition position: Double, duration: Double, cacheSeconds: Double)
    func renderer(_ renderer: MPVWrapper, didChangePause isPaused: Bool)
    func renderer(_ renderer: MPVWrapper, didChangeLoading isLoading: Bool)
    func renderer(_ renderer: MPVWrapper, didBecomeReadyToSeek: Bool)
    func renderer(_ renderer: MPVWrapper, didBecomeTracksReady: Bool)
    func renderer(_ renderer: MPVWrapper, didSelectAudioOutput audioOutput: String)
    func renderer(_ renderer: MPVWrapper, didBecomeChaptersReady chapters: [MPVChapter])
}

/// MPV player using vo_avfoundation for video output.
/// This renders video directly to AVSampleBufferDisplayLayer for PiP support.
final class MPVWrapper {
    enum RendererError: Error {
        case mpvCreationFailed
        case mpvInitialization(Int32)
    }
    
    private let displayLayer: AVSampleBufferDisplayLayer
    private let queue = DispatchQueue(label: "mpv.avfoundation", qos: .userInitiated)
    private let stateQueue = DispatchQueue(label: "mpv.avfoundation.state", attributes: .concurrent)
    
    private var mpv: OpaquePointer?
    
    private var currentPreset: PlayerPreset?
    private var currentURL: URL?
    private var currentHeaders: [String: String]?
    private var pendingExternalSubtitles: [String] = []
    private var initialSubtitleId: Int?
    private var initialAudioId: Int?
    
    private var isRunning = false
    private var isStopping = false
    
    // KVO observation for display layer status
    private var statusObservation: NSKeyValueObservation?
    
    weak var delegate: MPVWrapperDelegate?
    
    // Thread-safe state for playback
    private var _cachedDuration: Double = 0
    private var _cachedPosition: Double = 0
    private var _cachedCacheSeconds: Double = 0
    private var _isPaused: Bool = true
    private var _playbackSpeed: Double = 1.0
    private var _isLoading: Bool = false
    private var _isReadyToSeek: Bool = false
    private var _isSeeking: Bool = false

    // Progress update throttling - CRITICAL for performance!
    // DO NOT REMOVE THIS THROTTLE - it is essential for battery life and CPU efficiency.
    //
    // Without throttling, time-pos fires every video frame (24+ times/sec at 24fps).
    // Each update crosses the React Native JS bridge, which is expensive on mobile.
    // Even if the JS side does nothing, 24+ bridge calls/sec wastes CPU and battery.
    //
    // Throttling to 1 update/sec during normal playback is sufficient for:
    // - Progress bar updates (users can't perceive 1-second granularity)
    // - Playback position tracking
    // - Any JS-side logic that needs current position
    //
    // During seeking, we bypass the throttle for responsive scrubbing.
    // This optimization reduced CPU usage by ~50% for downloaded file playback.
    private var lastProgressUpdateTime: CFAbsoluteTime = 0
    
    // Thread-safe accessors
    private var cachedDuration: Double {
        get { stateQueue.sync { _cachedDuration } }
        set { stateQueue.async(flags: .barrier) { self._cachedDuration = newValue } }
    }
    private var cachedPosition: Double {
        get { stateQueue.sync { _cachedPosition } }
        set { stateQueue.async(flags: .barrier) { self._cachedPosition = newValue } }
    }
    private var cachedCacheSeconds: Double {
        get { stateQueue.sync { _cachedCacheSeconds } }
        set { stateQueue.async(flags: .barrier) { self._cachedCacheSeconds = newValue } }
    }
    private var isPaused: Bool {
        get { stateQueue.sync { _isPaused } }
        set { stateQueue.async(flags: .barrier) { self._isPaused = newValue } }
    }
    private var playbackSpeed: Double {
        get { stateQueue.sync { _playbackSpeed } }
        set { stateQueue.async(flags: .barrier) { self._playbackSpeed = newValue } }
    }
    private var isLoading: Bool {
        get { stateQueue.sync { _isLoading } }
        set { stateQueue.async(flags: .barrier) { self._isLoading = newValue } }
    }
    private var isReadyToSeek: Bool {
        get { stateQueue.sync { _isReadyToSeek } }
        set { stateQueue.async(flags: .barrier) { self._isReadyToSeek = newValue } }
    }
    private var isSeeking: Bool {
        get { stateQueue.sync { _isSeeking } }
        set { stateQueue.async(flags: .barrier) { self._isSeeking = newValue } }
    }
    
    var isPausedState: Bool {
        return isPaused
    }
    
    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        observeDisplayLayerStatus()
    }
    
   
    /// Watches for display layer failures and auto-recovers.
    ///
    /// iOS aggressively kills VideoToolbox decoder sessions when the app is
    /// backgrounded, the screen is locked, or system resources are low.
    /// This causes the video to go black - especially problematic for PiP.
    ///
    /// This KVO observer detects when the display layer status becomes `.failed`
    /// and automatically reinitializes the hardware decoder to restore video.
    private func observeDisplayLayerStatus() {
        statusObservation = displayLayer.observe(\.status, options: [.new]) { [weak self] layer, _ in
            guard let self else { return }
            
            if layer.status == .failed {
                if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("🔧 Display layer failed - auto-resetting decoder") }
                self.queue.async {
                    self.performDecoderReset()
                }
            }
        }
    }
    
    /// Actually performs the decoder reset (called by observer or manually)
    private func performDecoderReset() {
        guard let handle = mpv else { return }
        if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("🔧 Resetting decoder: status=\(displayLayer.status.rawValue), requiresFlush=\(displayLayer.requiresFlushToResumeDecoding)") }
        commandSync(handle, ["set", "hwdec", "no"])
        commandSync(handle, ["set", "hwdec", "auto"])
    }
    
    deinit {
        stop()
    }
    
    func start() throws {
        guard !isRunning else { return }
        guard let handle = mpv_create() else {
            throw RendererError.mpvCreationFailed
        }
        mpv = handle

        // Logging — capture warnings and errors in both debug and release.
        // Previously release used "no" which silenced all mpv log messages,
        // preventing errors from reaching the StreamingLogger overlay.
        checkError(mpv_request_log_messages(handle, "warn"))

        // Pass the AVSampleBufferDisplayLayer to mpv via --wid
        // The vo_avfoundation driver expects this
        let layerPtrInt = Int(bitPattern: Unmanaged.passUnretained(displayLayer).toOpaque())
        var displayLayerPtr = Int64(layerPtrInt)
        checkError(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &displayLayerPtr))

        // Use AVFoundation video output - required for PiP support
        checkError(mpv_set_option_string(handle, "vo", "avfoundation"))

        // Enable composite OSD mode - renders subtitles directly onto video frames using GPU
        // This is better for PiP as subtitles are baked into the video
        // NOTE: Must be set BEFORE the #if targetEnvironment check or tvOS will freeze on player exit
        checkError(mpv_set_option_string(handle, "avfoundation-composite-osd", "yes"))

        // Hardware decoding with VideoToolbox
        // On simulator, use software decoding since VideoToolbox is not available
        // On device, use VideoToolbox with software fallback enabled
        #if targetEnvironment(simulator)
        checkError(mpv_set_option_string(handle, "hwdec", "no"))
        #else
        checkError(mpv_set_option_string(handle, "hwdec", "videotoolbox"))
        #endif
        checkError(mpv_set_option_string(handle, "hwdec-codecs", "all"))
        checkError(mpv_set_option_string(handle, "hwdec-software-fallback", "yes"))

        // Subtitle and audio settings
        checkError(mpv_set_option_string(mpv, "subs-match-os-language", "yes"))
        checkError(mpv_set_option_string(mpv, "subs-fallback", "yes"))

        // Tell MPV the stream is always seekable. This prevents MPV from
        // giving up on seeking in partially-downloaded local files.
        checkError(mpv_set_option_string(handle, "force-seekable", "yes"))

        // MKV demuxer options — MUST be set before mpv_initialize().
        // Setting demuxer sub-options via runtime "set" commands may fail
        // silently because mpv_command_async ignores errors (reply_id=0).
        //
        // probe-video-duration=yes: Makes MPV seek to the end of the file
        // to read the Cues element (seek index + accurate duration). Without
        // this, MPV defaults to "no" and the video duration is unknown until
        // the file is nearly fully downloaded. The LocalStreamServer will
        // block the tail-end Range request until those pieces are available.
        checkError(mpv_set_option_string(handle, "demuxer-mkv-probe-video-duration", "yes"))

        // subtitle-preroll=yes: Makes MPV read subtitle data from before
        // the seek target, so subtitles are visible immediately after seeking
        // instead of waiting for the next subtitle event.
        checkError(mpv_set_option_string(handle, "demuxer-mkv-subtitle-preroll", "yes"))

        // Initialize mpv
        let initStatus = mpv_initialize(handle)
        guard initStatus >= 0 else {
            throw RendererError.mpvInitialization(initStatus)
        }

        // Observe properties
        observeProperties()

        // Setup wakeup callback
        mpv_set_wakeup_callback(handle, { ctx in
            guard let ctx = ctx else { return }
            let instance = Unmanaged<MPVWrapper>.fromOpaque(ctx).takeUnretainedValue()
            instance.processEvents()
        }, Unmanaged.passUnretained(self).toOpaque())
        isRunning = true
    }
    
    func stop() {
        if isStopping { return }
        if !isRunning, mpv == nil { return }
        isRunning = false
        isStopping = true
        
        // Stop observing display layer status
        statusObservation?.invalidate()
        statusObservation = nil
        
        queue.sync { [weak self] in
            guard let self, let handle = self.mpv else { return }
            
            mpv_set_wakeup_callback(handle, nil, nil)
            mpv_terminate_destroy(handle)
            self.mpv = nil
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if #available(iOS 18.0, *) {
                self.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            } else {
                self.displayLayer.flushAndRemoveImage()
            }
        }
        
        isStopping = false
    }
    
    func load(
        url: URL,
        with preset: PlayerPreset,
        headers: [String: String]? = nil,
        startPosition: Double? = nil,
        externalSubtitles: [String]? = nil,
        initialSubtitleId: Int? = nil,
        initialAudioId: Int? = nil
    ) {
        currentPreset = preset
        currentURL = url
        currentHeaders = headers
        pendingExternalSubtitles = externalSubtitles ?? []
        self.initialSubtitleId = initialSubtitleId
        self.initialAudioId = initialAudioId
        queue.async { [weak self] in
            guard let self else { return }
            self.isLoading = true
            self.isReadyToSeek = false
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangeLoading: true)
            }

            guard let handle = self.mpv else { return }

            self.apply(commands: preset.commands, on: handle)
            // Stop previous playback synchronously before loading new file.
            // Must be synchronous (commandSync) so MPV finishes tearing down
            // the old decoder before we flush the display layer below.
            self.commandSync(handle, ["stop"])

            // Flush the display layer to clear the previous video's last frame.
            // vo_avfoundation retains the last decoded frame in the
            // AVSampleBufferDisplayLayer until new sample buffers arrive.
            // Without this flush, switching between videos (or restarting
            // playback) causes a brief flash of the old content while MPV
            // demuxes the new file and decodes its first frame.
            DispatchQueue.main.sync { [weak self] in
                guard let self else { return }
                if #available(iOS 18.0, *) {
                    self.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
                } else {
                    self.displayLayer.flushAndRemoveImage()
                }
            }

            self.updateHTTPHeaders(headers)
            // Set start position
            if let startPos = startPosition, startPos > 0 {
                self.setProperty(name: "start", value: String(format: "%.2f", startPos))
            } else {
                self.setProperty(name: "start", value: "0")
            }
            // Set initial audio track if specified
            if let audioId = self.initialAudioId, audioId > 0 {
                self.setAudioTrack(audioId)
            }
            // Set initial subtitle track if no external subs
            if self.pendingExternalSubtitles.isEmpty {
                if let subId = self.initialSubtitleId {
                    self.setSubtitleTrack(subId)
                } else {
                    self.disableSubtitles()
                }
            } else {
                self.disableSubtitles()
            }
            let target = url.isFileURL ? url.path : url.absoluteString
            self.command(handle, ["loadfile", target, "replace"])
        }
    }
    
    func reloadCurrentItem() {
        guard let url = currentURL, let preset = currentPreset else { return }
        load(url: url, with: preset, headers: currentHeaders)
    }
    
    func applyPreset(_ preset: PlayerPreset) {
        currentPreset = preset
        guard let handle = mpv else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.apply(commands: preset.commands, on: handle)
        }
    }
    
    // MARK: - Property Helpers
    
    private func setOption(name: String, value: String) {
        guard let handle = mpv else { return }
        checkError(mpv_set_option_string(handle, name, value))
    }
    
    private func setProperty(name: String, value: String) {
        guard let handle = mpv else { return }
        let status = mpv_set_property_string(handle, name, value)
        if status < 0 {
            Logger.shared.log("Failed to set property \(name)=\(value) (\(status))", type: "Warn")
        }
    }
    
    private func clearProperty(name: String) {
        guard let handle = mpv else { return }
        // Use mpv_set_property_string with empty string to reset the property.
        // The previous approach (MPV_FORMAT_NONE) was invalid — mpv doesn't
        // support setting properties with FORMAT_NONE, returning error -9
        // (MPV_ERROR_PROPERTY_FORMAT). Empty string works for both string and
        // list properties (like http-header-fields).
        let status = mpv_set_property_string(handle, name, "")
        if status < 0 {
            Logger.shared.log("Failed to clear property \(name) (\(status))", type: "Warn")
        }
    }
    
    private func updateHTTPHeaders(_ headers: [String: String]?) {
        guard let headers, !headers.isEmpty else {
            clearProperty(name: "http-header-fields")
            return
        }
        
        let headerString = headers
            .map { key, value in "\(key): \(value)" }
            .joined(separator: "\r\n")
        setProperty(name: "http-header-fields", value: headerString)
    }
    
    private func observeProperties() {
        guard let handle = mpv else { return }
        let properties: [(String, mpv_format)] = [
            ("duration", MPV_FORMAT_DOUBLE),
            ("time-pos", MPV_FORMAT_DOUBLE),
            ("pause", MPV_FORMAT_FLAG),
            ("track-list/count", MPV_FORMAT_INT64),
            ("paused-for-cache", MPV_FORMAT_FLAG),
            ("demuxer-cache-duration", MPV_FORMAT_DOUBLE),
            ("current-ao", MPV_FORMAT_STRING)
        ]
        for (name, format) in properties {
            mpv_observe_property(handle, 0, name, format)
        }
    }
    
    private func apply(commands: [[String]], on handle: OpaquePointer) {
        for command in commands {
            guard !command.isEmpty else { continue }
            // Intercept "set" commands and use the synchronous property API
            // instead of mpv_command_async. mpv_command_async with reply_id=0
            // silently ignores errors, so "set" commands can fail without any
            // indication. mpv_set_property_string is synchronous, reports
            // errors via Logger, and guarantees the property is changed before
            // subsequent commands (like loadfile) execute.
            if command.count == 3 && command[0] == "set" {
                setProperty(name: command[1], value: command[2])
            } else {
                self.command(handle, command)
            }
        }
    }
    
    private func command(_ handle: OpaquePointer, _ args: [String]) {
        guard !args.isEmpty else { return }
        _ = withCStringArray(args) { pointer in
            mpv_command_async(handle, 0, pointer)
        }
    }
    
    @discardableResult
    private func commandSync(_ handle: OpaquePointer, _ args: [String]) -> Int32 {
        guard !args.isEmpty else { return -1 }
        return withCStringArray(args) { pointer in
            mpv_command(handle, pointer)
        }
    }
    
    private func checkError(_ status: CInt) {
        if status < 0 {
            Logger.shared.log("MPV API error: \(String(cString: mpv_error_string(status)))", type: "Error")
        }
    }
    
    // MARK: - Event Handling
    
    private func processEvents() {
        queue.async { [weak self] in
            guard let self else { return }
            
            while self.mpv != nil && !self.isStopping {
                guard let handle = self.mpv,
                      let eventPointer = mpv_wait_event(handle, 0) else { return }
                let event = eventPointer.pointee
                if event.event_id == MPV_EVENT_NONE { break }
                self.handleEvent(event)
                if event.event_id == MPV_EVENT_SHUTDOWN { break }
            }
        }
    }
    
    private func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_FILE_LOADED:
            // Add external subtitles now that the file is loaded
            let hadExternalSubs = !pendingExternalSubtitles.isEmpty
            if hadExternalSubs, let handle = mpv {
                for (index, subUrl) in pendingExternalSubtitles.enumerated() {
                    if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("🔧 Adding external subtitle [\(index)]: \(subUrl)") }
                    // Use commandSync to ensure subs are added in exact order (not async)
                    // "auto" flag = add without auto-selecting
                    commandSync(handle, ["sub-add", subUrl, "auto"])
                }
                pendingExternalSubtitles = []
                // Set subtitle after external subs are added
                if let subId = initialSubtitleId {
                    setSubtitleTrack(subId)
                } else {
                    disableSubtitles()
                }
            }
            if !isReadyToSeek {
                isReadyToSeek = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didBecomeReadyToSeek: true)
                }
            }
            // Notify loading ended
            if isLoading {
                isLoading = false
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didChangeLoading: false)
                }
            }
            // Fetch chapters now that file metadata is available
            let chapters = getChapters()
            if !chapters.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didBecomeChaptersReady: chapters)
                }
            }
            
        case MPV_EVENT_SEEK:
            // Seek started - show loading indicator and enable immediate progress updates
            isSeeking = true
            if !isLoading {
                isLoading = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didChangeLoading: true)
                }
            }
            // NOTE: Do NOT flush AVSampleBufferDisplayLayer here.
            //
            // vo_avfoundation handles the layer flush internally via VOCTRL_RESET,
            // which fires BEFORE MPV_EVENT_SEEK is delivered to Swift.  Adding a
            // second async flush here would wipe newly-decoded post-seek frames,
            // creating a gap in the queue and producing a flash.
            //
            // The paused-for-cache flush (which clears pre-queued frames during
            // mid-stream stalls) is also suppressed while isSeeking==true.  After
            // a seek, paused-for-cache fires during the initial buffer-fill window.
            // If we flush then, MPV re-decodes from the keyframe before the seek
            // point and those keyframe→seek-point frames display as a brief flash
            // of "previously-played" content.  See the paused-for-cache handler.
            
        case MPV_EVENT_PLAYBACK_RESTART:
            // Video playback has started/restarted (including after seek)
            isSeeking = false
            if isLoading {
                isLoading = false
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didChangeLoading: false)
                }
            }
        case MPV_EVENT_PROPERTY_CHANGE:
            if let property = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee.name {
                let name = String(cString: property)
                refreshProperty(named: name, event: event)
            }

        case MPV_EVENT_SHUTDOWN:
            Logger.shared.log("mpv shutdown", type: "Warn")

        case MPV_EVENT_LOG_MESSAGE:
            if let logMessagePointer = event.data?.assumingMemoryBound(to: mpv_event_log_message.self) {
                let component = String(cString: logMessagePointer.pointee.prefix)
                let text = String(cString: logMessagePointer.pointee.text)
                let lower = text.lowercased()
                if lower.contains("error") {
                    Logger.shared.log("mpv[\(component)] \(text)", type: "Error")
                } else if lower.contains("warn") || lower.contains("warning") {
                    Logger.shared.log("mpv[\(component)] \(text)", type: "Warn")
                }
            }
        default:
            break
        }
    }
    
    private func refreshProperty(named name: String, event: mpv_event) {
        guard let handle = mpv else { return }
        switch name {
        case "duration":
            var value = Double(0)
            let status = getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value)
            if status >= 0 {
                cachedDuration = value
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didUpdatePosition: self.cachedPosition, duration: self.cachedDuration, cacheSeconds: self.cachedCacheSeconds)
                }
            }
        case "time-pos":
            var value = Double(0)
            let status = getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value)
            if status >= 0 {
                cachedPosition = value
                // Always update immediately when seeking, otherwise throttle to once per second
                let now = CFAbsoluteTimeGetCurrent()
                let shouldUpdate = isSeeking || (now - lastProgressUpdateTime >= 1.0)
                if shouldUpdate {
                    lastProgressUpdateTime = now
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.delegate?.renderer(self, didUpdatePosition: self.cachedPosition, duration: self.cachedDuration, cacheSeconds: self.cachedCacheSeconds)
                    }
                }
            }
        case "demuxer-cache-duration":
            var value = Double(0)
            let status = getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value)
            if status >= 0 {
                cachedCacheSeconds = value
            }
        case "pause":
            var flag: Int32 = 0
            let status = getProperty(handle: handle, name: name, format: MPV_FORMAT_FLAG, value: &flag)
            if status >= 0 {
                let newPaused = flag != 0
                if newPaused != isPaused {
                    isPaused = newPaused
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.delegate?.renderer(self, didChangePause: self.isPaused)
                    }
                }
            }
        case "paused-for-cache":
            var flag: Int32 = 0
            let status = getProperty(handle: handle, name: name, format: MPV_FORMAT_FLAG, value: &flag)
            if status >= 0 {
                let buffering = flag != 0
                if buffering != isLoading {
                    isLoading = buffering
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.delegate?.renderer(self, didChangeLoading: buffering)
                    }
                }
                // When a MID-STREAM cache stall starts (not during a seek),
                // flush the display layer's queued-but-not-yet-displayed sample
                // buffers WITHOUT removing the currently displayed image.
                //
                // Root cause of stall glitch: MPV pre-queues several seconds of
                // frames into AVSampleBufferDisplayLayer; as the layer's
                // presentation clock continues advancing during a stall, those
                // pre-queued future frames eventually become due and get rendered,
                // making the video appear to jump to a "wrong" (older-looking)
                // frame. Calling flush() discards those pending queue entries and
                // freezes the display at the exact stall position — no black screen.
                //
                // WHY we skip this during a seek (isSeeking == true):
                // After a seek, vo_avfoundation calls VOCTRL_RESET which flushes
                // the layer, then immediately starts enqueuing new post-seek frames.
                // paused-for-cache fires during this initial buffer-fill window.
                // If we also flush here, we discard those newly-decoded post-seek
                // frames and MPV has to re-decode from the keyframe before the seek
                // point. Those keyframe→seek-point frames then display rapidly as a
                // brief "flash of previously-played frames." Suppressing the flush
                // during a seek lets the post-seek frames display normally.
                if buffering && !isSeeking {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        if #available(iOS 18.0, *) {
                            self.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: false, completionHandler: nil)
                        } else {
                            self.displayLayer.flush()
                        }
                    }
                }
            }
        case "track-list/count":
            var trackCount: Int64 = 0
            let status = getProperty(handle: handle, name: name, format: MPV_FORMAT_INT64, value: &trackCount)
            if status >= 0 && trackCount > 0 {
                Logger.shared.log("Track list updated: \(trackCount) tracks available", type: "Info")
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didBecomeTracksReady: true)
                }
            }
        case "current-ao":
            // Audio output is now active - notify delegate
            if let aoName = getStringProperty(handle: handle, name: name) {
                if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("[MPV] 🔊 Audio output selected: \(aoName)") }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didSelectAudioOutput: aoName)
                }
            }
        default:
            break
        }
    }
    
    private func getStringProperty(handle: OpaquePointer, name: String) -> String? {
        var result: String?
        if let cString = mpv_get_property_string(handle, name) {
            result = String(cString: cString)
            mpv_free(cString)
        }
        return result
    }
    
    @discardableResult
    private func getProperty<T>(handle: OpaquePointer, name: String, format: mpv_format, value: inout T) -> Int32 {
        return withUnsafeMutablePointer(to: &value) { mutablePointer in
            return mpv_get_property(handle, name, format, mutablePointer)
        }
    }
    
    @inline(__always)
    private func withCStringArray<R>(_ args: [String], body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> R) -> R {
        var cStrings = [UnsafeMutablePointer<CChar>?]()
        cStrings.reserveCapacity(args.count + 1)
        for s in args {
            cStrings.append(strdup(s))
        }
        cStrings.append(nil)
        defer {
            for ptr in cStrings where ptr != nil {
                free(ptr)
            }
        }
        
        return cStrings.withUnsafeMutableBufferPointer { buffer in
            return buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) { rebound in
                return body(UnsafeMutablePointer(mutating: rebound))
            }
        }
    }
    
    // MARK: - Playback Controls
    
    func play() {
        setProperty(name: "pause", value: "no")
    }
    
    func pausePlayback() {
        setProperty(name: "pause", value: "yes")
    }
    
    func togglePause() {
        if isPaused { play() } else { pausePlayback() }
    }
    
    func seek(to seconds: Double) {
        guard let handle = mpv else { return }
        let clamped = max(0, seconds)
        cachedPosition = clamped
        commandSync(handle, ["seek", String(clamped), "absolute"])
    }

    func seek(by seconds: Double) {
        guard let handle = mpv else { return }
        let newPosition = max(0, cachedPosition + seconds)
        cachedPosition = newPosition
        commandSync(handle, ["seek", String(seconds), "relative"])
    }
    
    /// Sync timebase - no-op for vo_avfoundation (mpv handles timing)
    func syncTimebase() {
        // vo_avfoundation manages its own timebase
    }
    
    func setSpeed(_ speed: Double) {
        playbackSpeed = speed
        setProperty(name: "speed", value: String(speed))
    }
    
    func getSpeed() -> Double {
        guard let handle = mpv else { return 1.0 }
        var speed: Double = 1.0
        getProperty(handle: handle, name: "speed", format: MPV_FORMAT_DOUBLE, value: &speed)
        return speed
    }
    
    // MARK: - Subtitle Controls
    
    func getSubtitleTracks() -> [[String: Any]] {
        guard let handle = mpv else {
            Logger.shared.log("getSubtitleTracks: mpv handle is nil", type: "Warn")
            return []
        }
        var tracks: [[String: Any]] = []
        
        var trackCount: Int64 = 0
        getProperty(handle: handle, name: "track-list/count", format: MPV_FORMAT_INT64, value: &trackCount)
        
        for i in 0..<trackCount {
            guard let trackType = getStringProperty(handle: handle, name: "track-list/\(i)/type"),
                  trackType == "sub" else { continue }
            
            var trackId: Int64 = 0
            getProperty(handle: handle, name: "track-list/\(i)/id", format: MPV_FORMAT_INT64, value: &trackId)
            
            var track: [String: Any] = ["id": Int(trackId)]
            
            if let title = getStringProperty(handle: handle, name: "track-list/\(i)/title") {
                track["title"] = title
            }
            
            // Language detection: try lang → demux-lang → parse from title
            if let lang = getStringProperty(handle: handle, name: "track-list/\(i)/lang") {
                track["lang"] = lang
            } else if let demuxLang = getStringProperty(handle: handle, name: "track-list/\(i)/demux-lang") {
                track["lang"] = demuxLang
            } else if let title = track["title"] as? String {
                if let parsed = Self.parseLanguageFromTitle(title) {
                    track["lang"] = parsed
                }
            }
            
            var selected: Int32 = 0
            getProperty(handle: handle, name: "track-list/\(i)/selected", format: MPV_FORMAT_FLAG, value: &selected)
            track["selected"] = selected != 0
            
            Logger.shared.log("getSubtitleTracks: found sub track id=\(trackId), title=\(track["title"] ?? "none"), lang=\(track["lang"] ?? "none")", type: "Info")
            tracks.append(track)
        }
        
        Logger.shared.log("getSubtitleTracks: returning \(tracks.count) subtitle tracks", type: "Info")
        return tracks
    }
    
    func setSubtitleTrack(_ trackId: Int) {
        Logger.shared.log("setSubtitleTrack: setting sid to \(trackId)", type: "Info")
        guard mpv != nil else {
            Logger.shared.log("setSubtitleTrack: mpv handle is nil!", type: "Error")
            return
        }
        
        if trackId < 0 {
            setProperty(name: "sid", value: "no")
        } else {
            setProperty(name: "sid", value: String(trackId))
        }
    }
    
    func disableSubtitles() {
        setProperty(name: "sid", value: "no")
    }
    
    func getCurrentSubtitleTrack() -> Int {
        guard let handle = mpv else { return 0 }
        var sid: Int64 = 0
        getProperty(handle: handle, name: "sid", format: MPV_FORMAT_INT64, value: &sid)
        return Int(sid)
    }
    
    func addSubtitleFile(url: String, select: Bool = true) {
        guard let handle = mpv else { return }
        let flag = select ? "select" : "cached"
        commandSync(handle, ["sub-add", url, flag])
    }
    
    // MARK: - Subtitle Positioning
    
    func setSubtitlePosition(_ position: Int) {
        setProperty(name: "sub-pos", value: String(position))
    }
    
    func setSubtitleScale(_ scale: Double) {
        setProperty(name: "sub-scale", value: String(scale))
    }
    
    func setSubtitleMarginY(_ margin: Int) {
        setProperty(name: "sub-margin-y", value: String(margin))
    }
    
    func setSubtitleAlignX(_ alignment: String) {
        setProperty(name: "sub-align-x", value: alignment)
    }
    
    func setSubtitleAlignY(_ alignment: String) {
        setProperty(name: "sub-align-y", value: alignment)
    }
    
    func setSubtitleFontSize(_ size: Int) {
        setProperty(name: "sub-font-size", value: String(size))
    }

    // MARK: - Subtitle Delay

    /// Sets subtitle delay in seconds (positive = later, negative = earlier).
    /// Mirrors options.svelte's `subtitleDelay` input field.
    func setSubtitleDelay(_ delay: Double) {
        setProperty(name: "sub-delay", value: String(delay))
    }

    // MARK: - Deband

    /// Toggles the deband video filter (reduces banding artifacts).
    /// Uses the vf (video filter) pipeline instead of the `deband` property,
    /// because the property only works with vo=gpu/gpu-next, not vo=avfoundation.
    /// The @deband label allows add/remove by name.
    ///
    /// The lavfi deband filter is CPU-based — it must read and modify pixel
    /// data in system memory.  Native `hwdec=videotoolbox` produces GPU-only
    /// CVPixelBuffers that CPU filters cannot access, so the filter silently
    /// has no effect.  Switching to `videotoolbox-copy` keeps hardware
    /// decoding (VideoToolbox) but copies results to system memory so the
    /// deband filter can process every frame.  When deband is turned off we
    /// restore zero-copy `videotoolbox` for maximum performance.
    func setDeband(_ enabled: Bool) {
        guard let handle = mpv else { return }
        if enabled {
            #if !targetEnvironment(simulator)
            commandSync(handle, ["set", "hwdec", "videotoolbox-copy"])
            #endif
            commandSync(handle, ["vf", "add", "@deband:deband"])
        } else {
            commandSync(handle, ["vf", "remove", "@deband"])
            #if !targetEnvironment(simulator)
            commandSync(handle, ["set", "hwdec", "videotoolbox"])
            #endif
        }
    }

    // MARK: - Audio Track Controls
    
    func getAudioTracks() -> [[String: Any]] {
        guard let handle = mpv else {
            Logger.shared.log("getAudioTracks: mpv handle is nil", type: "Warn")
            return []
        }
        var tracks: [[String: Any]] = []
        
        var trackCount: Int64 = 0
        getProperty(handle: handle, name: "track-list/count", format: MPV_FORMAT_INT64, value: &trackCount)
        
        for i in 0..<trackCount {
            guard let trackType = getStringProperty(handle: handle, name: "track-list/\(i)/type"),
                  trackType == "audio" else { continue }
            
            var trackId: Int64 = 0
            getProperty(handle: handle, name: "track-list/\(i)/id", format: MPV_FORMAT_INT64, value: &trackId)
            
            var track: [String: Any] = ["id": Int(trackId)]
            
            if let title = getStringProperty(handle: handle, name: "track-list/\(i)/title") {
                track["title"] = title
            }
            
            // Language detection: try lang → demux-lang → parse from title
            if let lang = getStringProperty(handle: handle, name: "track-list/\(i)/lang") {
                track["lang"] = lang
            } else if let demuxLang = getStringProperty(handle: handle, name: "track-list/\(i)/demux-lang") {
                track["lang"] = demuxLang
            } else if let title = track["title"] as? String {
                if let parsed = Self.parseLanguageFromTitle(title) {
                    track["lang"] = parsed
                }
            }
            
            if let codec = getStringProperty(handle: handle, name: "track-list/\(i)/codec") {
                track["codec"] = codec
            }
            
            var channels: Int64 = 0
            getProperty(handle: handle, name: "track-list/\(i)/audio-channels", format: MPV_FORMAT_INT64, value: &channels)
            if channels > 0 {
                track["channels"] = Int(channels)
            }
            
            var selected: Int32 = 0
            getProperty(handle: handle, name: "track-list/\(i)/selected", format: MPV_FORMAT_FLAG, value: &selected)
            track["selected"] = selected != 0
            
            Logger.shared.log("getAudioTracks: found audio track id=\(trackId), title=\(track["title"] ?? "none"), lang=\(track["lang"] ?? "none")", type: "Info")
            tracks.append(track)
        }
        
        Logger.shared.log("getAudioTracks: returning \(tracks.count) audio tracks", type: "Info")
        return tracks
    }

    /// Attempts to extract an ISO 639 language code from a track title string.
    /// Handles common patterns found in MKV/MP4 metadata, e.g.:
    /// - "English", "Japanese", "English (US)", "Japanese 5.1 Surround"
    /// - "eng", "jpn", "ger"
    /// Returns the ISO 639-2/B or 639-1 code, or nil if no language is detected.
    static func parseLanguageFromTitle(_ title: String) -> String? {
        let lower = title.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Map of common full language names → ISO 639-2/B codes.
        // Covers the most common languages found in anime/media files.
        let languageMap: [(pattern: String, code: String)] = [
            ("japanese", "jpn"),
            ("english",  "eng"),
            ("chinese",  "chi"),
            ("korean",   "kor"),
            ("french",   "fre"),
            ("german",   "ger"),
            ("spanish",  "spa"),
            ("italian",  "ita"),
            ("portuguese", "por"),
            ("russian",  "rus"),
            ("arabic",   "ara"),
            ("hindi",    "hin"),
            ("thai",     "tha"),
            ("vietnamese", "vie"),
            ("indonesian", "ind"),
            ("malay",    "may"),
            ("polish",   "pol"),
            ("dutch",    "dut"),
            ("turkish",  "tur"),
            ("romanian", "rum"),
            ("czech",    "cze"),
            ("hungarian", "hun"),
            ("swedish",  "swe"),
            ("norwegian", "nor"),
            ("danish",   "dan"),
            ("finnish",  "fin"),
            ("greek",    "gre"),
            ("hebrew",   "heb"),
            ("ukrainian", "ukr"),
            ("catalan",  "cat"),
            ("latvian",  "lav"),
            ("lithuanian", "lit"),
            ("brazilian", "por"),
        ]

        for entry in languageMap {
            if lower.contains(entry.pattern) {
                return entry.code
            }
        }

        // Check for bare 3-letter ISO 639-2 codes (e.g., "eng", "jpn") at
        // word boundaries. Only match if the code is valid per Locale.
        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for word in words where word.count == 3 {
            if Locale.current.localizedString(forLanguageCode: word) != nil {
                return word
            }
        }

        // Check for 2-letter ISO 639-1 codes (e.g., "en", "ja")
        for word in words where word.count == 2 {
            if Locale.current.localizedString(forLanguageCode: word) != nil {
                return word
            }
        }

        return nil
    }
    
    func setAudioTrack(_ trackId: Int) {
        guard mpv != nil else {
            Logger.shared.log("setAudioTrack: mpv handle is nil", type: "Warn")
            return
        }
        Logger.shared.log("setAudioTrack: setting aid to \(trackId)", type: "Info")
        setProperty(name: "aid", value: String(trackId))
    }
    
    func getCurrentAudioTrack() -> Int {
        guard let handle = mpv else { return 0 }
        var aid: Int64 = 0
        getProperty(handle: handle, name: "aid", format: MPV_FORMAT_INT64, value: &aid)
        return Int(aid)
    }

    // MARK: - Chapters

    /// Reads chapter metadata from MPV's `chapter-list` property.
    /// Returns an array of MPVChapter with index, title, and start time.
    func getChapters() -> [MPVChapter] {
        guard let handle = mpv else { return [] }
        var chapterCount: Int64 = 0
        getProperty(handle: handle, name: "chapter-list/count", format: MPV_FORMAT_INT64, value: &chapterCount)
        guard chapterCount > 0 else { return [] }

        var chapters: [MPVChapter] = []
        for i in 0..<chapterCount {
            let title = getStringProperty(handle: handle, name: "chapter-list/\(i)/title") ?? "Chapter \(i + 1)"
            var time: Double = 0
            getProperty(handle: handle, name: "chapter-list/\(i)/time", format: MPV_FORMAT_DOUBLE, value: &time)
            chapters.append(MPVChapter(index: Int(i), title: title, time: time))
        }
        Logger.shared.log("getChapters: returning \(chapters.count) chapters", type: "Info")
        return chapters
    }

    // MARK: - Technical Info

    func getTechnicalInfo() -> [String: Any] {
        guard let handle = mpv else { return [:] }

        var info: [String: Any] = [:]

        // Video dimensions
        var videoWidth: Int64 = 0
        var videoHeight: Int64 = 0
        if getProperty(handle: handle, name: "video-params/w", format: MPV_FORMAT_INT64, value: &videoWidth) >= 0 {
            info["videoWidth"] = Int(videoWidth)
        }
        if getProperty(handle: handle, name: "video-params/h", format: MPV_FORMAT_INT64, value: &videoHeight) >= 0 {
            info["videoHeight"] = Int(videoHeight)
        }

        // Video codec
        if let videoCodec = getStringProperty(handle: handle, name: "video-format") {
            info["videoCodec"] = videoCodec
        }

        // Audio codec
        if let audioCodec = getStringProperty(handle: handle, name: "audio-codec-name") {
            info["audioCodec"] = audioCodec
        }

        // FPS (container fps)
        var fps: Double = 0
        if getProperty(handle: handle, name: "container-fps", format: MPV_FORMAT_DOUBLE, value: &fps) >= 0 && fps > 0 {
            info["fps"] = fps
        }

        // Video bitrate (bits per second)
        var videoBitrate: Int64 = 0
        if getProperty(handle: handle, name: "video-bitrate", format: MPV_FORMAT_INT64, value: &videoBitrate) >= 0 && videoBitrate > 0 {
            info["videoBitrate"] = Int(videoBitrate)
        }

        // Audio bitrate (bits per second)
        var audioBitrate: Int64 = 0
        if getProperty(handle: handle, name: "audio-bitrate", format: MPV_FORMAT_INT64, value: &audioBitrate) >= 0 && audioBitrate > 0 {
            info["audioBitrate"] = Int(audioBitrate)
        }

        // Demuxer cache duration (seconds of video buffered)
        var cacheSeconds: Double = 0
        if getProperty(handle: handle, name: "demuxer-cache-duration", format: MPV_FORMAT_DOUBLE, value: &cacheSeconds) >= 0 {
            info["cacheSeconds"] = cacheSeconds
        }

        // Dropped frames
        var droppedFrames: Int64 = 0
        if getProperty(handle: handle, name: "frame-drop-count", format: MPV_FORMAT_INT64, value: &droppedFrames) >= 0 {
            info["droppedFrames"] = Int(droppedFrames)
        }

        return info
    }
}

// Dummy logger — forwards errors/warnings to StreamingLogger for in-player display.
// Console output is gated behind the "Show Streaming Logger" user preference.
final class Logger {
    static let shared = Logger()
    func log(_ message: String, type: String) {
        let showLogger = UserDefaults.standard.bool(forKey: "pref_showLogger")
        if showLogger {
            print("[\(type)] \(message)")
        }
        // Forward to StreamingLogger so errors/warnings appear in the player overlay.
        switch type.lowercased() {
        case "error":
            StreamingLogger.shared.error(message)
        case "warn":
            StreamingLogger.shared.warn(message)
        default:
            break
        }
    }
}