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
///
/// While it is pressed it is `:active`, and app.css scales an `:active` element to 0.98 (`transition: all 0.1s
/// ease-in-out`), which wins over `select:scale-[1.05]`: so a card grows when the pointer or the D-pad is on it
/// and shrinks while it is pressed.
class SelectableCardView: UIView, UIGestureRecognizerDelegate, ActiveElementObserver, NoActiveScale {
    private let restingBackground: UIColor
    private let selectedBackground: UIColor
    private var isPressed = false
    private var isHovered = false
    private var appliedSelected = false
    private var appliedPressed = false
    /// The room around the card that the second shadow can reach (its blur of 3 and its offset of 4).
    private static let lowerShadowReach: CGFloat = 12
    /// `shadow-lg` is two shadows. The card's own layer has the first, `0 10px 15px -3px`; this has the second,
    /// `0 4px 6px -4px`. A box-shadow is not painted under its box, so this one is masked to what is outside the card.
    private let lowerShadowView = UIView()
    private let lowerShadowMask = CAShapeLayer()

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
        // `shadow-lg`: `0 10px 15px -3px rgb(0 0 0 / 0.1)` (a CSS blur of 15 is a radius of 7.5 here, and the -3 is a
        // path that is 3 smaller on every side), and `0 4px 6px -4px rgb(0 0 0 / 0.1)` in `lowerShadowView`.
        layer.shadowRadius = 7.5
        layer.shadowOffset = CGSize(width: 0, height: 10)

        lowerShadowView.isUserInteractionEnabled = false
        lowerShadowView.isHidden = true   // a mask is drawn off screen: only while the shadow is there
        lowerShadowView.layer.shadowColor = UIColor.black.cgColor
        lowerShadowView.layer.shadowOpacity = 0
        lowerShadowView.layer.shadowRadius = 3
        lowerShadowView.layer.shadowOffset = CGSize(width: 0, height: 4)
        lowerShadowMask.fillRule = .evenOdd
        lowerShadowView.layer.mask = lowerShadowMask
        insertSubview(lowerShadowView, at: 0)

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
        if appliedPressed {
            transform = CGAffineTransform(scaleX: ActiveScale.scale, y: ActiveScale.scale)
        } else {
            transform = selected ? CGAffineTransform(scaleX: 1.05, y: 1.05) : .identity
        }
        layer.shadowOpacity = selected ? 0.1 : 0
        lowerShadowView.layer.shadowOpacity = selected ? 0.1 : 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3),
                                        cornerRadius: max(0, layer.cornerRadius - 3)).cgPath

        let reach = Self.lowerShadowReach
        let radius = layer.cornerRadius
        lowerShadowView.frame = bounds.insetBy(dx: -reach, dy: -reach)
        let card = CGRect(origin: CGPoint(x: reach, y: reach), size: bounds.size)
        let outside = UIBezierPath(rect: lowerShadowView.bounds)
        outside.append(UIBezierPath(roundedRect: card, cornerRadius: radius))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lowerShadowView.layer.shadowPath = UIBezierPath(roundedRect: card.insetBy(dx: 4, dy: 4),
                                                        cornerRadius: max(0, radius - 4)).cgPath
        lowerShadowMask.frame = lowerShadowView.bounds
        lowerShadowMask.path = outside.cgPath
        CATransaction.commit()
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

    func activeElementDidChange() {
        updateSelectState(animated: true)
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isHovered = recognizer.state == .began || recognizer.state == .changed
        updateSelectState(animated: true)
    }

    private func updateSelectState(animated: Bool, force: Bool = false) {
        let selected = isPressed || isHovered || isActiveElement
        guard force || selected != appliedSelected || isPressed != appliedPressed else { return }
        appliedSelected = selected
        appliedPressed = isPressed
        // bg-accent is outside the transition list, so it switches immediately.
        backgroundColor = selected ? selectedBackground : restingBackground
        layer.zPosition = selected ? 2 : restingZPosition
        if selected { lowerShadowView.isHidden = false }
        guard animated else {
            applySelectState(selected)
            lowerShadowView.isHidden = !selected
            return
        }
        // `:active` brings `transition: all 0.1s ease-in-out` with it; out of it the card's own 200ms ease-out
        UIView.animate(withDuration: isPressed ? 0.1 : 0.2, delay: 0,
                       options: [isPressed ? .curveEaseInOut : .curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
                       animations: {
            self.applySelectState(selected)
        }, completion: { _ in
            if !self.appliedSelected { self.lowerShadowView.isHidden = true }
        })
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
