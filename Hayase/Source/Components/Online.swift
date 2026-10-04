//
//  Online.swift
//  Hayase
//
//  Mirrors: interface lib/components/Online.svelte (with lib/components/icons/AnilistError.svelte),
//  the bar above the app that says "Back online", "Offline" or what AniList answered.
//

import UIKit

/// The viewBox of AnilistError.svelte is 41×30, drawn at `size-[1.1rem]`.
private final class AnilistErrorIconView: UIView {
    private static let side: CGFloat = 17.6
    private static let first = SVGPath.path("M27.825 21.773V2.977c0-1.077-.613-1.672-1.725-1.672h-3.795c-1.111 0-1.725.595-1.725 1.672v8.927c0 .251 2.5 1.418 2.565 1.665 1.904 7.21.414 12.982-1.392 13.251 2.952.142 3.277 1.517 1.078.578.337-3.848 1.65-3.84 5.422-.142.032.032.774 1.539.82 1.539h8.91c1.113 0 1.726-.594 1.726-1.672v-3.677c0-1.078-.614-1.672-1.725-1.672H27.825z")
    private static let second = SVGPath.path("M12.07 1.306l-9.966 27.49h7.743l1.687-4.756h8.433l1.649 4.755h7.705l-9.929-27.49H12.07zm1.227 16.642l2.415-7.615 2.645 7.615h-5.06z")

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.side, height: Self.side)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        // preserveAspectRatio meet: the 41×30 drawing fitted into the square and centred
        let scale = min(bounds.width / 41, bounds.height / 30)
        context.translateBy(x: (bounds.width - 41 * scale) / 2, y: (bounds.height - 30 * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        // clip-path: M0 0H40V29H0z translated (.957, .5)
        context.clip(to: CGRect(x: 0.957, y: 0.5, width: 40, height: 29))
        context.setFillColor(UIColor(red: 0xaa / 255, green: 0xaa / 255, blue: 0xaa / 255, alpha: 1).cgColor)
        context.addPath(Self.first)
        context.fillPath()
        context.setFillColor(UIColor.white.cgColor)
        context.addPath(Self.second)
        context.fillPath()
    }
}

final class HayaseOnlineBar: UIView {
    private enum Kind: Equatable {
        case none
        case backOnline
        case offline
        case error
    }

