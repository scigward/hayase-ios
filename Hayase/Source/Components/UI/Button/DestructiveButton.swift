//
//  DestructiveButton.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/button/index.ts, `variant='destructive'` with the shared base:
//  `bg-destructive text-destructive-foreground select:bg-destructive/90 shadow-sm` (hover, focus-visible or
//  active, with the 150ms of `transition-colors`), `rounded-md` and `disabled:opacity-50`. It is a `SelectButton`,
//  so the press scale of app.css and the D-pad's focus are the same as every other button.
//

import UIKit

final class DestructiveButton: SelectButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        applyDestructiveVariant()
        dimsWhenDisabled = true   // disabled:opacity-50
    }

    required init?(coder: NSCoder) {
        nil
    }
}
