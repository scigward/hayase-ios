//
//  SelectButton.swift
//  Hayase
//
//  Mirrors: interface components/ui/button (the `select:` variants) and icons/animated.
//

import UIKit

/// A button that restyles while selected: hover, focus-visible or active, so while touched or
/// under an iPad pointer. Colours change with `transition-colors` (150ms). Icon buttons can
/// also play their animated icon (`animated-icon`) each time they become selected.
class SelectButton: UIButton {
    /// The animated icons of `icons/animated`, which run while the button is selected.
    enum IconAnimation {
        case heartBeat
        /// bookmark.svelte and fileimage.svelte share this one (`primaryAnimation`).
        case wobble
        case clapperboard
        case penWiggle
        case boltSpin

        /// heart.svelte `heartBeat`: 1.2s ease-in-out, three pulses to 110%.
        /// `primaryAnimation`: 0.5s ease-in-out, a small wobble.
        /// clapperboard.svelte: the icon swings about its lower left corner, 0.4s ease-in-out.
        /// pencilline.svelte `penWiggle`: 0.5s ease-in-out, twice.
        /// bolt.svelte `screw-rotate`: a half turn in 1s, ease, three times.
        func makeAnimation(iconSize: CGSize) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: "transform")
            func pose(scale: CGFloat = 1, degrees: CGFloat = 0, about: CGPoint = .zero,
                      shift: CGPoint = .zero) -> NSValue {
                var transform = CATransform3DMakeTranslation(shift.x + about.x, shift.y + about.y, 0)
                transform = CATransform3DRotate(transform, degrees * .pi / 180, 0, 0, 1)
                transform = CATransform3DScale(transform, scale, scale, 1)
                transform = CATransform3DTranslate(transform, -about.x, -about.y, 0)
                return NSValue(caTransform3D: transform)
            }
            switch self {
            case .heartBeat:
                animation.duration = 1.2
                animation.values = [pose(), pose(scale: 1.1), pose(), pose(scale: 1.1),
                                    pose(), pose(scale: 1.1), pose()]
                animation.keyTimes = (0...6).map { NSNumber(value: Double($0) / 6) }
            case .wobble:
                animation.duration = 0.5
                animation.values = [pose(), pose(scale: 1.05, degrees: -7),
                                    pose(scale: 1.05, degrees: 7), pose()]
                animation.keyTimes = [0, 0.2, 0.4, 1].map { NSNumber(value: $0) }
            case .clapperboard:
                // transform-origin 4px 20px of the 24px icon, relative to the layer's centre.
                let corner = CGPoint(x: (4.0 / 24 - 0.5) * iconSize.width, y: (20.0 / 24 - 0.5) * iconSize.height)
                animation.duration = 0.4
                animation.values = [pose(degrees: 0, about: corner), pose(degrees: -10, about: corner),
                                    pose(degrees: 16, about: corner), pose(degrees: 0, about: corner)]
                animation.keyTimes = [0, 0.3, 0.6, 1].map { NSNumber(value: $0) }
            case .penWiggle:
                // Two wiggles of 0.5s; offsets are in the 24px icon's units.
                let unit = iconSize.width / 24
                animation.duration = 1
                animation.values = [pose(),
                                    pose(degrees: -0.5, shift: CGPoint(x: -unit, y: 1.5 * unit)),
                                    pose(),
                                    pose(degrees: 0.5, shift: CGPoint(x: 1.5 * unit, y: -unit)),
                                    pose(),
                                    pose(degrees: -0.5, shift: CGPoint(x: -unit, y: 1.5 * unit)),
                                    pose(),
                                    pose(degrees: 0.5, shift: CGPoint(x: 1.5 * unit, y: -unit)),
                                    pose()]
                animation.keyTimes = (0...8).map { NSNumber(value: Double($0) / 8) }
            case .boltSpin:
                animation.duration = 1
                animation.repeatCount = 3
                animation.values = [pose(), pose(degrees: 180)]
                animation.keyTimes = [0, 1]
                animation.timingFunctions = [CAMediaTimingFunction(name: .default)]   // CSS `ease`
                return animation
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
    /// chevronleft/chevronright.svelte: the icon slides sideways by this much while selected,
    /// `transition: transform 0.2s ease-in`.
    var selectedIconShift: CGFloat = 0

    private var isPointerOver = false
    private var appliedSelected = false
    private var iconSwapOverlay: UIImageView?

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

    /// `variant='secondary'`: bg-secondary text-secondary-foreground select:bg-secondary/60
    /// shadow-sm. `selectedTint` is `select:!text-custom` where the button sets one.
    func applySecondaryVariant(selectedTint custom: UIColor? = nil) {
        restingBackground = UIColor.HayaseTheme.secondary
        selectedBackground = UIColor.HayaseTheme.secondary.withAlphaComponent(0.6)
        restingTint = UIColor.HayaseTheme.secondaryForeground
        selectedTint = custom ?? UIColor.HayaseTheme.secondaryForeground
        applyShadowSm()
    }

    /// `variant='outline'` (with `border-0`): bg-muted select:bg-accent select:text-accent-foreground
    /// shadow-sm. The search Toggle uses bg-background instead.
    func applyOutlineVariant(background: UIColor = UIColor.HayaseTheme.muted) {
        restingBackground = background
        selectedBackground = UIColor.HayaseTheme.accent
        restingTint = UIColor.HayaseTheme.foreground
        selectedTint = UIColor.HayaseTheme.accentForeground
        applyShadowSm()
    }

    /// `variant='ghost'`: transparent, select:bg-secondary-foreground/20 select:text-accent-foreground.
    func applyGhostVariant() {
        restingBackground = .clear
        selectedBackground = UIColor.HayaseTheme.secondaryForeground.withAlphaComponent(0.2)
        restingTint = UIColor.HayaseTheme.foreground
        selectedTint = UIColor.HayaseTheme.accentForeground
    }

    /// Sets the icon's colour whatever the state, for icons that carry their own colour class.
    var contentTint: UIColor {
        get { restingTint }
        set {
            restingTint = newValue
            selectedTint = newValue
        }
    }

    /// shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05)
    func applyShadowSm() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 1
    }

