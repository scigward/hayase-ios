//
//  BannerImage.swift
//  Hayase
//
//  Mirrors: interface components/ui/banner/banner-image.svelte
//
//  The banner image is not part of a page. It sits at the top of the app, behind the route, and
//  the page that is showing says which media it is (`bannerSrc`) and whether it has been scrolled
//  out of sight (`hideBanner`).
//

import UIKit

enum BannerImage {
    /// `transition-opacity duration-500`, with Tailwind's default easing `cubic-bezier(0.4, 0, 0.2, 1)`.
    static let fadeDuration: TimeInterval = 0.5
    static let fadeTiming = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)

    /// `opacity-5`: how much of the banner is left once the page is scrolled past `hideThreshold`.
    static let hiddenAlpha: CGFloat = 0.05
    /// `hideBanner.value = target.scrollTop > 100`
    static let hideThreshold: CGFloat = 100

    private static let fadeKey = "banner-image-fade"

    /// Fades the opacity of `views` to `alpha`, from wherever a fade already under way has got to.
    /// `completion` runs once the fade is over, or at once when it is not animated.
    static func fade(_ views: [UIView], to alpha: CGFloat, animated: Bool = true, completion: (() -> Void)? = nil) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        for view in views {
            let from = view.layer.presentation()?.opacity ?? view.layer.opacity
            view.layer.removeAnimation(forKey: fadeKey)
            view.alpha = alpha
            guard animated else { continue }
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = from
            animation.toValue = Float(alpha)
            animation.duration = fadeDuration
            animation.timingFunction = fadeTiming
            view.layer.add(animation, forKey: fadeKey)
        }
        CATransaction.commit()
    }
}

// MARK: - What the sidebar is told

/// The sidebar shows a slice of the same banner. Its copy of `bannerSrc` and `hideBanner` is
/// kept up to date with this notification.
enum BannerBackdrop {
    static let didChange = Notification.Name("HayaseHomeBannerBackdropDidChange")
    static let homeRoute = "home"

    private static let urlKey = "url"
    private static let alphaKey = "alpha"
    private static let scrollOffsetKey = "scrollOffset"
    private static let heightKey = "height"
    private static let routeKey = "route"
    private static let mediaKey = "media"

    static func post(route: String = homeRoute,
                     height: CGFloat,
                     mediaID: Int?,
                     urlString: String? = nil,
                     scrollOffset: CGFloat? = nil,
                     alpha: CGFloat? = nil) {
        var userInfo: [String: Any] = [heightKey: height, routeKey: route]
        // The banner belongs to a media (`bannerSrc`); the sidebar drops the old one when it changes.
        if let mediaID { userInfo[mediaKey] = mediaID }
        if let urlString { userInfo[urlKey] = urlString }
        if let scrollOffset { userInfo[scrollOffsetKey] = scrollOffset }
        if let alpha { userInfo[alphaKey] = alpha }
        NotificationCenter.default.post(name: didChange, object: nil, userInfo: userInfo)
    }
}

// MARK: - BannerGradientView

/// `.banner-gr::after`: a radial gradient from the page background, clear in the middle and
/// opaque at the edges. Desktop centres it at 59.18%, below `md` at 50%.
final class BannerGradientView: UIView {
    private var centerX: CGFloat = 0.50

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
    }

    func setCompact(_ compact: Bool) {
        // banner-image.svelte:
        // desktop: radial-gradient(75% 65% at 59.18% 34.97%, ...)
        // mobile:  radial-gradient(75% 65% at 50% 34.97%, ...)
        let next: CGFloat = compact ? 0.50 : 0.5918
        guard next != centerX else { return }
        centerX = next
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0,
              let context = UIGraphicsGetCurrentContext() else { return }
        let background = UIColor.HayaseTheme.background
        // hsla(from var(--background) h s l / 0.16) 30.56%, var(--background) 100%
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [
                                            background.withAlphaComponent(0.16).cgColor,
                                            background.withAlphaComponent(0.16).cgColor,
                                            background.cgColor,
                                        ] as CFArray,
                                        locations: [0.0, 0.3056, 1.0]) else { return }

        let center = CGPoint(x: bounds.width * centerX, y: bounds.height * 0.3497)
        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: bounds.width * 0.75, y: bounds.height * 0.65)
        context.drawRadialGradient(gradient,
                                   startCenter: .zero,
                                   startRadius: 0,
                                   endCenter: .zero,
                                   endRadius: 1,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
}

// MARK: - BannerImageView

/// banner-image.svelte as the Home route draws it:
/// • rendered behind the scrollable route, not inside it
/// • 80vh high below `md`, 90vh from `md` up
/// • 100% opaque, 5% once the page is scrolled past `hideThreshold`
final class BannerImageView: UIView {
    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .clear
        return iv
    }()

    private let gradientView = BannerGradientView()
    private var imageHeightConstraint: NSLayoutConstraint!
    private var currentURLString: String?
    /// When the current image was announced, to tell an instant load from a slow one.
    private var urlAnnouncedAt: CFTimeInterval = 0
    private var isFaded = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = false

        [imageView, gradientView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageHeightConstraint,

            gradientView.topAnchor.constraint(equalTo: imageView.topAnchor),
            gradientView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            gradientView.heightAnchor.constraint(equalTo: imageView.heightAnchor),
        ])
    }

    /// `h-[80vh] md:h-[90vh]`, and the `banner-gr-sm` gradient below `md`.
    func configureForLayout(isRegular: Bool, viewHeight: CGFloat) {
        imageHeightConstraint.constant = viewHeight * (isRegular ? 0.90 : 0.80)
        gradientView.setCompact(!isRegular)
    }

    func setBackdrop(urlString: String?, image: UIImage?) {
        guard let urlString else {
            currentURLString = nil
            imageView.layer.removeAllAnimations()
            imageView.subviews.forEach { $0.removeFromSuperview() }
            imageView.image = nil
            return
        }

        if currentURLString != urlString {
            currentURLString = urlString
            urlAnnouncedAt = CACurrentMediaTime()
        }

        guard let image else { return }
        guard currentURLString == urlString else { return }

        imageView.layer.removeAllAnimations()
        if imageView.image == nil {
            // banner-image.svelte replaces the banner element on every change, so a new image
            // is always a fresh `Load` that fades in.
            LoadIn.show(image, in: imageView,
                        blurred: CACurrentMediaTime() - urlAnnouncedAt < LoadIn.blurWindow)
        } else {
            imageView.image = image
        }
    }

    func setFaded(_ faded: Bool, animated: Bool, completion: (() -> Void)? = nil) {
        let targetAlpha: CGFloat = faded ? BannerImage.hiddenAlpha : 1
        guard faded != isFaded || abs(imageView.alpha - targetAlpha) > 0.001 else {
            completion?()
            return
        }
        isFaded = faded
        BannerImage.fade([imageView, gradientView], to: targetAlpha, animated: animated, completion: completion)
    }
}
