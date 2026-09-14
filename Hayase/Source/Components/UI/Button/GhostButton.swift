//
//  GhostButton.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

// Mirrors: hayase-app/interface/src/lib/components/ui/button/index.ts
// (`ghost` variant + shared base). base: rounded-md text-sm font-medium
// disabled:opacity-50. ghost: bg-transparent, select:bg-secondary-foreground/20
// (the only ghost-specific state — iOS has no hover, so "select" maps to
// isHighlighted).

import UIKit

final class GhostButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 6   // rounded-md
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.cornerRadius = 6
        clipsToBounds = true
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? UIColor.HayaseTheme.secondaryForeground.withAlphaComponent(0.2) : .clear
        }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.5 }   // disabled:opacity-50
    }
}
