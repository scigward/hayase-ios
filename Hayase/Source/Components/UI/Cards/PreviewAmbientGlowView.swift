// Mirrors preview.svelte's blur-2xl saturate-200 banner copy.
import UIKit
import CoreImage

/// A multicolored image glow, not a tinted shadow or a system-material backdrop.
/// Rendering is off-main, cancellable and cached; layout only positions the result.
final class PreviewAmbientGlowView: UIView {
    static let blurRadius: CGFloat = 40
    static let padding: CGFloat = blurRadius * 3

    private static let renderScale: CGFloat = 0.5
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: colorSpace,
        .outputColorSpace: colorSpace,
    ])
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 8 * 1_024 * 1_024
        return cache
    }()
    private static let renderQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Hayase.PreviewAmbientGlow"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private let bannerSize: CGSize
    private let imageView = UIImageView()
    private var renderOperation: BlockOperation?
    private var generation = 0

    init(bannerSize: CGSize) {
        self.bannerSize = bannerSize
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        clipsToBounds = false
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds.insetBy(dx: -Self.padding, dy: -Self.padding)
    }

    func configure(image: UIImage, cacheKey: String) {
        reset()
        let token = generation
        let size = bannerSize
        let key = "\(cacheKey)|\(size.width)x\(size.height)|blur40-saturate2" as NSString
        if let cached = Self.cache.object(forKey: key) {
            imageView.image = cached
            return
        }

        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard operation?.isCancelled == false else { return }
            let result = autoreleasepool { Self.render(image: image, bannerSize: size) }
            guard operation?.isCancelled == false, let result else { return }
            if let cgImage = result.cgImage {
                Self.cache.setObject(result, forKey: key,
                                     cost: cgImage.bytesPerRow * cgImage.height)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.renderOperation = nil
                self.imageView.image = result
            }
        }
        renderOperation = operation
        Self.renderQueue.addOperation(operation)
    }

    func reset() {
        generation += 1
        renderOperation?.cancel()
        renderOperation = nil
        imageView.image = nil
    }

    deinit { renderOperation?.cancel() }

    private static func render(image: UIImage, bannerSize: CGSize) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0,
              bannerSize.width > 0, bannerSize.height > 0 else { return nil }
        // A 40pt blur contains no sharp detail: half-resolution pixels are enough.
        // Include transparent padding BEFORE blurring so the edges fade outwards;
        // clamping the source would instead produce a hard rectangular glow.
        let padding = Self.padding * renderScale
        let target = CGSize(width: bannerSize.width * renderScale,
                            height: bannerSize.height * renderScale)
        let canvas = CGSize(width: target.width + padding * 2,
                            height: target.height + padding * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let thumbnail = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            let rect = CGRect(origin: CGPoint(x: padding, y: padding), size: target)
            UIBezierPath(roundedRect: rect,
                         byRoundingCorners: [.topLeft, .topRight],
                         cornerRadii: CGSize(width: 4 * renderScale, height: 4 * renderScale)).addClip()
            let scale = max(target.width / image.size.width, target.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: rect.midX - drawSize.width / 2,
                                  y: rect.midY - drawSize.height / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
        guard let input = CIImage(image: thumbnail) else { return nil }
        let output = input.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: blurRadius * renderScale,
        ]).applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 2,
        ])
        guard let cgImage = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
