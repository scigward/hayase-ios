// Mirrors Dialog.Overlay fade (150ms) and Dialog.Content flyAndScale (200ms, cubicOut).
import UIKit

extension PlayerOptionsController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        PlayerOptionsAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        PlayerOptionsAnimator(presenting: false)
    }

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        PlayerOptionsPresentationController(presentedViewController: presented, presenting: presenting)
    }
}

private final class PlayerOptionsPresentationController: UIPresentationController {
    override var shouldRemovePresentersView: Bool { false }
    override var frameOfPresentedViewInContainerView: CGRect { containerView?.bounds ?? .zero }
    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        presentedView?.frame = frameOfPresentedViewInContainerView
    }
}

private final class PlayerOptionsAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let presenting: Bool
    init(presenting: Bool) { self.presenting = presenting }
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.2 }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let controller = context.viewController(forKey: presenting ? .to : .from) as? PlayerOptionsController else {
            context.completeTransition(false)
            return
        }
        if presenting {
            controller.view.frame = context.finalFrame(for: controller)
            context.containerView.addSubview(controller.view)
            controller.view.layoutIfNeeded()
            controller.setTransitionProgress(false)
            controller.setBackdropVisible(false)
        }
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 1.0 / 3.0, y: 1),
                                            controlPoint2: CGPoint(x: 2.0 / 3.0, y: 1))
        let animator = UIViewPropertyAnimator(duration: 0.2, timingParameters: timing)
        animator.addAnimations { controller.setTransitionProgress(self.presenting) }
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveLinear, .beginFromCurrentState]) {
            controller.setBackdropVisible(self.presenting)
        }
        animator.addCompletion { _ in
            let completed = !context.transitionWasCancelled
            if !completed {
                controller.setTransitionProgress(!self.presenting)
                controller.setBackdropVisible(!self.presenting)
            }
            context.completeTransition(completed)
        }
        animator.startAnimation()
    }
}
