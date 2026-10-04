//
//  Checkbox.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/checkbox/checkbox.svelte
//
//    border-primary data-[state=checked]:bg-primary data-[state=checked]:text-primary-foreground
//    peer box-content h-4 w-4 shrink-0 rounded-sm border shadow
//
//  The box is `box-content`, so the 16pt it is sized to sits inside a 1pt border: 18pt in all. The
//  indicator is 16pt, and its Check `h-3.5 w-3.5` (14pt) is `text-transparent` until checked.
//

import UIKit

final class Checkbox: UIControl, NoActiveScale {
    static let side: CGFloat = 18

    private let mark = UIImageView(image: RadixIcons.check(size: 14))
    private var isPressScaled = false
    private var pressAnimator: UIViewPropertyAnimator?

    private(set) var isChecked = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 4          // rounded-sm: calc(var(--radius) - 4px)
        layer.borderWidth = 1
        layer.borderColor = UIColor.HayaseTheme.primary.cgColor
        // shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 1.5

        mark.tintColor = UIColor.HayaseTheme.primaryForeground
        mark.contentMode = .center
        mark.isUserInteractionEnabled = false
        addSubview(mark)

        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(toggle), for: .touchUpInside)
        apply()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.side, height: Self.side)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The 14pt check is centred in the 16pt indicator, inside the 1pt border.
        mark.frame = CGRect(x: 2, y: 2, width: 14, height: 14)
    }

    func setChecked(_ checked: Bool) {
        isChecked = checked
        apply()
    }

    private func apply() {
        // data-[state=checked]:bg-primary; the mark is text-transparent until then
        backgroundColor = isChecked ? UIColor.HayaseTheme.primary : .clear
        mark.isHidden = !isChecked
        accessibilityValue = isChecked ? "checked" : "unchecked"
    }

    @objc private func toggle() {
        setChecked(!isChecked)
        sendActions(for: .valueChanged)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    override var isHighlighted: Bool {
        didSet { updatePressScale() }
    }

    /// app.css, for every button: `&:active:not([disabled]) { transition: all 0.1s ease-in-out; transform: scale(0.98) }`
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
}
