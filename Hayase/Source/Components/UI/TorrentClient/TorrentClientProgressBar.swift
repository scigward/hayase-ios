// files/cells/progress.svelte: a 6pt clipped secondary capsule and translated fill.
import UIKit

final class TorrentClientProgressBar: UIView {
    var progress: Float = 0 {
        didSet { if progress != oldValue { updateProgress(animated: animatesUpdates && window != nil) } }
    }
    var animatesUpdates = true
    private let fill = UIView()
    private var animator: UIViewPropertyAnimator?
    private let barHeight: CGFloat

    init(height: CGFloat = 6) {
        barHeight = height
        super.init(frame: .zero)
        layer.cornerRadius = height / 2
        clipsToBounds = true
        backgroundColor = UIColor.HayaseTheme.secondary
        fill.backgroundColor = UIColor.HayaseTheme.primary
        addSubview(fill)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: barHeight) }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard fill.bounds.size != bounds.size else { return }
        fill.bounds = bounds
        fill.center = CGPoint(x: bounds.midX, y: bounds.midY)
        updateProgress(animated: false)
    }

    private func updateProgress(animated: Bool) {
        if let animator {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .current)
            self.animator = nil
        }
        let transform = CGAffineTransform(translationX: (CGFloat(max(0, min(1, progress))) - 1) * bounds.width, y: 0)
        if animated {
            let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.4, y: 0),
                                                controlPoint2: CGPoint(x: 0.2, y: 1))
            let animator = UIViewPropertyAnimator(duration: 0.15, timingParameters: timing)
            animator.addAnimations { self.fill.transform = transform }
            animator.addCompletion { [weak self] _ in self?.animator = nil }
            self.animator = animator
            animator.startAnimation()
        } else { fill.transform = transform }
    }
}
