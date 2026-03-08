import Foundation
import UIKit
import Libmpv
import CoreVideo
import CoreMedia
import AVFoundation

// MARK: - Models

struct MPVTrack {
    let id: Int
    let type: String        // "audio", "sub", "video"
    let title: String?
    let lang: String?
    let isSelected: Bool

    var displayName: String {
        if let t = title, !t.isEmpty { return t }
        if let l = lang,  !l.isEmpty { return l }
        return "\(type.capitalized) \(id)"
    }
}

struct MPVChapter {
    let index: Int
    let title: String
    let time: Double
}

// MARK: - Delegate

protocol MPVWrapperDelegate: AnyObject {
    func mpvTimeUpdated(current: Double, duration: Double)
    func mpvPauseChanged(_ isPaused: Bool)
    func mpvFileEnded()
    func mpvTracksChanged(_ tracks: [MPVTrack])
    func mpvChaptersChanged(_ chapters: [MPVChapter])
}

// MARK: - MPVWrapper

final class MPVWrapper {

    // MARK: - Private state

    private let displayLayer: AVSampleBufferDisplayLayer

    private let renderQueue  = DispatchQueue(label: "mpv.render",  qos: .userInitiated)
    private let eventQueue   = DispatchQueue(label: "mpv.events",  qos: .utility)
    private let stateQueue   = DispatchQueue(label: "mpv.state",   attributes: .concurrent)
    private let renderQueueKey = DispatchSpecificKey<Void>()

