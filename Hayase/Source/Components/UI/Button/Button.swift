//
//  Button.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

import UIKit

/// `<Button variant='outline' size='icon'>`, border-0: a 36pt square with an icon. Other
/// variants are set with `applyGhostVariant()` or the colour properties.
final class Button: SelectButton {
    private let iconName: String
    private let iconPointSize: CGFloat
    /// `size-9`: 36, or less where the button is a flex item that gives way
    private(set) var widthConstraint: NSLayoutConstraint!

    init(iconName: String, pointSize: CGFloat = 16) {
        self.iconName = iconName
        self.iconPointSize = pointSize
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setup() {
        applyOutlineVariant()
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center
        setImage(UIImage.hayaseIcon(iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular)),
            for: .normal)
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: 36)
        widthConstraint.isActive = true
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }
}
