//
//  SelectableCardView.swift
//  Hayase
//

// Mirrors: interface EpisodesList.svelte and forums/Threads.svelte card classes
// (select:scale-[1.05] select:shadow-lg select:bg-accent, transition-[transform,box-shadow] duration-200 ease-out)

import UIKit

/// The interface's card `select:` state, shared by the anime page's episode and
/// thread cards. tailwind.config.ts defines `select` as hover, focus-visible or
/// active: a touch is active while it is down, and an iPad pointer is hover.
class SelectableCardView: UIView, UIGestureRecognizerDelegate {
    private let restingBackground: UIColor
    private let selectedBackground: UIColor
    private var isPressed = false
    private var isHovered = false
    private var appliedSelected = false

    /// z-position while not selected; a selected card draws above its neighbours.
    var restingZPosition: CGFloat = 0 {
        didSet {
            if !appliedSelected { layer.zPosition = restingZPosition }
        }
    }

    init(restingBackground: UIColor, selectedBackground: UIColor) {
        self.restingBackground = restingBackground
        self.selectedBackground = selectedBackground
        super.init(frame: .zero)
        backgroundColor = restingBackground
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0

        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressChanged(_:)))
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        press.delegate = self
        addGestureRecognizer(press)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Selected-state changes that the card's transition animates. Subclasses add
    /// their `group-select:` changes and call super.
    func applySelectState(_ selected: Bool) {
        transform = selected ? CGAffineTransform(scaleX: 1.05, y: 1.05) : .identity
        layer.shadowRadius = selected ? 18 : 0
        layer.shadowOpacity = selected ? 0.45 : 0
        layer.shadowOffset = selected ? CGSize(width: 0, height: 8) : .zero
    }

    /// Clears the selected state immediately, for cell reuse.
    func resetSelectState() {
        isPressed = false
        isHovered = false
        updateSelectState(animated: false, force: true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func pressChanged(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            isPressed = true
        case .ended, .cancelled, .failed:
            isPressed = false
        default:
            return
        }
        updateSelectState(animated: true)
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isHovered = recognizer.state == .began || recognizer.state == .changed
        updateSelectState(animated: true)
    }

    private func updateSelectState(animated: Bool, force: Bool = false) {
        let selected = isPressed || isHovered
        guard force || selected != appliedSelected else { return }
        appliedSelected = selected
        // bg-accent is outside the transition list, so it switches immediately.
        backgroundColor = selected ? selectedBackground : restingBackground
        layer.zPosition = selected ? 2 : restingZPosition
        guard animated else {
            applySelectState(selected)
            return
        }
        UIView.animate(withDuration: 0.2, delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.applySelectState(selected)
        }
    }
}

/// Lets a selected card's scale and shadow draw past its table cell, as the
/// interface's grids do.
protocol CardOverflowRendering: AnyObject {}

extension CardOverflowRendering where Self: UITableViewCell {
    func allowCardOverflowRendering() {
        [self, contentView].forEach { view in
            view.clipsToBounds = false
            view.layer.masksToBounds = false
        }

        // UITableView uses private wrapper views around visible cells. Those
        // wrappers can be recreated during reuse, so clear clipping on every
        // layout pass instead of relying on only the cell/contentView flags.
        var current = superview
        while let view = current {
            view.clipsToBounds = false
            view.layer.masksToBounds = false
            current = view.superview
        }
    }
}