    private static let barHeight: CGFloat = 24
    /// CSS `ease`
    private static let ease = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.25, y: 0.1),
                                                      controlPoint2: CGPoint(x: 0.25, y: 1))

    /// The shell pins its content under this view; the height follows the bar while it opens and closes.
    private(set) var heightConstraint: NSLayoutConstraint!
    private var barHeightConstraint: NSLayoutConstraint!

    private let bar = UIView()
    private let stack = UIStackView()
    private let cloudOff = UIImageView(image: UIImage.hayaseIcon("cloud-off"))
    private let anilistError = AnilistErrorIconView()
    private let label = UILabel()

    private var hideFirst = false
    private var kind = Kind.none
    private var visibleHeight: CGFloat = 0
    private var generation = 0
    private var animator: UIViewPropertyAnimator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true
        clipsToBounds = true
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.clipsToBounds = true   // overflow-clip
        addSubview(bar)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        cloudOff.image = cloudOff.image?.withRenderingMode(.alwaysTemplate)
        cloudOff.tintColor = UIColor.HayaseTheme.foreground
        cloudOff.contentMode = .scaleAspectFit
        cloudOff.translatesAutoresizingMaskIntoConstraints = false
        cloudOff.setContentCompressionResistancePriority(.required, for: .horizontal)
        anilistError.translatesAutoresizingMaskIntoConstraints = false
        anilistError.setContentCompressionResistancePriority(.required, for: .horizontal)

        label.textColor = UIColor.HayaseTheme.foreground
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: bar.leadingAnchor, constant: 16),   // px-4
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            cloudOff.widthAnchor.constraint(equalToConstant: 16),
            cloudOff.heightAnchor.constraint(equalToConstant: 16),
        ])
        barHeightConstraint = bar.heightAnchor.constraint(equalToConstant: 0)
        barHeightConstraint.isActive = true

        NotificationCenter.default.addObserver(self, selector: #selector(statusChanged),
                                               name: AniListConnectionStatus.didChange, object: nil)
        statusChanged()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setHeight(visibleHeight)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setHeight(visibleHeight)
    }

    /// `{#if $online && hideFirst} … {:else if !$online} … {:else if $error} …`
    @objc private func statusChanged() {
        let status = AniListConnectionStatus.shared
        let online = status.isOnline
        if !online && !hideFirst { hideFirst = true }

        let next: Kind
        if online && hideFirst {
            next = .backOnline
        } else if !online {
            next = .offline
        } else if status.errorMessage != nil {
            next = .error
        } else {
            next = .none
        }

        if next == .error {
            // text-nowrap: a line break in the message is a space
            // `$error.message || 'Unknown error'`
            let message = (status.errorMessage ?? "").isEmpty ? "Unknown error" : (status.errorMessage ?? "")
            label.text = "AniList: " + message.replacingOccurrences(of: "\n", with: " ")
        }
        guard next != kind else { return }
        kind = next
        present(next)
    }

    /// A new element every time the branch changes: its animation starts over, two seconds late.
    private func present(_ kind: Kind) {
        generation += 1
        let current = generation
        animator?.stopAnimation(true)
        animator = nil

        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        switch kind {
        case .none:
            setHeight(0)
            return
        case .backOnline:
            // bg-green-600 text-sm
            bar.backgroundColor = UIColor(red: 0x16 / 255, green: 0xa3 / 255, blue: 0x4a / 255, alpha: 1)
            label.font = .nunito(ofSize: 14)
            label.text = "Back online"
            stack.spacing = 0
            stack.addArrangedSubview(label)
            // no `from` before the animation starts: the bar is as tall as its text, 1.25rem
            setHeight(20)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.generation == current else { return }
                // `hide 300ms forwards 2s`: from 24px to nothing
                self.setHeight(Self.barHeight)
                self.superview?.layoutIfNeeded()
                self.animateHeight(to: 0, current: current)
            }
        case .offline:
            // bg-muted text-sm, CloudOff 16 me-2
            bar.backgroundColor = UIColor.HayaseTheme.muted
            label.font = .nunito(ofSize: 14)
            label.text = "Offline"
            stack.spacing = 8
            stack.addArrangedSubview(cloudOff)
            stack.addArrangedSubview(label)
            setHeight(0)
            scheduleShow(current: current)
        case .error:
            // bg-red-800 text-sm, AnilistError size-[1.1rem] me-1.5, leading-none
            bar.backgroundColor = UIColor(red: 0x99 / 255, green: 0x1b / 255, blue: 0x1b / 255, alpha: 1)
            label.font = .nunito(ofSize: 14)
            stack.spacing = 6
            stack.addArrangedSubview(anilistError)
            stack.addArrangedSubview(label)
            setHeight(0)
            scheduleShow(current: current)
        }
    }

    /// `show 300ms forwards 2s`: from nothing to 24px
    private func scheduleShow(current: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.generation == current else { return }
            self.animateHeight(to: Self.barHeight, current: current)
        }
    }

    private func setHeight(_ height: CGFloat) {
        visibleHeight = height
        barHeightConstraint.constant = height
        heightConstraint.constant = height == 0 ? 0 : height + safeTopInset
    }

    private var safeTopInset: CGFloat {
        window?.safeAreaInsets.top ?? 0
    }

    private func animateHeight(to height: CGFloat, current: Int) {
        let apply = { [weak self] in
            guard let self else { return }
            self.setHeight(height)
            self.superview?.layoutIfNeeded()
        }
        if UIAccessibility.isReduceMotionEnabled {
            apply()
            return
        }
        let animator = UIViewPropertyAnimator(duration: 0.3, timingParameters: Self.ease)
        animator.addAnimations(apply)
        self.animator = animator
        animator.startAnimation()
    }
}
