//
//  CardLoadIn.swift
//  Hayase
//
//  Mirrors: src/app.css `@keyframes load-in`, which small.svelte, episode.svelte and skeleton.svelte
//  run on their `.item` when they mount: `animation: 0.3s ease 0s 1 load-in`.
//

import UIKit

/// A card cell that plays the mount animation of its `.item`.
protocol InterfaceMountAnimating: UICollectionViewCell {
    /// Asks the collection view whether this cell is mounting, and plays the animation if so.
    func requestInterfaceMountAnimation()
    func playInterfaceLoadInAnimation(startedAt: CFTimeInterval)
}

enum CardLoadIn {
    static let animationKey = "interfaceLoadIn"
    static let duration: TimeInterval = 0.3
    /// 1.2rem at the 16px root size
    static let offsetY: CGFloat = 19.2
    static let scale: CGFloat = 0.95

    /// `translate3d(0, 1.2rem, 0) scale(0.95)` to none, with CSS `ease`.
    static func play(on view: UIView, startedAt: CFTimeInterval) {
        view.layer.removeAnimation(forKey: animationKey)
        view.transform = .identity

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DMakeAffineTransform(
            CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: offsetY))
        animation.toValue = CATransform3DIdentity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
        animation.beginTime = view.layer.convertTime(startedAt, from: nil)
        view.layer.add(animation, forKey: animationKey)
    }

    static func cancel(on view: UIView) {
        view.layer.removeAnimation(forKey: animationKey)
        view.transform = .identity
    }

    /// The collection view an `InterfaceMountAnimating` cell is in, if it is an `AnimeCardCollectionView`.
    static func enclosingCollectionView(of cell: UIView) -> AnimeCardCollectionView? {
        var candidate = cell.superview
        while let view = candidate {
            if let collectionView = view as? AnimeCardCollectionView { return collectionView }
            candidate = view.superview
        }
        return nil
    }
}
