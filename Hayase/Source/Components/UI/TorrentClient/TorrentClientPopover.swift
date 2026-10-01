// Mirrors the interface dropdown-menu and tooltip primitives used by tables.
import UIKit

final class TorrentClientSortPopover: UIView {
    var onDismiss: (() -> Void)?
    private weak var sourceView: UIView?
    private let outside = UIControl()
    private let content = UIView()
    private var animator: UIViewPropertyAnimator?
    private let onSort: (Bool) -> Void
    private var keyboardRow: Int?

    init(sourceView: UIView, onSort: @escaping (Bool) -> Void) {
        self.sourceView = sourceView
        self.onSort = onSort
        super.init(frame: .zero)
        outside.addTarget(self, action: #selector(close), for: .touchDown)
        addSubview(outside)
        content.backgroundColor = UIColor.HayaseTheme.popover
        content.layer.cornerRadius = 6
        content.layer.borderWidth = 1
        content.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        content.layer.shadowColor = UIColor.black.cgColor
        content.layer.shadowOpacity = 0.1
        content.layer.shadowRadius = 3
        content.layer.shadowOffset = CGSize(width: 0, height: 4)
        addSubview(content)
        for (index, title) in ["Asc", "Desc"].enumerated() {
            let button = TorrentClientSortItemButton()
            button.setTitle(title, for: .normal)
            button.setImage(index == 0 ? TorrentClientRadixIcons.arrowUp : TorrentClientRadixIcons.arrowDown, for: .normal)
            button.tag = index
            button.addTarget(self, action: #selector(selected(_:)), for: .touchUpInside)
            content.addSubview(button)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window = sourceView?.window else { return }
        frame = window.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(self)
        layoutIfNeeded()
        becomeFirstResponder()
        UIAccessibility.post(notification: .layoutChanged, argument: content.subviews.first)
        content.alpha = 0
        content.transform = CGAffineTransform(translationX: 0, y: -8).scaledBy(x: 0.95, y: 0.95)
        animate(shown: true)
    }

    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(close)),
         UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(moveFocus(_:))),
         UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(moveFocus(_:))),
         UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(chooseFocusedRow))]
    }
    @objc private func moveFocus(_ command: UIKeyCommand) {
        let next: Int
        if let keyboardRow { next = (keyboardRow + (command.input == UIKeyCommand.inputDownArrow ? 1 : -1) + 2) % 2 }
        else { next = command.input == UIKeyCommand.inputDownArrow ? 0 : 1 }
        keyboardRow = next
        for (index, view) in content.subviews.enumerated() { (view as? UIButton)?.isHighlighted = index == next }
    }
    @objc private func chooseFocusedRow() {
        guard isUserInteractionEnabled else { return }
        onSort((keyboardRow ?? 0) == 0)
        close()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        outside.frame = bounds
        guard let sourceView else { return }
        let anchor = sourceView.convert(sourceView.bounds, to: self)
        let safe = bounds.inset(by: safeAreaInsets)
        let width = min(max(128, anchor.width), max(1, safe.width - 8))
        let height: CGFloat = 74 // p-1 + border = 5 each side; 2 * (leading-5 + py-1.5)
        let x = max(safe.minX + 4, min(anchor.minX, safe.maxX - width - 4))
        let y = anchor.maxY + 4 + height <= safe.maxY
            ? anchor.maxY + 4 : max(safe.minY, anchor.minY - 4 - height)
        content.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        content.center = CGPoint(x: x + width / 2, y: y + height / 2)
        for (index, row) in content.subviews.enumerated() {
            row.frame = CGRect(x: 5, y: 5 + CGFloat(index) * 32, width: width - 10, height: 32)
        }
    }

    private func animate(shown: Bool) {
        animator?.stopAnimation(true)
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 1 / 3, y: 1),
                                            controlPoint2: CGPoint(x: 2 / 3, y: 1))
        let animator = UIViewPropertyAnimator(duration: 0.15, timingParameters: timing)
        animator.addAnimations {
            self.content.alpha = shown ? 1 : 0
            self.content.transform = shown ? .identity
                : CGAffineTransform(translationX: 0, y: -8).scaledBy(x: 0.95, y: 0.95)
        }
        animator.addCompletion { [weak self] _ in
            self?.animator = nil
            if !shown {
                self?.removeFromSuperview()
                self?.onDismiss?()
            }
        }
        self.animator = animator
        animator.startAnimation()
    }

    @objc private func selected(_ sender: UIButton) {
        guard isUserInteractionEnabled else { return }
        onSort(sender.tag == 0)
        close()
    }
    @objc func close() {
        guard isUserInteractionEnabled else { return }
        resignFirstResponder()
        isUserInteractionEnabled = false
        animate(shown: false)
    }
}

