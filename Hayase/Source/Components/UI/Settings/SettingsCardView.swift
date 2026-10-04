// Mirrors: src/lib/components/SettingCard.svelte and ui/{label,input,button,slider}
import UIKit

protocol SettingsResponsiveView: AnyObject {
    func updateLayout(viewportWidth: CGFloat)
}

enum SettingsTypography {
    static func label(_ text: String, size: CGFloat, lineHeight: CGFloat,
                      weight: UIFont.Weight = .regular,
                      color: UIColor = UIColor.HayaseTheme.foreground) -> UILabel {
        let label = UILabel()
        label.font = .nunito(ofSize: size, weight: weight)
        label.textColor = color
        let paragraph = NSMutableParagraphStyle()
        // CSS permits glyphs to overflow a short line box; UILabel clips them.
        // Reserve the font's actual metrics for leading-none labels in UIKit.
        let safeLineHeight = max(lineHeight, ceil(label.font.lineHeight))
        paragraph.minimumLineHeight = safeLineHeight
        paragraph.maximumLineHeight = safeLineHeight
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.nunito(ofSize: size, weight: weight),
            .foregroundColor: color, .paragraphStyle: paragraph,
        ])
        label.numberOfLines = 0
        return label
    }

    static func button(_ title: String, destructive: Bool = false) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
        button.setTitleColor(destructive ? UIColor.HayaseTheme.destructiveForeground : UIColor.HayaseTheme.primaryForeground, for: .normal)
        button.backgroundColor = destructive ? UIColor.HayaseTheme.destructive : UIColor.HayaseTheme.primary
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.layer.cornerRadius = 6
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }
}

final class SettingsCardView: UIView, SettingsResponsiveView {
    private let stack = UIStackView()
    private let textStack: UIStackView
    private var horizontal: Bool?
    private var textWidth: NSLayoutConstraint?
    private var holderHeight: NSLayoutConstraint?
    /// The control the label is `for`: a tap on the text acts on it, as a click on a `<label for>` does.
    weak var labelTarget: UIView?

    /// `transparent` is `class='bg-transparent'` and `topAlignedControl` is `self-baseline` on the control, which
    /// when it is the only item to be aligned to a baseline sits at the top of the row instead of its middle.
    init(title: String, description: String, control: UIView, transparent: Bool = false,
         topAlignedControl: Bool = false) {
        // The label's `leading-[unset]` leaves the line to the page's `line-height: 1.5` (21pt of 14pt)
        let titleLabel = SettingsTypography.label(title, size: 14, lineHeight: 21, weight: .bold)
        let descriptionLabel = SettingsTypography.label(description, size: 12, lineHeight: 16,
                                                         weight: .medium, color: UIColor.HayaseTheme.mutedForeground)
        descriptionLabel.isHidden = description.isEmpty
        textStack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        super.init(frame: .zero)
        backgroundColor = transparent ? .clear : UIColor.HayaseTheme.muted
        layer.cornerRadius = 6
        textStack.axis = .vertical
        textStack.spacing = 0
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if control.contentHuggingPriority(for: .horizontal).rawValue < UILayoutPriority.defaultHigh.rawValue {
            control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        }
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(textStack)
        if topAlignedControl {
            let holder = UIView()
            control.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(control)
            let matchesText = holder.heightAnchor.constraint(equalTo: textStack.heightAnchor)
            matchesText.priority = .defaultHigh
            holderHeight = matchesText
            NSLayoutConstraint.activate([
                control.topAnchor.constraint(equalTo: holder.topAnchor),
                control.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                control.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                control.bottomAnchor.constraint(lessThanOrEqualTo: holder.bottomAnchor),
            ])
            stack.addArrangedSubview(holder)
        } else {
            stack.addArrangedSubview(control)
        }
        addSubview(stack)
        textStack.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(labelTapped)))
        textWidth = textStack.widthAnchor.constraint(equalTo: stack.widthAnchor)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            control.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])
        control.accessibilityLabel = title
        updateLayout(viewportWidth: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateLayout(viewportWidth: CGFloat) {
        let next = viewportWidth >= 768
        if horizontal != next {
            textWidth?.isActive = false
            horizontal = next
            stack.axis = next ? .horizontal : .vertical
            stack.alignment = next ? .center : .leading
            textWidth?.isActive = !next
            holderHeight?.isActive = next
        }
        stack.arrangedSubviews.compactMap { $0 as? SettingsResponsiveView }
            .forEach { $0.updateLayout(viewportWidth: viewportWidth) }
    }

    /// A click on the label goes to its control: a switch is toggled, an input is focused.
    @objc private func labelTapped() {
        if let toggle = labelTarget as? HayaseSwitch {
            toggle.sendActions(for: .touchUpInside)
        } else if let input = labelTarget as? SettingsInputControl {
            input.input.becomeFirstResponder()
        }
    }
}

final class SettingsInputControl: UIView {
    let input = Input(placeholder: "")
    var onChange: ((String) -> Void)?
    var onCommit: ((String) -> String)?

