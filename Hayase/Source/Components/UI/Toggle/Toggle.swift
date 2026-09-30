//
//  Toggle.swift
//  Hayase
//
//  UIKit counterpart for the interface toggle component.
//

import UIKit

/// `<Toggle variant='outline' size='icon'>`, border-0: bg-background, and bg-accent while
/// selected or pressed (`data-[state=on]`).
final class Toggle: SelectButton {
    private let iconName: String
    private let iconPointSize: CGFloat

    var pressed = false {
        didSet { updateAppearance() }
    }

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
        applyOutlineVariant(background: UIColor.HayaseTheme.background)
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center
        setImage(UIImage.hayaseIcon(iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular)),
            for: .normal)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 36).isActive = true
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    private func updateAppearance() {
        restingBackground = pressed ? UIColor.HayaseTheme.accent : UIColor.HayaseTheme.background
        restingTint = pressed ? UIColor.HayaseTheme.accentForeground : UIColor.HayaseTheme.foreground
    }
}
