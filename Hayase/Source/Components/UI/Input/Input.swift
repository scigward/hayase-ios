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
        backgroundColor = UIColor.HayaseTheme.muted
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
            self.backgroundColor = selected ? UIColor.HayaseTheme.accent : UIColor.HayaseTheme.muted
            self.iconImageView?.tintColor = self.isFirstResponder
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
