// Mirrors CSS filter: blur() in EpisodesList.svelte and anime/[id]/+layout.svelte.
import UIKit
import CoreImage

/// Blurs the content itself without the tint or saturation of a system backdrop.
/// Radius is in logical points, just as CSS pixels scale with the interface zoom.
///
/// The content is drawn into an image and blurred once the layout pass that sized it is over: drawing it from
/// `layoutSubviews`, with `layoutIfNeeded` on the content, laid its ancestors out inside their own pass, which
/// left a card that was made while it had a blur (and the rating badge under the title) without its content.
final class HayaseContentBlurView: UIView {
    let contentView: UIView
    var radius: CGFloat = 0 { didSet { invalidateBlur() } }
    private let renderedView = UIImageView()
    private static let context = CIContext(options: nil)
    /// The first blur of a session sets Core Image up, which takes long enough to be felt in a scroll.
    private static let warmUp: Void = {
        DispatchQueue.global(qos: .userInitiated).async { _ = HayaseContentBlurView.context }
    }()
    private var renderedSize = CGSize.zero
    private var needsRender = true
    private var renderScheduled = false

    init(content: UIView) {
        _ = Self.warmUp
        contentView = content
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            setContentHuggingPriority(content.contentHuggingPriority(for: axis), for: axis)
            setContentCompressionResistancePriority(content.contentCompressionResistancePriority(for: axis), for: axis)
        }
        renderedView.isUserInteractionEnabled = false
        renderedView.isHidden = true
        addSubview(renderedView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func invalidateBlur() {
        needsRender = true
        // Never briefly expose unblurred spoilers while waiting for layout.
        contentView.isHidden = radius > 0
        renderedView.isHidden = radius <= 0
        if radius <= 0 {
            renderedView.image = nil
            renderedSize = .zero
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard radius > 0, bounds.width > 0, bounds.height > 0 else { return }
        guard needsRender || renderedSize != bounds.size else { return }
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderScheduled = false
            self.renderBlurIfNeeded()
        }
    }

    /// Draws and blurs the content now, for a change that has to show in the same animation as the content.
    /// Never from inside a layout pass.
    func renderBlurIfNeeded() {
        guard radius > 0, bounds.width > 0, bounds.height > 0 else { return }
        guard needsRender || renderedSize != bounds.size else { return }
        needsRender = false
        renderedSize = bounds.size
        let padding = ceil(radius * 3)
        let imageBounds = bounds.insetBy(dx: -padding, dy: -padding)
        let format = UIGraphicsImageRendererFormat()
        format.scale = window?.screen.scale ?? UIScreen.main.scale
        format.opaque = false
        contentView.isHidden = false
        contentView.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: imageBounds.size, format: format).image { context in
            context.cgContext.translateBy(x: padding, y: padding)
            contentView.layer.render(in: context.cgContext)
        }
        contentView.isHidden = true
        renderedView.frame = imageBounds
        guard let input = CIImage(image: image),
              let filter = CIFilter(name: "CIGaussianBlur") else { return }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius * image.scale, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage,
              let cgImage = Self.context.createCGImage(output, from: input.extent) else { return }
        renderedView.image = UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }
}
