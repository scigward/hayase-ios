//
//  RouteScrollRestoration.swift
//  Hayase
//
//  Browser-style scroll restoration for route navigation.
//

import UIKit

// MARK: - RouteScrollRestoration

enum RouteScrollRestoration {
    static func capture(from viewController: UIViewController?) -> CGPoint? {
        guard let scrollView = scrollView(in: viewController),
              scrollView.bounds.width > 0,
              scrollView.bounds.height > 0 else { return nil }
        return scrollView.contentOffset
    }

    static func restore(_ offset: CGPoint?, in viewController: UIViewController?) {
        guard let offset else { return }
        DispatchQueue.main.async {
            apply(offset, to: scrollView(in: viewController))
            // Restore once more after UIKit has finished route layout/reload work.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                apply(offset, to: scrollView(in: viewController))
            }
        }
    }

    private static func scrollView(in viewController: UIViewController?) -> UIScrollView? {
        guard let viewController else { return nil }
        if let scrollView = viewController.view as? UIScrollView { return scrollView }
        return firstScrollableView(in: viewController.view)
    }

    private static func firstScrollableView(in view: UIView?) -> UIScrollView? {
        guard let view else { return nil }
        if let scrollView = view as? UIScrollView,
           !scrollView.isHidden,
           scrollView.alpha > 0.01,
           scrollView.bounds.width > 0,
           scrollView.bounds.height > 0 {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = firstScrollableView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    private static func apply(_ offset: CGPoint, to scrollView: UIScrollView?) {
        guard let scrollView, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }

        let inset = scrollView.adjustedContentInset
        let minX = -inset.left
        let minY = -inset.top
        let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        let clamped = CGPoint(
            x: min(max(offset.x, minX), maxX),
            y: min(max(offset.y, minY), maxY)
        )
        scrollView.setContentOffset(clamped, animated: false)
    }
}
