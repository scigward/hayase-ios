// Mirrors: hayase-app/interface/src/lib/components/ui/player/subtitles.ts (initSubtitleRenderer, maxRenderHeight)

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
    private let queueKey = DispatchSpecificKey<Void>()
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
        queue.setSpecific(key: queueKey, value: ())
        observeDisplayLayerStatus()
    }

    private var isOnQueue: Bool {
        DispatchQueue.getSpecific(key: queueKey) != nil
    }

    private func withHandle<T>(_ defaultValue: T, _ body: (OpaquePointer) -> T) -> T {
        if isOnQueue {
            guard let handle = mpv, !isStopping else { return defaultValue }
            return body(handle)
        }

        return queue.sync {
            guard let handle = self.mpv, !self.isStopping else { return defaultValue }
            return body(handle)
        }
    }

    private func withHandleAsync(_ body: @escaping (OpaquePointer) -> Void) {
        queue.async { [weak self] in
            guard let self, let handle = self.mpv, !self.isStopping else { return }
            body(handle)
        }
    }
    
    private func observeDisplayLayerStatus() {
        statusObservation = displayLayer.observe(\.status, options: [.new]) { [weak self] layer, _ in
            guard let self else { return }
            if layer.status == .failed {
                if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("🔧 Display layer failed - auto-resetting decoder") }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // AVSampleBufferDisplayLayer does not resume accepting
                    // samples after a failure until its failed image is flushed.
                    self.displayLayer.flushAndRemoveImage()
                    self.queue.async { [weak self] in
                        self?.performDecoderReset()
                    }
                }
            }
        }
    }
    
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
        appliedDeband = false

        let mpvLogLevel = Settings.debugLevel == "*" ? "debug" : "warn"
        checkError(mpv_request_log_messages(handle, mpvLogLevel))

        let layerPtrInt = Int(bitPattern: Unmanaged.passUnretained(displayLayer).toOpaque())
        var displayLayerPtr = Int64(layerPtrInt)
        checkError(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &displayLayerPtr))

        checkError(mpv_set_option_string(handle, "vo", "avfoundation"))
        checkError(mpv_set_option_string(handle, "avfoundation-composite-osd", "yes"))
        // Read once at start; a changed setting applies from the next player.
        let subtitleRenderHeight = Int(Settings.subtitleRenderHeight) ?? 0
        checkError(mpv_set_option_string(handle, "avfoundation-osd-render-height", String(subtitleRenderHeight)))
        configureSubtitleStyle(on: handle)

        #if targetEnvironment(simulator)
        checkError(mpv_set_option_string(handle, "hwdec", "no"))
        #else
        checkError(mpv_set_option_string(handle, "hwdec", "videotoolbox"))
        #endif
        checkError(mpv_set_option_string(handle, "hwdec-codecs", "all"))
        checkError(mpv_set_option_string(handle, "hwdec-software-fallback", "yes"))

        checkError(mpv_set_option_string(mpv, "subs-match-os-language", "yes"))
        checkError(mpv_set_option_string(mpv, "subs-fallback", "yes"))
        checkError(mpv_set_option_string(handle, "force-seekable", "yes"))
        checkError(mpv_set_option_string(handle, "demuxer-mkv-subtitle-preroll", "yes"))

        let initStatus = mpv_initialize(handle)
        guard initStatus >= 0 else {
            throw RendererError.mpvInitialization(initStatus)
        }

        observeProperties()

        mpv_set_wakeup_callback(handle, { ctx in
            guard let ctx = ctx else { return }
            let instance = Unmanaged<MPVWrapper>.fromOpaque(ctx).takeUnretainedValue()
            instance.processEvents()
        }, Unmanaged.passUnretained(self).toOpaque())
        isRunning = true
    }

    /// Mirrors interface `subtitles.ts` dialogue-style overrides. mpv/libass
    /// applies these only to subtitle dialogue it considers safe to override;
    /// embedded signs and typesetting remain governed by the ASS script.
    func applySubtitleStyle() {
        withHandle(()) { handle in configureSubtitleStyle(on: handle, initializing: false) }
    }

    func applyLoggingLevel() {
        withHandle(()) { handle in
            checkError(mpv_request_log_messages(handle, Settings.debugLevel == "*" ? "debug" : "warn"))
        }
    }

    private func configureSubtitleStyle(on handle: OpaquePointer, initializing: Bool = true) {
        let set: (String, String) -> Void = { name, value in
            self.checkError(initializing
                ? mpv_set_option_string(handle, name, value)
                : mpv_set_property_string(handle, name, value))
        }
        let selection = Settings.subtitleStyle
        guard selection != "none" else {
            set("sub-ass-override", "no")
            set("sub-ass-style-overrides", "")
            return
        }

        let font: String
        let spacing: String
        let scaleX: String
        switch selection {
        case "gandhisans":
            font = "Gandhi Sans"
            spacing = "0.2"
            scaleX = "98"
        case "notosans":
            font = "Noto Sans"
            spacing = "0"
            scaleX = "99"
        default:
            font = "Roboto Medium"
            spacing = "0"
            scaleX = "100"
        }

        let overrides = [
            "FontName=\(font)", "FontSize=72", "PrimaryColour=&H00FFFFFF",
            "SecondaryColour=&HFF000000", "OutlineColour=&H00000000",
            "BackColour=&H00000000", "Bold=1", "Italic=0", "Underline=0",
            "StrikeOut=0", "ScaleX=\(scaleX)", "ScaleY=100",
            "Spacing=\(spacing)", "Angle=0", "BorderStyle=1", "Outline=4",
            "Shadow=0", "Alignment=2", "MarginL=135", "MarginR=135", "MarginV=50",
        ].joined(separator: ",")
        set("sub-ass-override", "yes")
        set("sub-ass-style-overrides", overrides)
    }
    
    func stop() {
        if isStopping { return }
        if !isRunning, mpv == nil { return }
        isRunning = false
        isStopping = true
        
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
            self.command(handle, ["stop"])


            self.updateHTTPHeaders(headers)
            if let startPos = startPosition, startPos > 0 {
                self.setProperty(name: "start", value: String(format: "%.2f", startPos))
            } else {
                self.setProperty(name: "start", value: "0")
            }
            if let audioId = self.initialAudioId, audioId > 0 {
                self.setAudioTrack(audioId)
            }
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
        withHandleAsync { [weak self] handle in
            self?.apply(commands: preset.commands, on: handle)
        }
    }
    
    // MARK: - Property Helpers
    
    private func setOption(name: String, value: String) {
        withHandle(()) { handle in
            checkError(mpv_set_option_string(handle, name, value))
        }
    }
    
    private func setProperty(name: String, value: String) {
        withHandle(()) { handle in
            let status = mpv_set_property_string(handle, name, value)
            if status < 0 {
                Logger.shared.log("Failed to set property \(name)=\(value) (\(status))", type: "Warn")
            }
        }
    }
    
    private func clearProperty(name: String) {
        withHandle(()) { handle in
            let status = mpv_set_property_string(handle, name, "")
            if status < 0 {
                Logger.shared.log("Failed to clear property \(name) (\(status))", type: "Warn")
            }
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
            setDeband(Settings.deband)
            let hadExternalSubs = !pendingExternalSubtitles.isEmpty
            if hadExternalSubs, let handle = mpv {
                for (index, subUrl) in pendingExternalSubtitles.enumerated() {
                    if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("🔧 Adding external subtitle [\(index)]: \(subUrl)") }
                    commandSync(handle, ["sub-add", subUrl, "auto"])
                }
                pendingExternalSubtitles = []
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
            if isLoading {
                isLoading = false
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didChangeLoading: false)
                }
            }
            let chapters = getChapters()
            if !chapters.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didBecomeChaptersReady: chapters)
                }
            }
            
        case MPV_EVENT_SEEK:
            isSeeking = true
            if !isLoading {
                isLoading = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didChangeLoading: true)
                }
            }
            
        case MPV_EVENT_PLAYBACK_RESTART:
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
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value) >= 0 {
                cachedDuration = value
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didUpdatePosition: self.cachedPosition, duration: self.cachedDuration, cacheSeconds: self.cachedCacheSeconds)
                }
            }
        case "time-pos":
            var value = Double(0)
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value) >= 0 {
                cachedPosition = value
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
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value) >= 0 {
                cachedCacheSeconds = value
            }
        case "pause":
            var flag: Int32 = 0
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_FLAG, value: &flag) >= 0 {
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
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_FLAG, value: &flag) >= 0 {
                let buffering = flag != 0
                if buffering != isLoading {
                    isLoading = buffering
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.delegate?.renderer(self, didChangeLoading: buffering)
                    }
                }
            }
        case "track-list/count":
            var trackCount: Int64 = 0
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_INT64, value: &trackCount) >= 0 && trackCount > 0 {
                Logger.shared.log("Track list updated: \(trackCount) tracks available", type: "Info")
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didBecomeTracksReady: true)
                }
            }
        case "current-ao":
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
        let clamped = max(0, seconds)
        cachedPosition = clamped
        withHandle(()) { handle in
            commandSync(handle, ["seek", String(clamped), "absolute"])
        }
    }

    func seek(by seconds: Double) {
        let newPosition = max(0, cachedPosition + seconds)
        cachedPosition = newPosition
        withHandle(()) { handle in
            commandSync(handle, ["seek", String(seconds), "relative"])
        }
    }
    
    func syncTimebase() { }
    
    func setSpeed(_ speed: Double) {
        playbackSpeed = speed
        setProperty(name: "speed", value: String(speed))
    }
    
    func getSpeed() -> Double {
        withHandle(1.0) { handle in
            var speed: Double = 1.0
            getProperty(handle: handle, name: "speed", format: MPV_FORMAT_DOUBLE, value: &speed)
            return speed
        }
    }
    
    // MARK: - Subtitle Controls
    
    func getSubtitleTracks(mkvFileURL: URL? = nil) -> [[String: Any]] {
        withHandle([[String: Any]]()) { handle in
            var tracks: [[String: Any]] = []

            let mkvLanguages: [Int: String]
            if let fileURL = mkvFileURL {
                mkvLanguages = MatroskaMetadataService.shared.subtitleLanguages(for: fileURL)
            } else {
                mkvLanguages = [:]
            }

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

                if let mkvLang = mkvLanguages[Int(trackId)], mkvLang != "und" {
                    track["lang"] = mkvLang
                } else if let lang = getStringProperty(handle: handle, name: "track-list/\(i)/lang"), lang != "und" {
                    track["lang"] = lang
                } else if let demuxLang = getStringProperty(handle: handle, name: "track-list/\(i)/demux-lang"), demuxLang != "und" {
                    track["lang"] = demuxLang
                } else if let title = track["title"] as? String,
                          let parsed = Self.parseLanguageFromTitle(title) {
                    track["lang"] = parsed
                }

                var selected: Int32 = 0
                getProperty(handle: handle, name: "track-list/\(i)/selected", format: MPV_FORMAT_FLAG, value: &selected)
                track["selected"] = selected != 0

                Logger.shared.log("getSubtitleTracks: found sub track id=\(trackId), title=\(track["title"] ?? "none"), lang=\(track["lang"] ?? "none")", type: "Info")
                tracks.append(track)
            }

            return tracks
        }
    }

    func setSubtitleTrack(_ trackId: Int) {
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
        withHandle(0) { handle in
            var sid: Int64 = 0
            getProperty(handle: handle, name: "sid", format: MPV_FORMAT_INT64, value: &sid)
            return Int(sid)
        }
    }
    
    func addSubtitleFile(url: String, select: Bool = true) {
        let flag = select ? "select" : "cached"
        withHandle(()) { handle in
            commandSync(handle, ["sub-add", url, flag])
        }
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
    func setSubtitleDelay(_ delay: Double) {
        setProperty(name: "sub-delay", value: String(delay))
    }

    func captureScreenshotPNGData(completion: @escaping (Data?) -> Void) {
        queue.async { [weak self] in
            guard let self, let handle = self.mpv, !self.isStopping else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("hayase_screenshot_\(UUID().uuidString).png")
            let status = self.commandSync(handle, ["screenshot-to-file", url.path, "subtitles"])
            let data = status >= 0 ? try? Data(contentsOf: url) : nil
            try? FileManager.default.removeItem(at: url)

            DispatchQueue.main.async { completion(data) }
        }
    }

    // MARK: - Deband
    
    private var appliedDeband = false

    func setDeband(_ enabled: Bool) {
        withHandle(()) { handle in
            guard appliedDeband != enabled else { return }
            appliedDeband = enabled
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
    }

    // MARK: - Video Track Controls

    func getVideoTracks() -> [[String: Any]] {
        withHandle([[String: Any]]()) { handle in
            var tracks: [[String: Any]] = []
            var trackCount: Int64 = 0
            getProperty(handle: handle, name: "track-list/count", format: MPV_FORMAT_INT64, value: &trackCount)

            for i in 0..<trackCount {
                guard let trackType = getStringProperty(handle: handle, name: "track-list/\(i)/type"),
                      trackType == "video" else { continue }

                var trackId: Int64 = 0
                getProperty(handle: handle, name: "track-list/\(i)/id", format: MPV_FORMAT_INT64, value: &trackId)

                var track: [String: Any] = ["id": Int(trackId)]
                if let title = getStringProperty(handle: handle, name: "track-list/\(i)/title") {
                    track["title"] = title
                }
                if let lang = getStringProperty(handle: handle, name: "track-list/\(i)/lang"), lang != "und" {
                    track["lang"] = lang
                } else if let demuxLang = getStringProperty(handle: handle, name: "track-list/\(i)/demux-lang"), demuxLang != "und" {
                    track["lang"] = demuxLang
                }

                var selected: Int32 = 0
                getProperty(handle: handle, name: "track-list/\(i)/selected", format: MPV_FORMAT_FLAG, value: &selected)
                track["selected"] = selected != 0
                tracks.append(track)
            }

            return tracks
        }
    }

    func setVideoTrack(_ trackId: Int) {
        setProperty(name: "vid", value: String(trackId))
    }

    // MARK: - Audio Track Controls
    
    func getAudioTracks() -> [[String: Any]] {
        withHandle([[String: Any]]()) { handle in
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
                if let lang = getStringProperty(handle: handle, name: "track-list/\(i)/lang") {
                    track["lang"] = lang
                } else if let demuxLang = getStringProperty(handle: handle, name: "track-list/\(i)/demux-lang") {
                    track["lang"] = demuxLang
                } else if let title = track["title"] as? String,
                          let parsed = Self.parseLanguageFromTitle(title) {
                    track["lang"] = parsed
                }
                if let codec = getStringProperty(handle: handle, name: "track-list/\(i)/codec") {
                    track["codec"] = codec
                }

                var channels: Int64 = 0
                getProperty(handle: handle, name: "track-list/\(i)/audio-channels", format: MPV_FORMAT_INT64, value: &channels)
                if channels > 0 { track["channels"] = Int(channels) }

                var selected: Int32 = 0
                getProperty(handle: handle, name: "track-list/\(i)/selected", format: MPV_FORMAT_FLAG, value: &selected)
                track["selected"] = selected != 0
                tracks.append(track)
            }

            return tracks
        }
    }

    static func parseLanguageFromTitle(_ title: String) -> String? {
        let lower = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let languageMap: [(pattern: String, code: String)] = [
            ("japanese", "jpn"), ("english", "eng"), ("chinese", "chi"), ("korean", "kor"),
            ("french", "fre"), ("german", "ger"), ("spanish", "spa"), ("italian", "ita"),
            ("portuguese", "por"), ("russian", "rus"), ("arabic", "ara"), ("hindi", "hin"),
            ("thai", "tha"), ("vietnamese", "vie"), ("indonesian", "ind"), ("malay", "may"),
            ("polish", "pol"), ("dutch", "dut"), ("turkish", "tur"), ("romanian", "rum"),
            ("czech", "cze"), ("hungarian", "hun"), ("swedish", "swe"), ("norwegian", "nor"),
            ("danish", "dan"), ("finnish", "fin"), ("greek", "gre"), ("hebrew", "heb"),
            ("ukrainian", "ukr"), ("catalan", "cat"), ("latvian", "lav"), ("lithuanian", "lit"),
            ("brazilian", "por"),
        ]
        for entry in languageMap {
            if lower.contains(entry.pattern) { return entry.code }
        }
        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for word in words where word.count == 3 {
            if Locale.current.localizedString(forLanguageCode: word) != nil { return word }
        }
        for word in words where word.count == 2 {
            if Locale.current.localizedString(forLanguageCode: word) != nil { return word }
        }
        return nil
    }
    
    func setAudioTrack(_ trackId: Int) {
        setProperty(name: "aid", value: String(trackId))
    }
    
    func getCurrentAudioTrack() -> Int {
        withHandle(0) { handle in
            var aid: Int64 = 0
            getProperty(handle: handle, name: "aid", format: MPV_FORMAT_INT64, value: &aid)
            return Int(aid)
        }
    }

    // MARK: - Chapters
    
    func getChapters() -> [MPVChapter] {
        withHandle([MPVChapter]()) { handle in
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
            return chapters
        }
    }

    // MARK: - Technical Info
    
    func getTechnicalInfo() -> [String: Any] {
        withHandle([String: Any]()) { handle in
            var info: [String: Any] = [:]
            var videoWidth: Int64 = 0, videoHeight: Int64 = 0
            if getProperty(handle: handle, name: "video-params/w", format: MPV_FORMAT_INT64, value: &videoWidth) >= 0 {
                info["videoWidth"] = Int(videoWidth)
            }
            if getProperty(handle: handle, name: "video-params/h", format: MPV_FORMAT_INT64, value: &videoHeight) >= 0 {
                info["videoHeight"] = Int(videoHeight)
            }
            if let videoCodec = getStringProperty(handle: handle, name: "video-format") {
                info["videoCodec"] = videoCodec
            }
            if let audioCodec = getStringProperty(handle: handle, name: "audio-codec-name") {
                info["audioCodec"] = audioCodec
            }

            var fps: Double = 0
            if getProperty(handle: handle, name: "container-fps", format: MPV_FORMAT_DOUBLE, value: &fps) >= 0 && fps > 0 {
                info["fps"] = fps
            }
            var videoBitrate: Int64 = 0
            if getProperty(handle: handle, name: "video-bitrate", format: MPV_FORMAT_INT64, value: &videoBitrate) >= 0 && videoBitrate > 0 {
                info["videoBitrate"] = Int(videoBitrate)
            }
            var audioBitrate: Int64 = 0
            if getProperty(handle: handle, name: "audio-bitrate", format: MPV_FORMAT_INT64, value: &audioBitrate) >= 0 && audioBitrate > 0 {
                info["audioBitrate"] = Int(audioBitrate)
            }
            var cacheSeconds: Double = 0
            if getProperty(handle: handle, name: "demuxer-cache-duration", format: MPV_FORMAT_DOUBLE, value: &cacheSeconds) >= 0 {
                info["cacheSeconds"] = cacheSeconds
            }
            var droppedFrames: Int64 = 0
            if getProperty(handle: handle, name: "frame-drop-count", format: MPV_FORMAT_INT64, value: &droppedFrames) >= 0 {
                info["droppedFrames"] = Int(droppedFrames)
            }

            return info
        }
    }
}

final class Logger {
    static let shared = Logger()
    func log(_ message: String, type: String) {
        let showLogger = UserDefaults.standard.bool(forKey: "pref_showLogger") || Settings.debugLevel == "*"
        if showLogger {
            print("[\(type)] \(message)")
        }
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