private final class TorrentClientSortItemButton: UIButton {
    private var hovered = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 4
        contentHorizontalAlignment = .left
        contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        titleLabel?.font = .nunito(ofSize: 14)
        setTitleColor(UIColor.HayaseTheme.foreground, for: .normal)
        tintColor = UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.7)
        adjustsImageWhenHighlighted = false
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    // Explicit frames preserve the Radix glyph's 14px size and mr-2 spacing;
    // UIButton imageEdgeInsets would shrink the glyph when reserving that gap.
    override func imageRect(forContentRect rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.midY - 7, width: 14, height: 14)
    }
    override func titleRect(forContentRect rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + 22, y: rect.midY - 10, width: max(0, rect.width - 22), height: 20)
    }
    override var isHighlighted: Bool { didSet { updateAppearance() } }
    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        hovered = gesture.state == .began || gesture.state == .changed
        updateAppearance()
    }
    private func updateAppearance() {
        let selected = hovered || isHighlighted
        backgroundColor = selected ? UIColor.HayaseTheme.accent : .clear
        setTitleColor(selected ? UIColor.HayaseTheme.accentForeground : UIColor.HayaseTheme.foreground, for: .normal)
    }
}

final class TorrentClientDateTooltip: UIView {
    private weak var sourceView: UIView?
    private let label = UILabel()
    init(text: String, sourceView: UIView) {
        self.sourceView = sourceView
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = UIColor.HayaseTheme.primary
        layer.cornerRadius = 6
        clipsToBounds = true
        label.font = .nunito(ofSize: 12)
        label.textColor = UIColor.HayaseTheme.primaryForeground
        label.numberOfLines = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 16
        paragraph.maximumLineHeight = 16
        paragraph.lineBreakMode = .byWordWrapping
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: label.font as Any,
            .foregroundColor: UIColor.HayaseTheme.primaryForeground,
            .paragraphStyle: paragraph,
            .baselineOffset: (16 - label.font.lineHeight) / 2,
        ])
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window = sourceView?.window else { return }
        let safe = window.bounds.inset(by: window.safeAreaInsets)
        let labelSize = label.sizeThatFits(CGSize(width: max(1, safe.width - 32), height: CGFloat.greatestFiniteMagnitude))
        let size = CGSize(width: labelSize.width + 24, height: labelSize.height + 12)
        let anchor = sourceView?.convert(sourceView?.bounds ?? .zero, to: window) ?? .zero
        let x = max(safe.minX + 4, min(anchor.midX - size.width / 2, safe.maxX - size.width - 4))
        let y = anchor.minY - size.height - 4 >= safe.minY
            ? anchor.minY - size.height - 4 : anchor.maxY + 4
        frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        label.frame = bounds.insetBy(dx: 12, dy: 6)
        window.addSubview(self)
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.95, y: 0.95)
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 1 / 3, y: 1),
                                            controlPoint2: CGPoint(x: 2 / 3, y: 1))
        let animator = UIViewPropertyAnimator(duration: 0.15, timingParameters: timing)
        animator.addAnimations { self.alpha = 1; self.transform = .identity }
        animator.startAnimation()
    }
    func close() { removeFromSuperview() }
}
