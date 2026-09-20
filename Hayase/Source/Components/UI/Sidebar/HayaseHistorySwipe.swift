//
//  HayaseHistorySwipe.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/routes/+layout.svelte (onNavigate skips view transitions for iOS back/forward, which swipes natively)
//

import UIKit

// MARK: - HayaseHistorySwipe

/// The interactive back/forward page swipe, laid out like UIKit's default navigation parallax.
final class HayaseHistorySwipe {
    enum Direction {
        case back
        case forward
    }

    private static let parallax: CGFloat = 0.25  // covered page sits width / 4 off
    private static let dimAlpha: CGFloat = 0.1
    private static let shadowWidth: CGFloat = 6
    private static let shadowAlpha: CGFloat = 0.2
    private static let duration: TimeInterval = 0.35
    private static let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.1878, y: 0.0023),
                                                        controlPoint2: CGPoint(x: 0.5399, y: 0.9629))

    let direction: Direction
    let current: UIView

    private let stage = UIView()
    private let destination: UIView
    private let dim = UIView()
    private let shadow = UIView()
    private let width: CGFloat
    private var progress: CGFloat = 0
    private var animator: UIViewPropertyAnimator?

    private var top: UIView { direction == .back ? current : destination }
    private var bottom: UIView { direction == .back ? destination : current }

    init(direction: Direction, current: UIView, destination: UIView, host: UIView) {
        self.direction = direction
        self.current = current
        self.destination = destination
        width = host.bounds.width

        stage.frame = host.bounds
        stage.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        stage.clipsToBounds = true
        stage.isUserInteractionEnabled = false

        for page in [current, destination] {
            page.transform = .identity
            page.frame = stage.bounds
        }

        dim.frame = stage.bounds
        dim.backgroundColor = UIColor.black.withAlphaComponent(Self.dimAlpha)
        dim.isUserInteractionEnabled = false

        let gradient = CAGradientLayer()
        gradient.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(Self.shadowAlpha).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        shadow.frame = CGRect(x: 0, y: 0, width: Self.shadowWidth, height: stage.bounds.height)
        gradient.frame = shadow.bounds
        shadow.layer.addSublayer(gradient)
        shadow.isUserInteractionEnabled = false

        stage.addSubview(bottom)
        stage.addSubview(dim)
        stage.addSubview(top)
        stage.addSubview(shadow)
        host.addSubview(stage)
        layout(progress: 0)
    }

    func update(progress: CGFloat) {
        self.progress = min(max(progress, 0), 1)
        layout(progress: self.progress)
    }

    func finish(completing: Bool, completion: @escaping () -> Void) {
        let target: CGFloat = completing ? 1 : 0
        let remaining = abs(target - progress)
        stage.isUserInteractionEnabled = true  // swallows touches while it settles
        let animator = UIViewPropertyAnimator(duration: Self.duration * TimeInterval(remaining),
                                              timingParameters: Self.timing)
        animator.addAnimations { [weak self] in
            self?.layout(progress: target)
        }
        animator.addCompletion { [weak self] _ in
            self?.progress = target
            self?.animator = nil
            completion()
        }
        self.animator = animator
        animator.startAnimation()
    }

    func remove() {
        animator?.stopAnimation(true)
        animator = nil
        stage.removeFromSuperview()
    }

    private func layout(progress p: CGFloat) {
        let topX: CGFloat
        let bottomX: CGFloat
        let dimLevel: CGFloat
        switch direction {
        case .back:
            topX = p * width
            bottomX = -width * Self.parallax * (1 - p)
            dimLevel = 1 - p
        case .forward:
            topX = width * (1 - p)
            bottomX = -width * Self.parallax * p
            dimLevel = p
        }
        top.transform = CGAffineTransform(translationX: topX, y: 0)
        bottom.transform = CGAffineTransform(translationX: bottomX, y: 0)
        dim.alpha = dimLevel
        shadow.transform = CGAffineTransform(translationX: topX - Self.shadowWidth, y: 0)
        shadow.alpha = 1 - p
    }
}
