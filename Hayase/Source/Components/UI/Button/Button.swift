//
//  Button.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

import UIKit

final class Button: UIButton {
    private let iconName: String
    private let iconPointSize: CGFloat

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
        backgroundColor = UIColor.HayaseTheme.muted
        layer.cornerRadius = 6
        layer.masksToBounds = true
        tintColor = UIColor.HayaseTheme.foreground
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center
        setImage(UIImage.hayaseIcon(iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular)),
            for: .normal)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 36).isActive = true
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted
                ? UIColor.HayaseTheme.accent
                : UIColor.HayaseTheme.muted
        }
    }
}