    override var isHighlighted: Bool {
        didSet { updateSelectState() }
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isPointerOver = recognizer.state == .began || recognizer.state == .changed
        updateSelectState()
    }

    private func updateSelectState() {
        // disabled:pointer-events-none
        let selected = isEnabled && (isHighlighted || isPointerOver)
        guard selected != appliedSelected else { return }
        appliedSelected = selected
        UIView.transition(with: self, duration: 0.15,
                          options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
                          animations: { self.applyColors() })
        if selected, let imageView, let animation = iconAnimation?.makeAnimation(iconSize: imageView.bounds.size) {
            imageView.layer.add(animation, forKey: "select")
        }
        if selectedIconShift != 0 {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn, .allowUserInteraction, .beginFromCurrentState]) {
                self.imageView?.transform = selected ? CGAffineTransform(translationX: self.selectedIconShift, y: 0) : .identity
            }
        }
    }

    private func applyColors() {
        backgroundColor = appliedSelected ? selectedBackground : restingBackground
        let tint = appliedSelected ? selectedTint : restingTint
        tintColor = tint
        setTitleColor(tint, for: .normal)
    }

    /// TransitionButton: the icon is swapped for another with `scaleBlurFade`, held, and
    /// swapped back. The blur of that transition is left out; scale and fade are kept.
    func swapIcon(to image: UIImage?, hold: TimeInterval) {
        guard let imageView, iconSwapOverlay == nil else { return }
        let overlay = UIImageView(image: image?.withRenderingMode(.alwaysTemplate))
        overlay.tintColor = tintColor
        overlay.frame = imageView.frame
        overlay.alpha = 0
        overlay.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        addSubview(overlay)
        iconSwapOverlay = overlay
        // scaleBlurFade: 300ms, cubicOut.
        func crossfade(showing overlayVisible: Bool, then completion: (() -> Void)?) {
            UIViewPropertyAnimator(duration: 0.3,
                                   controlPoint1: CGPoint(x: 0.33, y: 1),
                                   controlPoint2: CGPoint(x: 0.68, y: 1)) {
                imageView.alpha = overlayVisible ? 0 : 1
                imageView.transform = overlayVisible ? CGAffineTransform(scaleX: 0.01, y: 0.01) : .identity
                overlay.alpha = overlayVisible ? 1 : 0
                overlay.transform = overlayVisible ? .identity : CGAffineTransform(scaleX: 0.01, y: 0.01)
            }.startAnimation()
            if let completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: completion)
            }
        }
        crossfade(showing: true) { [weak self] in
            crossfade(showing: false, then: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                overlay.removeFromSuperview()
                self?.iconSwapOverlay = nil
            }
        }
    }
}
