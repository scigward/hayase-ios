//
//  HayaseProgressBar.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: @prgm/sveltekit-progress-bar 2.0.0 dist/ProgressBar.svelte, mounted in src/routes/+layout.svelte (zIndex 100, displayThresholdMs 150) and restyled in src/app.css (.svelte-progress-bar)
//

import UIKit

// MARK: - HayaseProgressBar

final class HayaseProgressBar: UIView {
    static let barHeight: CGFloat = 2  // .svelte-progress-bar height: 2px

    private static let minimum: CGFloat = 0.08
    private static let maximum: CGFloat = 0.994
    private static let stepSizes: [CGFloat] = [0, 0.005, 0.01, 0.02]
    private static let intervalTime: TimeInterval = 0.7  // intervalTime = 700
    private static let settleTime: TimeInterval = 0.7  // settleTime = 700
    private static let displayThreshold: TimeInterval = 0.15  // displayThresholdMs = 150
    private static let leaderSize = CGSize(width: 100, height: 4)  // width: 100px, .svelte-progress-bar-leader height: 4px
    private static let leaderAngle: CGFloat = 2.5 * .pi / 180  // rotate(2.5deg)
    private static let leaderLift: CGFloat = 4  // translate(0px, -4px)
    private static let leaderGlow: CGFloat = 4  // box-shadow: 0 0 8px, blur radius / 2
    private static let hiddenOffset: CGFloat = -8  // .svelte-progress-bar-hiding top: -8px
    private static let widthTiming = (duration: 0.21, controlPoint1: CGPoint(x: 0.42, y: 0), controlPoint2: CGPoint(x: 0.58, y: 1))  // width 0.21s ease-in-out
    private static let hideTiming = (duration: 0.8, controlPoint1: CGPoint(x: 0.25, y: 0.1), controlPoint2: CGPoint(x: 0.25, y: 1))  // top 0.8s ease

    private let bar = UIView()
    private let leader = UIView()
    private var running = false
    private var completed = false
    private var width: CGFloat = 0
    private var updater: Timer?
    private var pendingStart: DispatchWorkItem?
    private var animator: UIViewPropertyAnimator?
    private var laidOutWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        updater?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width != laidOutWidth else { return }
        laidOutWidth = bounds.width
        stopAnimation()
        layoutBar()
    }

    // MARK: beforeNavigate / afterNavigate

    func navigationWillBegin() {
        pendingStart?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.start() }
        pendingStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayThreshold, execute: work)
    }

    func navigationDidFinish() {
        pendingStart?.cancel()
        pendingStart = nil
        complete()
    }

    // MARK: State machine

    private func start() {
        pendingStart = nil
        width = Self.minimum
        running = true
        render()
        animate()
    }

    private func animate() {
        updater?.invalidate()
        running = true
        let timer = Timer(timeInterval: Self.intervalTime, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        updater = timer
    }

    private func tick() {
        let step = Self.increment(for: width) + (Self.stepSizes.randomElement() ?? 0)
        if width < Self.maximum {
            width += step
        }
        if width > Self.maximum {
            width = Self.maximum
            updater?.invalidate()
        }
        render()
    }

    private func complete() {
        updater?.invalidate()
        guard running else { return }
        width = 1
        running = false
        render()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleTime) { [weak self] in
            self?.completed = true
            self?.render()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleTime) { [weak self] in
                self?.completed = false
                self?.width = 0
                self?.render()
            }
        }
    }

    private static func increment(for progress: CGFloat) -> CGFloat {
        switch progress {
        case 0..<0.2: return 0.1
        case 0.2..<0.5: return 0.04
        case 0.5..<0.8: return 0.02
        case 0.8..<0.99: return 0.005
        default: return 0
        }
    }

    // MARK: Rendering

    private func setup() {
        isUserInteractionEnabled = false
        let color = UIColor.HayaseTheme.foreground  // currentColor

        bar.backgroundColor = color
        bar.isHidden = true
        bar.accessibilityTraits = .updatesFrequently  // role="progressbar"
        addSubview(bar)

        leader.backgroundColor = color
        leader.layer.shadowColor = color.cgColor
        leader.layer.shadowOpacity = 1
        leader.layer.shadowRadius = Self.leaderGlow
        leader.layer.shadowOffset = .zero
        leader.bounds = CGRect(origin: .zero, size: Self.leaderSize)
        leader.transform = CGAffineTransform(rotationAngle: Self.leaderAngle)
        leader.isHidden = true
        bar.addSubview(leader)
    }

    private func render() {
        let wasVisible = !bar.isHidden
        let isVisible = running || width > 0
        bar.isHidden = !isVisible
        leader.isHidden = !running
        bar.isAccessibilityElement = isVisible
        bar.accessibilityValue = String(format: "%d%%", Int(safe: Double((width * 100).rounded())))  // aria-valuenow
        stopAnimation()
        guard isVisible else { return }
        guard wasVisible else {
            layoutBar()
            return
        }
        // once completed, the top transition replaces the width one
        let timing = completed ? Self.hideTiming : Self.widthTiming
        let animator = UIViewPropertyAnimator(duration: timing.duration,
                                              controlPoint1: timing.controlPoint1,
                                              controlPoint2: timing.controlPoint2) { [weak self] in self?.layoutBar() }
        self.animator = animator
        animator.startAnimation()
    }

    private func layoutBar() {
        let barWidth = width > 0 ? bounds.width * width : 0
        bar.frame = CGRect(x: 0, y: completed ? Self.hiddenOffset : 0, width: barWidth, height: Self.barHeight)
        let lift = CGPoint(x: 0, y: -Self.leaderLift).applying(CGAffineTransform(rotationAngle: Self.leaderAngle))
        leader.center = CGPoint(x: barWidth - Self.leaderSize.width / 2 + lift.x,
                                y: Self.leaderSize.height / 2 + lift.y)
    }

    private func stopAnimation() {
        guard let animator, animator.state == .active else { return }
        animator.stopAnimation(false)
        animator.finishAnimation(at: .current)
    }
}
