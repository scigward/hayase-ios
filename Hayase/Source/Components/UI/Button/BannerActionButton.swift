//
//  BannerActionButton.swift
//  Hayase
//
//  Mirrors: interface full-banner.svelte PlayButton / FavoriteButton / BookmarkButton.
//

import UIKit

/// The banner's play, favourite and bookmark buttons. Each restyles while selected (hover,
/// focus-visible or active, so while touched or under an iPad pointer) with
/// `transition-colors` (150ms): the play button darkens to `bg-custom-600`, and the ghost icon
/// buttons gain a 20% background and turn `!text-custom`. The icon buttons also play their
/// animated icon each time they become selected.
final class BannerActionButton: UIButton {
    /// The animated icons of `icons/animated`, which run while the button is selected.
    enum IconAnimation {
        case heartBeat
        case bookmark

        /// heart.svelte `heartBeat`, 1.2s ease-in-out: three pulses to 110%.
        /// bookmark.svelte `primaryAnimation`, 0.5s ease-in-out: a small wobble.
        fileprivate func makeAnimation() -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: "transform")
            func pose(scale: CGFloat, degrees: CGFloat = 0) -> NSValue {
                let rotation = CATransform3DMakeRotation(degrees * .pi / 180, 0, 0, 1)
                return NSValue(caTransform3D: CATransform3DScale(rotation, scale, scale, 1))
            }
            switch self {
            case .heartBeat:
                animation.duration = 1.2
                animation.values = [pose(scale: 1), pose(scale: 1.1), pose(scale: 1), pose(scale: 1.1),
                                    pose(scale: 1), pose(scale: 1.1), pose(scale: 1)]
                animation.keyTimes = (0...6).map { NSNumber(value: Double($0) / 6) }
            case .bookmark:
                animation.duration = 0.5
                animation.values = [pose(scale: 1), pose(scale: 1.05, degrees: -7),
                                    pose(scale: 1.05, degrees: 7), pose(scale: 1)]
                animation.keyTimes = [0, 0.2, 0.4, 1].map { NSNumber(value: $0) }
            }
            animation.timingFunctions = (1..<animation.values!.count).map { _ in
                CAMediaTimingFunction(name: .easeInEaseOut)
            }
            return animation
        }
    }

    var restingBackground: UIColor = .clear {
        didSet { applyColors() }
    }
    var selectedBackground: UIColor = .clear {
        didSet { applyColors() }
    }
    var restingTint: UIColor = UIColor.HayaseTheme.foreground {
        didSet { applyColors() }
    }
    var selectedTint: UIColor = UIColor.HayaseTheme.foreground {
        didSet { applyColors() }
    }
    var iconAnimation: IconAnimation?

    private var isHovered = false
    private var appliedSelected = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        adjustsImageWhenHighlighted = false   // the selected colours are the only feedback
        layer.cornerRadius = 6                // rounded-md
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        applyColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isHighlighted: Bool {
        didSet { updateSelectState() }
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isHovered = recognizer.state == .began || recognizer.state == .changed
        updateSelectState()
    }

    private func updateSelectState() {
        let selected = isHighlighted || isHovered
        guard selected != appliedSelected else { return }
        appliedSelected = selected
        UIView.transition(with: self, duration: 0.15,
                          options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
                          animations: { self.applyColors() })
        if selected, let animation = iconAnimation?.makeAnimation() {
            imageView?.layer.add(animation, forKey: "select")
        }
    }

    private func applyColors() {
        backgroundColor = appliedSelected ? selectedBackground : restingBackground
        let tint = appliedSelected ? selectedTint : restingTint
        tintColor = tint
        setTitleColor(tint, for: .normal)
    }
}
