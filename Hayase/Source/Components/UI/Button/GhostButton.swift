//
//  GhostButton.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/button/index.ts, `variant='ghost'` with the shared base: transparent,
//  `select:bg-secondary-foreground/20 select:text-accent-foreground` (hover, focus-visible or active, with the
//  150ms of `transition-colors`), `rounded-md` and `disabled:opacity-50`. It is a `SelectButton`, so the press
//  scale of app.css and the D-pad's focus are the same as every other button.
//

import UIKit

final class GhostButton: SelectButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        applyGhostVariant()
        dimsWhenDisabled = true   // disabled:opacity-50
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        nil
    }
}
