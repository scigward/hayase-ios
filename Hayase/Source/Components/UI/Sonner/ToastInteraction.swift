// Mirrors svelte-sonner@0.3.28 Toast.svelte's upward pointer swipe.
import UIKit

/// Shared by styled notifications and MessageToast; timer interaction belongs to the stack.
final class SonnerToastGesture: NSObject, UIGestureRecognizerDelegate {
    private weak var card: ToastCardView?
    private let canSwipe: () -> Bool
    private var threshold: CGFloat = 10
    private var amount: CGFloat = 0
    private var cancelledDirection = false

    init(card: ToastCardView, canSwipe: @escaping () -> Bool = { true }) {
        self.card = card
        self.canSwipe = canSwipe
        super.init()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panChanged(_:)))
        pan.delegate = self
        card.addGestureRecognizer(pan)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard canSwipe() else { return false }
        var target = touch.view
        while let view = target, view !== card {
            if view is UIButton { return false } // Toast.svelte does not swipe from an action button.
            target = view.superview
        }
        threshold = touch.type == .indirectPointer ? 2 : 10
        return true
    }

    @objc private func panChanged(_ gesture: UIPanGestureRecognizer) {
        guard let card else { return }
        let movement = gesture.translation(in: card.superview)
        switch gesture.state {
        case .began:
            amount = 0
            cancelledDirection = false
            update(movement, card: card)
        case .changed:
            update(movement, card: card)
        case .ended, .cancelled:
            if gesture.state == .ended, amount <= -20 {
                card.dismiss(swiped: true)
            } else {
                SonnerAnimation.animate(duration: 0.4, changes: { card.transform = .identity })
            }
        default: break
        }
    }

    private func update(_ movement: CGPoint, card: ToastCardView) {
        guard !cancelledDirection else { return }
        if min(0, movement.y) < -threshold {
            amount = movement.y
            card.transform = CGAffineTransform(translationX: 0, y: amount)
        } else if abs(movement.x) > threshold {
            cancelledDirection = true
        }
    }
}
