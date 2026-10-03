//
//  SplashLogoView.swift
//  Hayase
//
//  Mirrors: the `.logo-container` of src/routes/+page.svelte
//
//    <div class='size-10 relative logo-container' on:animationend|self={navigate}>
//      <Logo class='size-10 [filter:url(#chromaticAberration)]' />
//      {#each spotlightData as s}<div class='spotlight …' />{/each}
//    </div>
//
//    .logo-container { animation: logo-scale .2s ease-out .2s both }    scale(5) → scale(1)
//
//    <filter id='chromaticAberration'>
//      red_  = the logo's red ×4 only            red  = red_ moved by dx 4  (4 → 0 over .1s from .15s)
//      blue_ = the logo's green ×3 and blue ×10  blue = blue_ moved by dx -6 (-6 → 0 over .1s from .15s)
//      feBlend screen: red and blue
//
//  The logo is white, so `red_` is pure red and `blue_` pure cyan, and where the two meet they screen
//  to white: the logo is drawn in red and in cyan, apart by 10 and coming together.
//  The filter's region is the box with 10% round it (4pt of the 40pt), which cuts off what the offsets
//  take beyond that.
//

import UIKit

final class SplashLogoView: UIView {
    /// `size-10`
    static let side: CGFloat = 40

    /// `animationend` of the scale: the logo has come to its size.
    var onScaleEnd: (() -> Void)?

    private let aberration = CALayer()
    private let region = CAShapeLayer()
    private let red = CAShapeLayer()
    private let cyan = CAShapeLayer()
    private let spotlights: [SplashSpotlightLayer]
    private var animationDelegate: ScaleDelegate?

    override init(frame: CGRect) {
        // The first moments show it five times as large: the bitmaps are as sharp as that
        let renderScale = max(UIScreen.main.scale, 2) * 5
        spotlights = SplashSpotlightSpec.all.map { SplashSpotlightLayer(spec: $0, renderScale: renderScale) }
        super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        isUserInteractionEnabled = false
        isAccessibilityElement = false

        // The logo in the box of the view, which is what `size-10` makes of the viewBox
        var fit = CGAffineTransform(scaleX: Self.side / HayaseLogo.viewBoxSide, y: Self.side / HayaseLogo.viewBoxSide)
        let path = HayaseLogo.path().copy(using: &fit)
        aberration.frame = bounds
        for (layer, color) in [(red, UIColor(red: 1, green: 0, blue: 0, alpha: 1)), (cyan, UIColor(red: 0, green: 1, blue: 1, alpha: 1))] {
            layer.frame = bounds
            layer.path = path
            layer.fillColor = color.cgColor
            aberration.addSublayer(layer)
        }
        cyan.compositingFilter = "screenBlendMode"

        // x -10% … 110% and y -10% … 110% of the box
        let inset = Self.side * 0.1
        region.frame = bounds
        region.path = UIBezierPath(rect: bounds.insetBy(dx: -inset, dy: -inset)).cgPath
        region.fillColor = UIColor.black.cgColor
        aberration.mask = region
        layer.addSublayer(aberration)

        spotlights.forEach { layer.addSublayer($0.root) }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.side, height: Self.side)
    }

    /// Everything runs from this moment, as the animations of the page do from its mount.
    func start() {
        let now = CACurrentMediaTime()
        let easeOut = CAMediaTimingFunction(controlPoints: 0, 0, 0.58, 1)    // ease-out

        // animation: logo-scale .2s ease-out .2s both
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 5
        scale.toValue = 1
        scale.duration = 0.2
        scale.beginTime = layer.convertTime(now, from: nil) + 0.2
        scale.timingFunction = easeOut
        scale.fillMode = .both
        scale.isRemovedOnCompletion = false
        let delegate = ScaleDelegate { [weak self] in self?.onScaleEnd?() }
        animationDelegate = delegate
        scale.delegate = delegate
        layer.add(scale, forKey: "logo-scale")

        // <animate attributeName='dx' values='4; 0' dur='0.1s' fill='freeze' begin='0.15s' />, and -6 → 0 for the cyan
        let linear = CAMediaTimingFunction(name: .linear)
        for (layer, offset) in [(red, CGFloat(4)), (cyan, CGFloat(-6))] {
            let move = CABasicAnimation(keyPath: "transform.translation.x")
            move.fromValue = offset
            move.toValue = 0
            move.duration = 0.1
            move.beginTime = layer.convertTime(now, from: nil) + 0.15
            move.timingFunction = linear
            move.fillMode = .both
            move.isRemovedOnCompletion = false
            layer.add(move, forKey: "chromatic-aberration")
        }

        spotlights.forEach { $0.start(at: now) }
    }
}

/// Tells when the scale has run to its end, and not when it was taken away.
private final class ScaleDelegate: NSObject, CAAnimationDelegate {
    private let finished: () -> Void

    init(finished: @escaping () -> Void) {
        self.finished = finished
    }

    func animationDidStop(_ animation: CAAnimation, finished flag: Bool) {
        if flag { finished() }
    }
}
