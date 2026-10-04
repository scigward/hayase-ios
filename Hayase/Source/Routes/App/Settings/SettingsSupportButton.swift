// Mirrors: src/routes/app/settings/+layout.svelte and app.css (hearbeat).
import UIKit

final class SettingsSupportButton: UIButton {
    private static let heartColor = UIColor(red: 250 / 255, green: 104 / 255, blue: 182 / 255, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        var style = UIButton.Configuration.plain()
        // Button size="sm" uses rounded-md, never UIKit's adaptive capsule.
        style.cornerStyle = .fixed
        style.background.cornerRadius = 6
        style.background.backgroundColor = UIColor.HayaseTheme.primary
        var titleAttributes = AttributeContainer()
        titleAttributes.font = UIFont.nunito(ofSize: 12, weight: .bold)
        titleAttributes.foregroundColor = UIColor.HayaseTheme.primaryForeground
        style.attributedTitle = AttributedString("Donate", attributes: titleAttributes)
        style.image = UIImage.hayaseFilledIcon("heart", pointSize: 18)?
            .withTintColor(Self.heartColor, renderingMode: .alwaysOriginal)
        style.imagePadding = 8
        style.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        configuration = style
        backgroundColor = UIColor.HayaseTheme.primary
        layer.cornerRadius = 6
        clipsToBounds = true
        accessibilityLabel = "Donate"
        for notification in [UIApplication.didBecomeActiveNotification,
                             UIApplication.willResignActiveNotification,
                             UIAccessibility.reduceMotionStatusDidChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(activityChanged(_:)),
                                                   name: notification, object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateHeartbeat(active: UIApplication.shared.applicationState == .active)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView?.layer.shadowColor = Self.heartColor.cgColor
        imageView?.layer.shadowOpacity = 1
        imageView?.layer.shadowRadius = 16
        imageView?.layer.shadowOffset = .zero
        imageView?.clipsToBounds = false
        updateHeartbeat(active: UIApplication.shared.applicationState == .active)
    }

    @objc private func activityChanged(_ notification: Notification) {
        updateHeartbeat(active: notification.name != UIApplication.willResignActiveNotification
                        && UIApplication.shared.applicationState == .active)
    }

    private func updateHeartbeat(active: Bool) {
        guard let heart = imageView?.layer else { return }
        guard window != nil, active, !UIAccessibility.isReduceMotionEnabled else {
            heart.removeAnimation(forKey: "supportHeartbeat")
            return
        }
        guard heart.animation(forKey: "supportHeartbeat") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1
        pulse.toValue = 0.85
        pulse.duration = 1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1)
        heart.add(pulse, forKey: "supportHeartbeat")
    }
}
