// Mirrors: src/lib/components/ui/switch/switch.svelte
import UIKit

final class HayaseSwitch: UIControl {
    private let track = UIView()
    private let thumb = UIView()
    private let stateLabel = UILabel()
    private let hidesState: Bool
    private(set) var isOn = false

    init(hideState: Bool = false) {
        hidesState = hideState
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        isAccessibilityElement = true
        stateLabel.font = .nunito(ofSize: 12)
        stateLabel.textColor = UIColor.HayaseTheme.foreground
        stateLabel.isHidden = hideState
        track.layer.cornerRadius = 8
        thumb.layer.cornerRadius = 6
        thumb.backgroundColor = UIColor.HayaseTheme.background
        SettingsTypography.applyButtonShadow(to: track, small: true)
        // Thumb `shadow-lg`: 0 10px 15px -3px rgb(0 0 0 / 0.1).
        thumb.layer.shadowColor = UIColor.black.cgColor
        thumb.layer.shadowOpacity = 0.1
        thumb.layer.shadowOffset = CGSize(width: 0, height: 10)
        thumb.layer.shadowRadius = 7.5
        [track, stateLabel].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
        track.addSubview(thumb)
        addTarget(self, action: #selector(toggle), for: .touchUpInside)
        setOn(false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: hidesState ? 32 : 56, height: 16) }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = CGRect(x: 0, y: (bounds.height - 16) / 2, width: 32, height: 16)
        thumb.frame = CGRect(x: isOn ? 18 : 2, y: 2, width: 12, height: 12)
        stateLabel.frame = CGRect(x: 40, y: (bounds.height - 16) / 2, width: 16, height: 16)
        thumb.layer.shadowPath = UIBezierPath(roundedRect: thumb.bounds.insetBy(dx: 3, dy: 3),
                                              cornerRadius: 3).cgPath
    }

    func setOn(_ value: Bool, animated: Bool) {
        isOn = value
        stateLabel.text = value ? "On" : "Off"
        accessibilityValue = stateLabel.text
        accessibilityTraits = value ? [.button, .selected] : .button
        let changes = {
            self.track.backgroundColor = value ? UIColor.HayaseTheme.primary : UIColor.HayaseTheme.input
            self.thumb.frame.origin.x = value ? 18 : 2
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIViewPropertyAnimator(duration: 0.15, controlPoint1: CGPoint(x: 0.4, y: 0),
                                   controlPoint2: CGPoint(x: 0.2, y: 1), animations: changes).startAnimation()
        } else { changes() }
    }

    override var isEnabled: Bool { didSet { track.alpha = isEnabled ? 1 : 0.5 } }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -14).contains(point)
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        toggle()
        return true
    }

    @objc private func toggle() {
        guard isEnabled else { return }
        setOn(!isOn, animated: true)
        sendActions(for: .valueChanged)
    }
}
