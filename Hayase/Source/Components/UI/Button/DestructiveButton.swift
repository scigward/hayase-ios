//
//  DestructiveButton.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

// Mirrors: hayase-app/interface/src/lib/components/ui/button/index.ts
// (`destructive` variant + shared base). base: rounded-md disabled:opacity-50.
// destructive: bg-destructive text-destructive-foreground shadow-sm,
// select:bg-destructive/90 (iOS: isHighlighted).

import UIKit

final class DestructiveButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.HayaseTheme.destructive
        tintColor = UIColor.HayaseTheme.destructiveForeground
        layer.cornerRadius = 6   // rounded-md
        layer.shadowColor = UIColor.black.cgColor   // shadow-sm
        layer.shadowOpacity = 0.05
        layer.shadowRadius = 1
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = UIColor.HayaseTheme.destructive.withAlphaComponent(isHighlighted ? 0.9 : 1)
        }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.5 }   // disabled:opacity-50
    }
}
