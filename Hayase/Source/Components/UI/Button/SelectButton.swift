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
class SelectButton: UIButton, ActiveElementObserver, NoActiveScale {
    /// The animated icons of `icons/animated`, which run while the button is selected.
    enum IconAnimation {
        case heartBeat
        /// bookmark.svelte and fileimage.svelte share this one (`primaryAnimation`).
        case wobble
        case boltSpin

        /// heart.svelte `heartBeat`: 1.2s ease-in-out, three pulses to 110%.
        /// `primaryAnimation`: 0.5s ease-in-out, a small wobble.
        /// bolt.svelte `screw-rotate`: a half turn in 1s, ease, three times.
        func makeAnimation() -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: "transform")
            func pose(scale: CGFloat = 1, degrees: CGFloat = 0) -> NSValue {
                let rotation = CATransform3DMakeRotation(degrees * .pi / 180, 0, 0, 1)
                return NSValue(caTransform3D: CATransform3DScale(rotation, scale, scale, 1))
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
            case .boltSpin:
                animation.duration = 1
                animation.repeatCount = 3
                animation.values = [pose(), pose(degrees: 180)]
                animation.keyTimes = [0, 1]
                animation.timingFunctions = [CAMediaTimingFunction(name: .default)]   // CSS `ease`
                return animation
            }
            let segments = max(0, (animation.values?.count ?? 0) - 1)
            animation.timingFunctions = (0..<segments).map { _ in
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
    /// `disabled:opacity-50`, which every variant of the interface's Button has. Off unless asked
    /// for, since other screens dim their own disabled buttons.
    var dimsWhenDisabled = false {
        didSet { updateDisabledAlpha() }
    }
    /// A disabled button that also has `!pointer-events-auto`, whose `select:` colours still follow the pointer.
    var selectsWhenDisabled = false
    /// chevronleft/chevronright.svelte: the icon slides sideways by this much while selected,
    /// `transition: transform 0.2s ease-in`.
    var selectedIconShift: CGFloat = 0

    private var isPointerOver = false
    private var appliedSelected = false
    var isSwappingIcon = false

    override var isEnabled: Bool {
        didSet { updateDisabledAlpha() }
    }

    private func updateDisabledAlpha() {
        guard dimsWhenDisabled else { return }
        alpha = isEnabled ? 1 : 0.5
    }
    private var layeredIcon: LayeredIconView?

    /// Uses an icon whose parts animate separately (clapperboard, pencil, trash) instead of an image.
    func setLayeredIcon(_ kind: LayeredIconView.Kind, size: CGFloat = 16) {
        layeredIcon?.removeFromSuperview()
        let icon = LayeredIconView(kind: kind)
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: size),
            icon.heightAnchor.constraint(equalToConstant: size),
        ])
        layeredIcon = icon
        icon.tint = appliedSelected ? selectedTint : restingTint
    }

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

    /// `variant='default'`: bg-primary text-primary-foreground select:bg-primary/60 shadow.
    func applyPrimaryVariant() {
        restingBackground = UIColor.HayaseTheme.primary
        selectedBackground = UIColor.HayaseTheme.primary.withAlphaComponent(0.6)
        restingTint = UIColor.HayaseTheme.primaryForeground
        selectedTint = UIColor.HayaseTheme.primaryForeground
        // shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 1.5
    }

    /// `variant='destructive'`: bg-destructive text-destructive-foreground select:bg-destructive/90 shadow-sm.
    func applyDestructiveVariant() {
        restingBackground = UIColor.HayaseTheme.destructive
        selectedBackground = UIColor.HayaseTheme.destructive.withAlphaComponent(0.9)
        restingTint = UIColor.HayaseTheme.destructiveForeground
        selectedTint = UIColor.HayaseTheme.destructiveForeground
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
        didSet {
            updateSelectState()
            updatePressScale()
        }
    }

    private var isPressScaled = false
    private var pressAnimator: UIViewPropertyAnimator?

    /// app.css, for every button: `&:active:not([disabled]) { transition: all 0.1s ease-in-out; transform: scale(0.98) }`.
    /// A button only has `transition-colors`, so out of `:active` it is back at once.
    private func updatePressScale() {
        let pressed = isEnabled && isHighlighted
        guard pressed != isPressScaled else { return }
        isPressScaled = pressed
        pressAnimator?.stopAnimation(true)
        pressAnimator = nil
        if pressed {
            let animator = UIViewPropertyAnimator(duration: 0.1,
                                                  controlPoint1: CGPoint(x: 0.42, y: 0),
                                                  controlPoint2: CGPoint(x: 0.58, y: 1)) {
                self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            }
            pressAnimator = animator
            animator.startAnimation()
        } else {
            UIView.performWithoutAnimation { self.transform = .identity }
        }
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isPointerOver = recognizer.state == .began || recognizer.state == .changed
        updateSelectState()
    }

    func activeElementDidChange() {
        updateSelectState()
    }

    private func updateSelectState() {
        // disabled:pointer-events-none
        let selected = (isEnabled || selectsWhenDisabled) && (isHighlighted || isPointerOver || isActiveElement)
        guard selected != appliedSelected else { return }
        appliedSelected = selected
        UIView.transition(with: self, duration: 0.15,
                          options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
                          animations: { self.applyColors() })
        if selected, let imageView, let animation = iconAnimation?.makeAnimation() {
            imageView.layer.add(animation, forKey: "select")
        }
        layeredIcon?.selectionChanged(selected)
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
        layeredIcon?.tint = tint
    }

}
