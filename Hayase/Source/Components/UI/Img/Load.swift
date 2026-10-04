//
//  Load.swift
//  Hayase
//
//  Mirrors: interface components/ui/img/load.svelte.
//

import UIKit

/// A view that shows one image and can be revealed by `LoadIn`.
protocol LoadInImageHost: UIView {
    var image: UIImage? { get set }
    /// How the image sits in the host's own box, and so how its softened copy must.
    var imageContentMode: UIView.ContentMode { get }
}

extension UIImageView: LoadInImageHost {
    var imageContentMode: UIView.ContentMode { contentMode }
}

/// How `Load` reveals an image: it fades in over 300ms, and an image that was ready almost
/// straight away (still inside the 300ms `load-in` animation) also starts 6px blurred and
/// clears as it fades. UIKit cannot animate a Gaussian blur, so the blurred stage is a
/// heavily downsampled copy that fades out over the sharp image.
enum LoadIn {
    /// How long after the image was inserted it can still show the blur.
    static let blurWindow: TimeInterval = 0.3

    private static let duration: TimeInterval = 0.3
    private static let blurRadius: CGFloat = 6

    static func show(_ image: UIImage, in host: LoadInImageHost, blurred: Bool) {
        host.subviews.forEach { $0.removeFromSuperview() }
        host.image = image

        // transition-[opacity,filter] duration-300, ease cubic-bezier(.4, 0, .2, 1)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = host.layer.opacity
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        host.layer.add(fade, forKey: "load-in")

        let content = host.bounds.inset(by: host.alignmentRectInsets)
        guard blurred, let soft = softened(image, displayWidth: content.width) else { return }
        let overlay = UIImageView(image: soft)
        overlay.contentMode = host.imageContentMode
        overlay.clipsToBounds = host.clipsToBounds
        // Pinned rather than framed, since the host may not have been laid out yet. A view's
        // anchors are its alignment rect, which is the image's own box when a host has bleed.
        overlay.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: host.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        // load-in: ease-out
        UIView.animate(withDuration: duration, delay: 0, options: .curveEaseOut, animations: {
            overlay.alpha = 0
        }, completion: { _ in
            overlay.removeFromSuperview()
        })
    }

    /// A copy small enough that scaling it back up blurs it by about `blurRadius` points.
    /// Box downsampling plus bilinear upscaling spreads a source pixel by roughly half the
    /// reduction factor.
    private static func softened(_ image: UIImage, displayWidth: CGFloat) -> UIImage? {
        let width = displayWidth > 0 ? displayWidth : UIScreen.main.bounds.width
        let pixelWidth = image.size.width * image.scale
        guard pixelWidth > 0 else { return nil }
        let factor = max(1, 2 * blurRadius * pixelWidth / width)
        let size = CGSize(width: max(1, (image.size.width / factor).rounded()),
                          height: max(1, (image.size.height / factor).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.interpolationQuality = .high
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
