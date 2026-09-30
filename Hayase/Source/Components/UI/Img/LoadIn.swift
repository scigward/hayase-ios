//
//  LoadIn.swift
//  Hayase
//
//  Mirrors: interface components/ui/img/load.svelte.
//

import UIKit

/// How `Load` reveals an image: it fades in over 300ms, and an image that was ready almost
/// straight away (still inside the 300ms `load-in` animation) also starts 6px blurred and
/// clears as it fades. UIKit cannot animate a Gaussian blur, so the blurred stage is a
/// heavily downsampled copy that fades out over the sharp image.
enum LoadIn {
    /// How long after the image was inserted it can still show the blur.
    static let blurWindow: TimeInterval = 0.3

    private static let duration: TimeInterval = 0.3
    private static let blurRadius: CGFloat = 6

    static func show(_ image: UIImage, in imageView: UIImageView, blurred: Bool) {
        imageView.subviews.forEach { $0.removeFromSuperview() }
        imageView.image = image

        // transition-[opacity,filter] duration-300, ease cubic-bezier(.4, 0, .2, 1)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = imageView.layer.opacity
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        imageView.layer.add(fade, forKey: "load-in")

        guard blurred, let soft = softened(image, displayWidth: imageView.bounds.width) else { return }
        let overlay = UIImageView(image: soft)
        overlay.contentMode = imageView.contentMode
        overlay.clipsToBounds = imageView.clipsToBounds
        overlay.frame = imageView.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.addSubview(overlay)
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
