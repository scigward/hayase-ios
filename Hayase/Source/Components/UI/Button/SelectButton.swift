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
    private var isSwappingIcon = false
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

    /// TransitionButton: the icon is swapped for another with `scaleBlurFade`, held, and
    /// swapped back. Each icon scales and blurs as it fades, over 300ms with cubicOut.
    func swapIcon(to image: UIImage?, hold: TimeInterval) {
        guard let imageView, let base = imageView.image, let image, !isSwappingIcon else { return }
        isSwappingIcon = true
        let tint = self.tintColor ?? UIColor.HayaseTheme.foreground
        let padding = Self.swapBlurRadius * 3
        let frame = imageView.frame.insetBy(dx: -padding, dy: -padding)

        func makeLayer(_ image: UIImage) -> (layer: CALayer, frames: [CGImage]) {
            let frames = Self.blurFrames(of: image, tint: tint, padding: padding)
            let layer = CALayer()
            layer.frame = frame
            layer.contents = frames.first
            layer.contentsScale = UIScreen.main.scale
            return (layer, frames)
        }
        let outgoing = makeLayer(base)
        let incoming = makeLayer(image)
        incoming.layer.opacity = 0
        self.layer.addSublayer(outgoing.layer)
        self.layer.addSublayer(incoming.layer)
        imageView.alpha = 0

        func scaleBlurFade(_ layer: CALayer, frames: [CGImage], entering: Bool) {
            let group = CAAnimationGroup()
            let timing = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)   // cubicOut
            let (from, to): (Float, Float) = entering ? (0, 1) : (1, 0)
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = from
            opacity.toValue = to
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = max(from, 0.001)
            scale.toValue = max(to, 0.001)
            let blur = CAKeyframeAnimation(keyPath: "contents")
            let ordered = entering ? Array(frames.reversed()) : frames
            blur.values = ordered
            blur.keyTimes = (0..<ordered.count).map { NSNumber(value: Double($0) / Double(ordered.count - 1)) }
            blur.calculationMode = .discrete
            group.animations = [opacity, scale, blur]
            group.duration = 0.3
            group.timingFunction = timing
            layer.add(group, forKey: "scaleBlurFade")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = to
            layer.transform = CATransform3DMakeScale(CGFloat(max(to, 0.001)), CGFloat(max(to, 0.001)), 1)
            layer.contents = entering ? frames.first : frames.last
            CATransaction.commit()
        }

        scaleBlurFade(outgoing.layer, frames: outgoing.frames, entering: false)
        scaleBlurFade(incoming.layer, frames: incoming.frames, entering: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            scaleBlurFade(incoming.layer, frames: incoming.frames, entering: false)
            scaleBlurFade(outgoing.layer, frames: outgoing.frames, entering: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                outgoing.layer.removeFromSuperlayer()
                incoming.layer.removeFromSuperlayer()
                imageView.alpha = 1
                self?.isSwappingIcon = false
            }
        }
    }

    /// blur(4px) at the start of the swap, in points.
    private static let swapBlurRadius: CGFloat = 4

    /// The icon in `tint` at each blur from none up to `swapBlurRadius`, on a canvas with room
    /// for the blur to spread.
    private static func blurFrames(of image: UIImage, tint: UIColor, padding: CGFloat) -> [CGImage] {
        let scale = UIScreen.main.scale
        let size = CGSize(width: image.size.width + 2 * padding, height: image.size.height + 2 * padding)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let tinted = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.withTintColor(tint, renderingMode: .alwaysOriginal)
                .draw(at: CGPoint(x: padding, y: padding))
        }
        guard let cgImage = tinted.cgImage else { return [] }
        let input = CIImage(cgImage: cgImage)
        let context = CIContext()
        let steps = 8
        return (0...steps).compactMap { step in
            guard step > 0 else { return cgImage }
            let output = input.applyingFilter("CIGaussianBlur",
                parameters: [kCIInputRadiusKey: swapBlurRadius * CGFloat(step) / CGFloat(steps) * scale])
            return context.createCGImage(output, from: input.extent)
        }
    }

}
