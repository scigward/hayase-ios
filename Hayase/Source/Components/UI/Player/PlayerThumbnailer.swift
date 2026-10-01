// Mirrors player/thumbnailer.ts: 12-second buckets, 700px frames, one active
// request and one replaceable next request, with a three-second timeout.
import UIKit
import AVFoundation

final class PlayerThumbnailer {
    static let interval: Double = 12
    private let cache = NSCache<NSNumber, UIImage>()
    private var generator: AVAssetImageGenerator?
    private var generation = UUID()
    private var active: (index: Int, completion: (UIImage?) -> Void)?
    private var next: (index: Int, completion: (UIImage?) -> Void)?
    private var timeout: DispatchWorkItem?
    private var capturing = false
    private var lastCaptureIndex: Int?
    private var requestID = UUID()

    init() { cache.totalCostLimit = 64 * 1024 * 1024 }
    deinit { generator?.cancelAllCGImageGeneration(); timeout?.cancel() }

    func updateSource(_ url: URL) {
        cancel()
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 700, height: 0)
        self.generator = generator
    }

    func cancel() {
        generation = UUID()
        generator?.cancelAllCGImageGeneration()
        generator = nil
        timeout?.cancel()
        active?.completion(nil)
        next?.completion(nil)
        active = nil
        next = nil
        capturing = false
        lastCaptureIndex = nil
        cache.removeAllObjects()
    }

    // MPV caches watched frames too, so previews remain available for containers
    // AVFoundation cannot decode, without seeking or replacing the active player.
    func rememberFrame(at time: Double, from renderer: MPVWrapper) {
        guard time.isFinite, time >= 0, !capturing else { return }
        let index = Int(time / Self.interval)
        guard lastCaptureIndex != index, cache.object(forKey: NSNumber(value: index)) == nil else { return }
        lastCaptureIndex = index
        capturing = true
        let token = generation
        renderer.captureScreenshotPNGData(includeSubtitles: false) { [weak self] data in
            guard let self, self.generation == token else { return }
            self.capturing = false
            guard let data, let image = UIImage(data: data), image.size.width > 0 else { return }
            let size = CGSize(width: 700, height: 700 * image.size.height / image.size.width)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            self.store(thumbnail, index: index)
        }
    }

    func thumbnail(at time: Double, completion: @escaping (UIImage?) -> Void) {
        guard time.isFinite, time >= 0 else { completion(nil); return }
        let index = Int(time / Self.interval)
        if let image = cache.object(forKey: NSNumber(value: index)) { completion(image); return }
        guard generator != nil else { completion(nil); return }
        if let active {
            if active.index == index {
                active.completion(nil)
                self.active = (index, completion)
            } else {
                next?.completion(nil)
                next = (index, completion)
            }
            return
        }
        active = (index, completion)
        generate()
    }
    private func generate() {
        guard let active, let generator else { return }
        let token = generation
        requestID = UUID()
        let request = requestID
        let index = active.index
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.requestID == request, self.active?.index == index else { return }
            self.generator?.cancelAllCGImageGeneration()
            self.finish(nil)
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        let time = CMTime(seconds: Double(index) * Self.interval, preferredTimescale: 600)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] _, image, _, _, _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.requestID == request, self.active?.index == index else { return }
                let thumbnail = image.map { UIImage(cgImage: $0) }
                if let thumbnail { self.store(thumbnail, index: index) }
                self.finish(thumbnail)
            }
        }
    }
    private func finish(_ image: UIImage?) {
        timeout?.cancel()
        let completion = active?.completion
        active = next
        next = nil
        completion?(image)
        generate()
    }
    private func store(_ image: UIImage, index: Int) {
        cache.setObject(image, forKey: NSNumber(value: index), cost: Int(image.size.width * image.size.height) * 4)
    }
}
