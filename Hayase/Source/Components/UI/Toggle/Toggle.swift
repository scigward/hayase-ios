//
//  Toggle.swift
//  Hayase
//
//  UIKit counterpart for the interface toggle component.
//

import UIKit

final class Toggle: UIButton {
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
        self.iconName = "circle-question-mark"
        self.iconPointSize = 16
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        layer.cornerRadius = 6
        layer.masksToBounds = true
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center
        setImage(UIImage.hayaseIcon(iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular)),
            for: .normal)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 36).isActive = true
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        updateAppearance()
    }

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    private func updateAppearance() {
        if pressed || isHighlighted {
            backgroundColor = UIColor.HayaseTheme.accent
            tintColor = UIColor.HayaseTheme.foreground
        } else {
            backgroundColor = UIColor.HayaseTheme.background
            tintColor = UIColor.HayaseTheme.mutedForeground
        }
    }
}
