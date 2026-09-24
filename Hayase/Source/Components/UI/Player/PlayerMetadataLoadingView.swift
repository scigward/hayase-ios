// Mirrors: ui/player/wrapper.svelte's pending active-torrent state.
import UIKit

final class PlayerMetadataLoadingView: UIView {
    private let text = UILabel()
    private let ring = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.HayaseTheme.background
        let spinner = UIView()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.layer.addSublayer(ring)
        ring.path = UIBezierPath(arcCenter: CGPoint(x: 20, y: 20), radius: 18.5,
                                 startAngle: -.pi / 2, endAngle: 0, clockwise: true).cgPath
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor.HayaseTheme.primary.cgColor
        ring.lineWidth = 3
        ring.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 1
        spin.repeatCount = .infinity
        ring.add(spin, forKey: "spin")
        text.text = "Loading torrent metadata,\nthis might take a minute..."
        text.font = .nunito(ofSize: 16)
        text.textColor = UIColor.HayaseTheme.foreground
        text.numberOfLines = 0
        text.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [spinner, text])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            spinner.widthAnchor.constraint(equalToConstant: 40), spinner.heightAnchor.constraint(equalToConstant: 40),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showError(_ message: String) {
        ring.removeAllAnimations()
        ring.isHidden = true
        text.text = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
