//
//  Textarea.swift
//  Hayase
//
//  Mirrors: interface components/ui/textarea.
//

import UIKit

/// `<Textarea>`: bg-muted, rounded-md, px-3 py-2, text-sm, shadow-sm, with `select:bg-accent
/// select:text-accent-foreground` and a `focus-visible:ring-1 ring-ring`. It grows with its
/// content (`field-sizing: content`), is capped by `maxLength` (`maxlength`) and hands Enter,
/// without Shift, to `onSubmit` instead of inserting a line break.
final class Textarea: UITextView, UITextViewDelegate {
    var onSubmit: (() -> Void)?
    var onTextChange: (() -> Void)?
    /// In UTF-16 units, as the browser counts them.
    var maxLength: Int?
    /// The height the field stops growing at and scrolls from. Nothing limits a textarea on the web;
    /// this keeps one from outgrowing the screen.
    var maxHeight: CGFloat? { didSet { invalidateIntrinsicContentSize() } }
    var placeholder = "" { didSet { placeholderLabel.text = placeholder } }

    private static let minHeight: CGFloat = 36
    private let placeholderLabel = UILabel()
    private var isPointerOver = false
    private var allowsLineBreak = false

    init() {
        super.init(frame: .zero, textContainer: nil)
        delegate = self
        font = .nunito(ofSize: 14)
        textColor = UIColor.HayaseTheme.foreground
        tintColor = UIColor.HayaseTheme.foreground
        backgroundColor = UIColor.HayaseTheme.muted
        layer.cornerRadius = 6
        textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        textContainer.lineFragmentPadding = 0
        isScrollEnabled = false
        clipsToBounds = false
        translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.font = .nunito(ofSize: 14)
        placeholderLabel.textColor = UIColor.HayaseTheme.mutedForeground
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
        ])

        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - Size

    override var intrinsicContentSize: CGSize {
        guard bounds.width > 0 else { return CGSize(width: UIView.noIntrinsicMetric, height: Self.minHeight) }
        let fitting = ceil(sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height)
        let height = min(max(fitting, Self.minHeight), maxHeight ?? .greatestFiniteMagnitude)
        exceedsMaxHeight = fitting > height
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isScrollEnabled != exceedsMaxHeight {
            isScrollEnabled = exceedsMaxHeight
            clipsToBounds = exceedsMaxHeight
        }
        if bounds.width != lastWidth {
            lastWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
        updateRing()
    }

    private var lastWidth: CGFloat = 0
    private var exceedsMaxHeight = false

    override var text: String! {
        didSet { contentDidChange() }
    }

    private func contentDidChange() {
        placeholderLabel.isHidden = !(text?.isEmpty ?? true)
        invalidateIntrinsicContentSize()
        onTextChange?()
    }

    // MARK: - Select state

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isPointerOver = recognizer.state == .began || recognizer.state == .changed
        updateAppearance()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        updateAppearance()
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        updateAppearance()
        return resigned
    }

    /// `select:` is hover, focus-visible or active, with `transition-colors`.
    private func updateAppearance() {
        let selected = isFirstResponder || isPointerOver
        UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.backgroundColor = selected ? UIColor.HayaseTheme.accent : UIColor.HayaseTheme.muted
            self.textColor = selected ? UIColor.HayaseTheme.accentForeground : UIColor.HayaseTheme.foreground
        }
        updateRing()
    }

    /// `focus-visible:ring-1 ring-ring` draws a 1px ring outside the field; otherwise `shadow-sm`.
    private func updateRing() {
        if isFirstResponder {
            layer.shadowColor = UIColor.HayaseTheme.ring.cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = 0
            layer.shadowOffset = .zero
            layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: -1, dy: -1),
                                            cornerRadius: layer.cornerRadius + 1).cgPath
        } else {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.05
            layer.shadowRadius = 1
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowPath = nil
        }
    }

    // MARK: - Enter

    /// A hardware keyboard's Shift+Enter and its Enter reach the delegate alike, as a line break;
    /// which key it was is only known here.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        allowsLineBreak = presses.contains {
            guard let key = $0.key else { return false }
            return (key.keyCode == .keyboardReturnOrEnter || key.keyCode == .keypadEnter)
                && key.modifierFlags.contains(.shift)
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        allowsLineBreak = false
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesCancelled(presses, with: event)
        allowsLineBreak = false
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        contentDidChange()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // `if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendMessage() }`
        if text == "\n" && !allowsLineBreak {
            onSubmit?()
            return false
        }
        guard let maxLength else { return true }
        let current = (textView.text ?? "") as NSString
        let room = maxLength - (current.length - range.length)
        guard (text as NSString).length > room else { return true }
        // A longer paste is cut to what fits, as the browser does, not refused.
        var cut = max(0, room)
        let pasted = text as NSString
        if cut > 0, cut < pasted.length, UTF16.isLeadSurrogate(pasted.character(at: cut - 1)) { cut -= 1 }
        textView.textStorage.replaceCharacters(in: range, with: pasted.substring(to: cut))
        textView.selectedRange = NSRange(location: range.location + cut, length: 0)
        contentDidChange()
        return false
    }
}