    // Pre-allocated arrays reused on every frame (only touched on renderQueue)
    private var dimensionsArray = [Int32](repeating: 0, count: 2)
    private var renderParams    = [mpv_render_param](
        repeating: mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil), count: 5)

    private let bgraFormatCString: [CChar] = Array("bgra\0".utf8CString)

    private var mpvHandle:     OpaquePointer?
    private var renderContext: OpaquePointer?
    private var videoSize:     CGSize = .zero

    private var pixelBufferPool:           CVPixelBufferPool?
    private var pixelBufferPoolAuxAttrs:   CFDictionary?
    private var formatDescription:         CMVideoFormatDescription?
    private var poolWidth  = 0
    private var poolHeight = 0

    private var isRunning        = false
    private var isStopping       = false
    private var isRenderScheduled = false
    private var lastRenderTime:  CFTimeInterval = 0
    private let minRenderInterval: CFTimeInterval

    var cachedDuration: Double = 0
    var cachedPosition: Double = 0
    private var _isPaused = true
    var isPaused: Bool { _isPaused }

    weak var delegate: MPVWrapperDelegate?

    // MARK: - Init

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        let maxFPS = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first?.maximumFramesPerSecond ?? 60
        self.minRenderInterval = 1.0 / CFTimeInterval(min(maxFPS, 60))
        renderQueue.setSpecific(key: renderQueueKey, value: ())
    }

    deinit { stop() }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        guard let handle = mpv_create() else { return }
        mpvHandle = handle

        setOption("terminal",               "no")
        setOption("msg-level",              "all=no")
        setOption("vo",                     "libmpv")
        setOption("hwdec",                  "videotoolbox-copy")
        setOption("keep-open",              "yes")
        setOption("idle",                   "yes")
        setOption("profile",                "fast")
        setOption("vd-lavc-threads",        "8")
        setOption("cache",                  "yes")
        setOption("demuxer-max-bytes",      "150M")
        setOption("demuxer-readahead-secs", "20")
        setOption("sub-auto",               "fuzzy")
        setOption("osc",                    "no")
        setOption("input-default-bindings", "no")
        setOption("input-vo-keyboard",      "no")
        setOption("ytdl",                   "no")
        setOption("audio-client-name",      "NyaiS")

        mpv_initialize(handle)
        createRenderContext()
        observeProperties()
        installWakeupHandler()
        isRunning = true
    }

    func stop() {
        guard isRunning || mpvHandle != nil else { return }
        guard !isStopping else { return }
        isRunning  = false
        isStopping = true

        renderQueue.sync { [weak self] in
            guard let self else { return }
            if let ctx = self.renderContext {
                mpv_render_context_set_update_callback(ctx, nil, nil)
                mpv_render_context_free(ctx)
                self.renderContext = nil
            }
            if let h = self.mpvHandle {
                mpv_set_wakeup_callback(h, nil, nil)
                self.execCommand(h, ["quit"])
            }
            self.formatDescription  = nil
            self.pixelBufferPool    = nil
            self.poolWidth          = 0
            self.poolHeight         = 0
        }

        renderQueue.sync { [weak self] in
            guard let self else { return }
            if let h = self.mpvHandle { mpv_destroy(h); self.mpvHandle = nil }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if #available(iOS 18, *) {
                self.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            } else {
                self.displayLayer.flushAndRemoveImage()
            }
        }
        isStopping = false
    }

    // MARK: - Render context

    private func createRenderContext() {
        guard let h = mpvHandle else { return }
        var apiType = MPV_RENDER_API_TYPE_SW
        withUnsafePointer(to: &apiType) { apiTypePtr in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                                 data: UnsafeMutableRawPointer(mutating: apiTypePtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            params.withUnsafeMutableBufferPointer { buf in
                _ = mpv_render_context_create(&renderContext, h, buf.baseAddress)
            }
        }
        guard renderContext != nil else { return }
        mpv_render_context_set_update_callback(renderContext, { ctx in
            guard let ctx else { return }
            Unmanaged<MPVWrapper>.fromOpaque(ctx).takeUnretainedValue().scheduleRender()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: - Property observation

    private func observeProperties() {
        guard let h = mpvHandle else { return }
        let props: [(String, mpv_format)] = [
            ("dwidth",       MPV_FORMAT_INT64),
            ("dheight",      MPV_FORMAT_INT64),
            ("duration",     MPV_FORMAT_DOUBLE),
            ("time-pos",     MPV_FORMAT_DOUBLE),
            ("pause",        MPV_FORMAT_FLAG),
            ("eof-reached",  MPV_FORMAT_FLAG),
            ("track-list",   MPV_FORMAT_NODE),
            ("chapter-list", MPV_FORMAT_NODE),
        ]
        for (name, format) in props {
            name.withCString { mpv_observe_property(h, 0, $0, format) }
        }
    }

    // MARK: - Wakeup / event processing

    private func installWakeupHandler() {
        guard let h = mpvHandle else { return }
        mpv_set_wakeup_callback(h, { userdata in
            guard let userdata else { return }
            Unmanaged<MPVWrapper>.fromOpaque(userdata).takeUnretainedValue().processEvents()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func processEvents() {
        eventQueue.async { [weak self] in
            guard let self, !self.isStopping else { return }
            while !self.isStopping {
                guard let h = self.mpvHandle,
                      let evPtr = mpv_wait_event(h, 0) else { return }
                let event = evPtr.pointee
                if event.event_id == MPV_EVENT_NONE { break }
                self.handleEvent(event)
                if event.event_id == MPV_EVENT_SHUTDOWN { break }
            }
        }
    }

    private func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_VIDEO_RECONFIG:
            refreshVideoSize()

        case MPV_EVENT_PROPERTY_CHANGE:
            guard let namePtr = event.data?
                .assumingMemoryBound(to: mpv_event_property.self).pointee.name else { return }
            refreshProperty(String(cString: namePtr))

        case MPV_EVENT_SHUTDOWN:
            break

        default:
            break
        }
    }

    private func refreshVideoSize() {
        var w: Int64 = 0, h: Int64 = 0
        getProperty(name: "dwidth",  format: MPV_FORMAT_INT64, value: &w)
        getProperty(name: "dheight", format: MPV_FORMAT_INT64, value: &h)
        let size = CGSize(width: max(Int(w), 0), height: max(Int(h), 0))
        stateQueue.async(flags: .barrier) { self.videoSize = size }
        renderQueue.async { [weak self] in
            guard let self else { return }
            if self.poolWidth != Int(w) || self.poolHeight != Int(h) {
                self.recreatePool(width: Int(max(w, 0)), height: Int(max(h, 0)))
            }
        }
    }

    private func refreshProperty(_ name: String) {
        switch name {
        case "duration":
            var v = 0.0
            if getProperty(name: name, format: MPV_FORMAT_DOUBLE, value: &v) >= 0 {
                cachedDuration = v
                DispatchQueue.main.async {
                    self.delegate?.mpvTimeUpdated(current: self.cachedPosition, duration: self.cachedDuration)
                }
            }
        case "time-pos":
            var v = 0.0
            if getProperty(name: name, format: MPV_FORMAT_DOUBLE, value: &v) >= 0 {
                cachedPosition = v
                DispatchQueue.main.async {
                    self.delegate?.mpvTimeUpdated(current: self.cachedPosition, duration: self.cachedDuration)
                }
            }
        case "pause":
            var flag: Int32 = 0
            if getProperty(name: name, format: MPV_FORMAT_FLAG, value: &flag) >= 0 {
                let paused = flag != 0
                guard paused != _isPaused else { return }
                _isPaused = paused
                DispatchQueue.main.async { self.delegate?.mpvPauseChanged(paused) }
            }
        case "eof-reached":
            var flag: Int32 = 0
            if getProperty(name: name, format: MPV_FORMAT_FLAG, value: &flag) >= 0, flag != 0 {
                DispatchQueue.main.async { self.delegate?.mpvFileEnded() }
            }
        case "track-list":
            let tracks = parseTrackList()
            DispatchQueue.main.async { self.delegate?.mpvTracksChanged(tracks) }
        case "chapter-list":
            let chapters = parseChapterList()
            DispatchQueue.main.async { self.delegate?.mpvChaptersChanged(chapters) }
        default:
            break
        }
    }

    // MARK: - Render scheduling

    private func scheduleRender() {
        renderQueue.async { [weak self] in
            guard let self, self.isRunning, !self.isStopping else { return }
            let now     = CACurrentMediaTime()
            let elapsed = now - self.lastRenderTime
            if elapsed < self.minRenderInterval {
                guard !self.isRenderScheduled else { return }
                self.isRenderScheduled = true
                self.renderQueue.asyncAfter(deadline: .now() + (self.minRenderInterval - elapsed)) { [weak self] in
                    guard let self else { return }
                    self.lastRenderTime    = CACurrentMediaTime()
                    self.performRenderUpdate()
                    self.isRenderScheduled = false
                }
                return
            }
            self.isRenderScheduled = true
            self.lastRenderTime    = now
            self.performRenderUpdate()
            self.isRenderScheduled = false
        }
    }

    private func performRenderUpdate() {
        guard let ctx = renderContext else { return }
        let flags = mpv_render_context_update(ctx)
        if UInt32(flags) & MPV_RENDER_UPDATE_FRAME.rawValue != 0 { renderFrame() }
        if flags > 0 { scheduleRender() }
    }

    // MARK: - Frame rendering  (CVPixelBuffer → AVSampleBufferDisplayLayer)

    private func renderFrame() {
        guard let ctx = renderContext else { return }
        let vSize = stateQueue.sync { videoSize }
        guard vSize.width > 0, vSize.height > 0 else { return }

        let width  = Int(vSize.width)
        let height = Int(vSize.height)
        if poolWidth != width || poolHeight != height { recreatePool(width: width, height: height) }

        var pixelBuffer: CVPixelBuffer?
        if let pool = pixelBufferPool {
            CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                kCFAllocatorDefault, pool, pixelBufferPoolAuxAttrs, &pixelBuffer)
        }
        if pixelBuffer == nil {
            let attrs: [CFString: Any] = [
                kCVPixelBufferIOSurfacePropertiesKey:   [:] as CFDictionary,
                kCVPixelBufferMetalCompatibilityKey:    kCFBooleanTrue!,
                kCVPixelBufferWidthKey:                 width,
                kCVPixelBufferHeightKey:                height,
                kCVPixelBufferPixelFormatTypeKey:       kCVPixelFormatType_32BGRA,
            ]
            CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        }
        guard let buffer = pixelBuffer else { return }

        CVPixelBufferLockBaseAddress(buffer, [])
        guard let baseAddr = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, []); return
        }

        dimensionsArray[0] = Int32(width)
        dimensionsArray[1] = Int32(height)
        var stride: Int    = CVPixelBufferGetBytesPerRow(buffer)

        dimensionsArray.withUnsafeMutableBufferPointer { dimsPtr in
            bgraFormatCString.withUnsafeBufferPointer { fmtPtr in
                withUnsafePointer(to: &stride) { stridePtr in
                    renderParams[0] = mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE,
                                                       data: UnsafeMutableRawPointer(dimsPtr.baseAddress))
                    renderParams[1] = mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT,
                                                       data: UnsafeMutableRawPointer(mutating: fmtPtr.baseAddress))
                    renderParams[2] = mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE,
                                                       data: UnsafeMutableRawPointer(mutating: stridePtr))
                    renderParams[3] = mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER,
                                                       data: baseAddr)
                    renderParams[4] = mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                    mpv_render_context_render(ctx, &renderParams)
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(buffer, [])
        enqueueBuffer(buffer)
    }

    private func enqueueBuffer(_ buffer: CVPixelBuffer) {
        let descChanged = updateFormatDescription(for: buffer)
        guard let fd = formatDescription else { return }

        let pts = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: fd,
            sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let failed: Bool
            if #available(iOS 18, *) {
                failed = self.displayLayer.sampleBufferRenderer.status == .failed
            } else {
                failed = self.displayLayer.status == .failed
            }

            if failed || descChanged {
                if #available(iOS 18, *) {
                    self.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
                } else {
                    self.displayLayer.flushAndRemoveImage()
                }
            }

            if self.displayLayer.controlTimebase == nil {
                var tb: CMTimebase?
                if CMTimebaseCreateWithSourceClock(
                    allocator: kCFAllocatorDefault,
                    sourceClock: CMClockGetHostTimeClock(),
                    timebaseOut: &tb) == noErr, let tb {
                    CMTimebaseSetRate(tb, rate: 1.0)
                    CMTimebaseSetTime(tb, time: pts)
                    self.displayLayer.controlTimebase = tb
                }
            }

            if #available(iOS 18, *) {
                self.displayLayer.sampleBufferRenderer.enqueue(sample)
            } else {
                self.displayLayer.enqueue(sample)
            }
        }
    }

    @discardableResult
    private func updateFormatDescription(for buffer: CVPixelBuffer) -> Bool {
        let w   = Int32(CVPixelBufferGetWidth(buffer))
        let h   = Int32(CVPixelBufferGetHeight(buffer))
        let fmt = CVPixelBufferGetPixelFormatType(buffer)
        if let desc = formatDescription {
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            if dims.width == w, dims.height == h,
               CMFormatDescriptionGetMediaSubType(desc) == fmt { return false }
        }
        var newDesc: CMVideoFormatDescription?
        if CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescriptionOut: &newDesc) == noErr, let newDesc {
            formatDescription = newDesc
        }
        return true
    }

    // MARK: - CVPixelBufferPool

    private func createPool(width: Int, height: Int) {
        let bufAttrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey:       kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey:                 width,
            kCVPixelBufferHeightKey:                height,
            kCVPixelBufferIOSurfacePropertiesKey:   [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey:    kCFBooleanTrue!,
        ]
        let poolAttrs: [CFString: Any] = [kCVPixelBufferPoolMinimumBufferCountKey: 4]
        let auxAttrs:  [CFString: Any] = [kCVPixelBufferPoolAllocationThresholdKey: 8]
        var pool: CVPixelBufferPool?
        if CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                   poolAttrs as CFDictionary,
                                   bufAttrs  as CFDictionary,
                                   &pool) == kCVReturnSuccess, let pool {
            pixelBufferPool       = pool
            pixelBufferPoolAuxAttrs = auxAttrs as CFDictionary
            poolWidth  = width
            poolHeight = height
        }
    }

    private func recreatePool(width: Int, height: Int) {
        pixelBufferPool     = nil
        formatDescription   = nil
        poolWidth           = 0
        poolHeight          = 0
        guard width > 0, height > 0 else { return }
        createPool(width: width, height: height)
    }

    // MARK: - Option / property helpers

    private func setOption(_ name: String, _ value: String) {
        guard let h = mpvHandle else { return }
        name.withCString { n in value.withCString { v in mpv_set_option_string(h, n, v) } }
    }

    private func setPropertyStr(_ name: String, _ value: String) {
        guard let h = mpvHandle else { return }
        name.withCString { n in value.withCString { v in mpv_set_property_string(h, n, v) } }
    }

    @discardableResult
    private func getProperty<T>(name: String, format: mpv_format, value: inout T) -> Int32 {
        guard let h = mpvHandle else { return -1 }
        return name.withCString { n in
            withUnsafeMutablePointer(to: &value) { mpv_get_property(h, n, format, $0) }
        }
    }

    // MARK: - Command helper (Luna pattern: strdup + withMemoryRebound)

    private func execCommand(_ handle: OpaquePointer, _ args: [String]) {
        guard !args.isEmpty else { return }
        withCStringArray(args) { mpv_command_async(handle, 0, $0) }
    }

    @inline(__always)
    private func withCStringArray<R>(_ args: [String],
                                     body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> R) -> R {
        var cs = [UnsafeMutablePointer<CChar>?]()
        cs.reserveCapacity(args.count + 1)
        for s in args { cs.append(strdup(s)) }
        cs.append(nil)
        defer { cs.forEach { if let p = $0 { free(p) } } }
        return cs.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) {
                body(UnsafeMutablePointer(mutating: $0))
            }
        }
    }

    // MARK: - Public playback API

    func loadFile(_ path: String) {
        guard mpvHandle != nil else { return }
        renderQueue.async { [weak self] in
            guard let self, let h = self.mpvHandle else { return }
            self.execCommand(h, ["loadfile", path, "replace"])
        }
    }

    func play()        { setPropertyStr("pause", "no") }
    func pause()       { setPropertyStr("pause", "yes") }
    func togglePause() { _isPaused ? play() : pause() }

    func seek(to seconds: Double) {
        guard let h = mpvHandle else { return }
        execCommand(h, ["seek", String(format: "%.3f", max(0, seconds)), "absolute"])
    }

    func setPlaybackRate(_ r: Double)   { setPropertyStr("speed",     String(r)) }
    func setSubtitleTrack(_ id: Int)    { setPropertyStr("sid",       id > 0 ? "\(id)" : "no") }
    func setAudioTrack(_ id: Int)       { setPropertyStr("aid",       "\(id)") }
    func setSubtitleDelay(_ d: Double)  { setPropertyStr("sub-delay", String(d)) }
    func screenshot()                   {
        guard let h = mpvHandle else { return }
        execCommand(h, ["screenshot", "subtitles"])
    }

    func getDouble(_ name: String) -> Double? {
        var v = 0.0
        return getProperty(name: name, format: MPV_FORMAT_DOUBLE, value: &v) >= 0 ? v : nil
    }

    // MARK: - Node parsing (track-list / chapter-list)

    private func parseTrackList() -> [MPVTrack] {
        guard let h = mpvHandle else { return [] }
        var node = mpv_node()
        guard "track-list".withCString({ mpv_get_property(h, $0, MPV_FORMAT_NODE, &node) }) == 0 else { return [] }
        defer { mpv_free_node_contents(&node) }
        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list else { return [] }

        var tracks: [MPVTrack] = []
        for i in 0..<Int(list.pointee.num) {
            let item = list.pointee.values[i]
            guard item.format == MPV_FORMAT_NODE_MAP, let map = item.u.list else { continue }
            var trackId: Int?; var type: String?; var title: String?; var lang: String?; var selected = false
            for j in 0..<Int(map.pointee.num) {
                let key = String(cString: map.pointee.keys[j])
                let val = map.pointee.values[j]
                switch key {
                case "id":       if val.format == MPV_FORMAT_INT64  { trackId  = Int(val.u.int64) }
                case "type":     if val.format == MPV_FORMAT_STRING { type     = String(cString: val.u.string) }
                case "title":    if val.format == MPV_FORMAT_STRING { title    = String(cString: val.u.string) }
                case "lang":     if val.format == MPV_FORMAT_STRING { lang     = String(cString: val.u.string) }
                case "selected": if val.format == MPV_FORMAT_FLAG   { selected = val.u.flag != 0 }
                default: break
                }
            }
            if let id = trackId, let type {
                tracks.append(MPVTrack(id: id, type: type, title: title, lang: lang, isSelected: selected))
            }
        }
        return tracks
    }

    private func parseChapterList() -> [MPVChapter] {
        guard let h = mpvHandle else { return [] }
        var node = mpv_node()
        guard "chapter-list".withCString({ mpv_get_property(h, $0, MPV_FORMAT_NODE, &node) }) == 0 else { return [] }
        defer { mpv_free_node_contents(&node) }
        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list else { return [] }

        var chapters: [MPVChapter] = []
        for i in 0..<Int(list.pointee.num) {
            let item = list.pointee.values[i]
            guard item.format == MPV_FORMAT_NODE_MAP, let map = item.u.list else { continue }
            var chTitle = "Chapter \(i + 1)"; var time = 0.0
            for j in 0..<Int(map.pointee.num) {
                let key = String(cString: map.pointee.keys[j])
                let val = map.pointee.values[j]
                switch key {
                case "title": if val.format == MPV_FORMAT_STRING { chTitle = String(cString: val.u.string) }
                case "time":  if val.format == MPV_FORMAT_DOUBLE { time    = val.u.double_ }
                default: break
                }
            }
            chapters.append(MPVChapter(index: i, title: chTitle, time: time))
        }
        return chapters
    }
}