    init(value: String, placeholder: String, width: CGFloat, numeric: Bool = false,
         secure: Bool = false, suffix: String = "") {
        super.init(frame: .zero)
        input.text = value
        input.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: UIColor.HayaseTheme.mutedForeground,
        ])
        input.isSecureTextEntry = secure
        input.keyboardType = numeric ? .numbersAndPunctuation : .default
        input.returnKeyType = .done
        input.layer.borderWidth = 1
        input.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        addSubview(input)
        NSLayoutConstraint.activate([
            input.topAnchor.constraint(equalTo: topAnchor),
            input.leadingAnchor.constraint(equalTo: leadingAnchor),
            input.trailingAnchor.constraint(equalTo: trailingAnchor),
            input.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 36),
        ])
        let preferredWidth = widthAnchor.constraint(equalToConstant: width)
        preferredWidth.priority = .defaultHigh
        preferredWidth.isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        if !suffix.isEmpty {
            // `absolute right-3 … text-sm leading-5`: the text ends 12pt from the edge of the field
            let reserved: CGFloat = suffix == "Mb/s" ? 48 : 40
            let label = SettingsTypography.label(suffix, size: 14, lineHeight: 20)
            label.numberOfLines = 1
            label.textAlignment = .right
            label.frame = CGRect(x: 0, y: 0, width: reserved - 12, height: 36)
            let holder = UIView(frame: CGRect(x: 0, y: 0, width: reserved, height: 36))
            holder.addSubview(label)
            input.rightView = holder
            input.rightViewMode = .always
        }
        input.addTarget(self, action: #selector(changed), for: .editingChanged)
        input.addTarget(self, action: #selector(committed), for: .editingDidEnd)
        input.addTarget(self, action: #selector(done), for: .editingDidEndOnExit)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func changed() { onChange?(input.text ?? "") }
    @objc private func committed() { if let onCommit { input.text = onCommit(input.text ?? "") } }
    @objc private func done() { input.resignFirstResponder() }
}

final class SettingsActionsView: UIStackView, SettingsResponsiveView {
    init(onAction: @escaping (String) -> Void) {
        super.init(frame: .zero)
        spacing = 12
        distribution = .fillEqually
        for title in ["Import Settings From File", "Export Settings To File", "Reset EVERYTHING To Default"] {
            let button = SettingsTypography.button(title, destructive: title.hasPrefix("Reset"))
            button.addAction(UIAction { _ in onAction(title) }, for: .touchUpInside)
            addArrangedSubview(button)
        }
        axis = .vertical
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func updateLayout(viewportWidth: CGFloat) { axis = viewportWidth >= 768 ? .horizontal : .vertical }
}

final class SettingsSliderControl: UIControl, KeyboardEventListener {
    private let track = UIView()
    private let fill = UIView()
    private let thumb = UIView()
    private(set) var value: Double
    private let range: ClosedRange<Double>
    private let step: Double

    init(value: Double, min: Double, max: Double, step: Double) {
        self.value = value.isFinite ? Swift.min(Swift.max(value, min), max) : min
        range = min...max
        self.step = step
        super.init(frame: .zero)
        track.backgroundColor = UIColor.HayaseTheme.primary.withAlphaComponent(0.2)
        track.layer.cornerRadius = 3
        fill.backgroundColor = UIColor.HayaseTheme.primary
        fill.layer.cornerRadius = 3
        thumb.backgroundColor = UIColor.HayaseTheme.background
        thumb.layer.cornerRadius = 8
        thumb.layer.borderWidth = 1
        thumb.layer.borderColor = UIColor.HayaseTheme.primary.withAlphaComponent(0.5).cgColor
        [track, fill, thumb].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        heightAnchor.constraint(equalToConstant: 16).isActive = true
        let width = widthAnchor.constraint(equalToConstant: 240)
        width.priority = .defaultHigh
        width.isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
        track.frame = CGRect(x: 0, y: 5, width: bounds.width, height: 6)
        fill.frame = CGRect(x: 0, y: 5, width: bounds.width * fraction, height: 6)
        thumb.frame = CGRect(x: max(0, bounds.width - 16) * fraction, y: 0, width: 16, height: 16)
        accessibilityValue = String(format: "%.1f", value)
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { update(touch); return true }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { update(touch); return true }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { sendActions(for: .editingDidEnd) }
    override func cancelTracking(with event: UIEvent?) { sendActions(for: .editingDidEnd) }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: 0, dy: -14).contains(point)
    }
    /// The thumb of the slider (melt-ui) takes the four arrows: Right and Up add a step, Left and Down take one,
    /// and the key is only prevented, so it goes on to `navigate` as well
    func keyDown(_ event: KeyboardEvent) {
        switch event.key {
        case KeyboardEvent.Key.arrowLeft, KeyboardEvent.Key.arrowDown:
            accessibilityDecrement()
        case KeyboardEvent.Key.arrowRight, KeyboardEvent.Key.arrowUp:
            accessibilityIncrement()
        default:
            return
        }
        event.preventDefault()
    }
    override func accessibilityIncrement() { setValue(value + step); sendActions(for: .editingDidEnd) }
    override func accessibilityDecrement() { setValue(value - step); sendActions(for: .editingDidEnd) }
    private func update(_ touch: UITouch) {
        let fraction = Double(touch.location(in: self).x / max(1, bounds.width))
        setValue(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
    }
    private func setValue(_ proposed: Double) {
        value = min(max((proposed / step).rounded() * step, range.lowerBound), range.upperBound)
        setNeedsLayout()
        sendActions(for: .valueChanged)
    }
}
