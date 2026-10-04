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
        // a label that is too narrow clipped its text with an ellipsis; the text of the page is simply shown
        stateLabel.lineBreakMode = .byClipping
        stateLabel.numberOfLines = 1
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

    /// `w-4`: the box of the text is 16 wide and "Off" is a little wider, which the page lets overflow
    private static let stateWidth: CGFloat = {
        let font = UIFont.nunito(ofSize: 12)
        let widest = ["On", "Off"].map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 16
        return max(16, ceil(widest))
    }()

    override var intrinsicContentSize: CGSize { CGSize(width: hidesState ? 32 : 40 + Self.stateWidth, height: 16) }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = CGRect(x: 0, y: (bounds.height - 16) / 2, width: 32, height: 16)
        thumb.frame = CGRect(x: isOn ? 18 : 2, y: 2, width: 12, height: 12)
        // the box of the text is 16 wide (`w-4`) and "Off" is wider than that: it overflows as it does in the page
        stateLabel.frame = CGRect(x: 40, y: (bounds.height - 16) / 2, width: max(Self.stateWidth, bounds.width - 40), height: 16)
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
