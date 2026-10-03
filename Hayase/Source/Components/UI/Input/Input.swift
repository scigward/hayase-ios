//
//  Input.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

import UIKit

final class Input: UITextField {
    private let iconName: String?
    private var iconImageView: UIImageView?
    private var isPointerOver = false
    var showsFocusRing = true { didSet { updateRing() } }
    var idleBackgroundColor = UIColor.HayaseTheme.muted {
        didSet { updateSelectState() }
    }
    var searchIconSize: CGFloat = 14 {
        didSet { applyIcon() }
    }
    /// The interface's search inputs draw `svelte-radix` MagnifyingGlass, not lucide's search.
    var usesRadixMagnifier = false {
        didSet { applyIcon() }
    }

    private func applyIcon() {
        guard let iconName else { return }
        iconImageView?.image = usesRadixMagnifier
            ? RadixIcons.magnifyingGlass(size: searchIconSize)
            : UIImage.hayaseIcon(iconName, pointSize: searchIconSize)
        updateIconFrame()
    }
    var iconLeadingInset: CGFloat? { didSet { updateIconFrame() } }
    var highlightsIconOnFocus = true { didSet { updateSelectState() } }

    /// app.css: `input:active:not(.no-scale) { transition: all 0.1s ease-in-out; transform: scale(0.98) }`, and for
    /// a `no-scale` field `.scale-parent:has(.no-scale:active)`, which scales the box around it. The view to
    /// scale while the field is pressed: the field itself, or its box. A field with none is not scaled.
    var pressScaleTarget: UIView?
    private var pressAnimator: UIViewPropertyAnimator?
    private weak var pressedTarget: UIView?

    private func setPressed(_ pressed: Bool) {
        pressAnimator?.stopAnimation(true)
        pressAnimator = nil
        if pressed {
            guard isEnabled, let target = pressScaleTarget else { return }
            pressedTarget = target
            let animator = UIViewPropertyAnimator(duration: 0.1,
                                                  controlPoint1: CGPoint(x: 0.42, y: 0),
                                                  controlPoint2: CGPoint(x: 0.58, y: 1)) {
                target.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            }
            pressAnimator = animator
            animator.startAnimation()
        } else if let target = pressedTarget {
            pressedTarget = nil
            UIView.performWithoutAnimation { target.transform = .identity }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        setPressed(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        setPressed(false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        setPressed(false)
    }

    private func updateIconFrame() {
        guard let iconLeadingInset else { return }
        iconImageView?.contentMode = .scaleAspectFit
        iconImageView?.frame = CGRect(x: iconLeadingInset, y: (36 - searchIconSize) / 2,
                                     width: searchIconSize, height: searchIconSize)
    }

    init(placeholder: String = "Any", iconName: String? = nil) {
        self.iconName = iconName
        super.init(frame: .zero)
        setup(placeholder: placeholder)
    }

    required init?(coder: NSCoder) {
        self.iconName = nil
        super.init(coder: coder)
        setup(placeholder: "Any")
    }

    private func setup(placeholder: String) {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = idleBackgroundColor
        layer.cornerRadius = 6
        borderStyle = .none
        textColor = UIColor.HayaseTheme.foreground
        tintColor = UIColor.HayaseTheme.foreground
        font = .nunito(ofSize: 14, weight: .regular)
        returnKeyType = .search
        autocorrectionType = .no
        autocapitalizationType = .none
        attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5)])

        if let iconName {
            let iconContainer = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
            let iconImageView = UIImageView(image: UIImage.hayaseIcon(iconName)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)))
            iconImageView.tintColor = UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5)
            iconImageView.contentMode = .center
            iconImageView.frame = iconContainer.bounds
            iconContainer.addSubview(iconImageView)
            self.iconImageView = iconImageView
            leftView = iconContainer
            leftViewMode = .always
        } else {
            leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 36))
            leftViewMode = .always
        }

        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        addTarget(self, action: #selector(focusChanged), for: [.editingDidBegin, .editingDidEnd])
        updateRing()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateRing()
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isPointerOver = recognizer.state == .began || recognizer.state == .changed
        updateSelectState()
    }

    @objc private func focusChanged() {
        updateSelectState()
        updateRing()
    }

    /// `select:bg-accent` (hover, focus-visible, active) with `transition-colors`; the search
    /// icon also turns from muted to `group-focus-within:text-accent-foreground`.
    private func updateSelectState() {
        let selected = isFirstResponder || isPointerOver
        UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.backgroundColor = selected ? UIColor.HayaseTheme.accent : self.idleBackgroundColor
            self.iconImageView?.tintColor = self.isFirstResponder && self.highlightsIconOnFocus
                ? UIColor.HayaseTheme.accentForeground
                : UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5)
        }
    }

    /// `focus-visible:ring-1 ring-ring` draws a 1px ring outside the field; otherwise `shadow-sm`.
    private func updateRing() {
        if showsFocusRing && isFirstResponder {
            layer.shadowColor = UIColor.HayaseTheme.ring.cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = 0
            layer.shadowOffset = .zero
            layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: -1, dy: -1),
                                            cornerRadius: layer.cornerRadius + 1).cgPath
        } else {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.05
            layer.shadowRadius = 1
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowPath = nil
        }
    }
}
