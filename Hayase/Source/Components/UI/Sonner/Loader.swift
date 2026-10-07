// Mirrors svelte-sonner@0.3.28 Loader.svelte and its Toaster.svelte CSS.
import UIKit

/// Loader.svelte + Toaster.svelte: 12 radial bars, not UIKit's platform spinner.
final class SonnerToastLoaderView: UIView {
    private let bars = (0..<12).map { _ in CALayer() }
    private var animating = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        bars.forEach {
            $0.backgroundColor = UIColor(white: 0.435, alpha: 1).cgColor // Sonner --gray11
            $0.cornerRadius = 6
            layer.addSublayer($0)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAnimation),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, bar) in bars.enumerated() {
            let angle = CGFloat(index) * .pi / 6
            let width = bounds.width * 0.24
            let height = bounds.height * 0.08
            let distance = width * 1.46
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            bar.position = CGPoint(x: bounds.midX + bounds.width * 0.02 + cos(angle) * distance,
                                   y: bounds.midY + bounds.height * 0.001 + sin(angle) * distance)
            bar.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        }
    }
    func setAnimating(_ value: Bool) {
        animating = value
        refreshAnimation()
    }
    override func didMoveToWindow() { super.didMoveToWindow(); refreshAnimation() }
    @objc private func refreshAnimation() {
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "sonner-spin")
            guard animating, window != nil, !UIAccessibility.isReduceMotionEnabled else { continue }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0.15
            fade.duration = 1.2
            fade.repeatCount = .infinity
            fade.timingFunction = CAMediaTimingFunction(name: .linear)
            // CSS animation-delay: -1.2s, -1.1s, … -0.1s means the later bars are earlier in their cycle.
            fade.beginTime = CACurrentMediaTime() + Double(index) * 0.1 - 1.2
            bar.add(fade, forKey: "sonner-spin")
        }
    }
}
