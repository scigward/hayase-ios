// Mirrors: src/routes/app/settings/+layout.svelte and app.css (hearbeat).
import UIKit

/// `<Button size='sm' class='font-bold gap-2 ...'>` of the default variant: `bg-primary text-primary-foreground
/// select:bg-primary/60 shadow` with the 150ms of `transition-colors`, `h-8 px-3 text-xs`, and the heart that beats.
final class SettingsSupportButton: SelectButton {
    private static let heartColor = UIColor(red: 250 / 255, green: 104 / 255, blue: 182 / 255, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyPrimaryVariant()
        titleLabel?.font = UIFont.nunito(ofSize: 12, weight: .bold)
        setTitle("Donate", for: .normal)
        setImage(UIImage.hayaseFilledIcon("heart", pointSize: 18)?
            .withTintColor(Self.heartColor, renderingMode: .alwaysOriginal), for: .normal)
        // gap-2: 8pt between the heart and the text
        imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        clipsToBounds = true   // contain-strict
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
