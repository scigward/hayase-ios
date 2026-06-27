//
//  Input.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

import UIKit

final class Input: UITextField {
    private let iconName: String?

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
        layer.masksToBounds = true
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
            leftView = iconContainer
            leftViewMode = .always
        } else {
            leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 36))
            leftViewMode = .always
        }
    }
}
