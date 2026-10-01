//
//  ChatBubbleView.swift
//  Hayase
//
//  Mirrors: interface components/ui/chat Messages.svelte and MessageToast.svelte, whose message
//  bubble is `bg-muted py-2 px-3 rounded-t-xl mb-1 select-all text-xs whitespace-pre-wrap`.
//

import UIKit

/// A chat message's bubble. Its text is selected as a whole when it is tapped (`select-all`).
final class ChatBubbleView: UIView {
    private let textView = ChatBubbleTextView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 12   // rounded-xl
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 8),               // py-2
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),      // px-3
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    private static func attributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 16   // text-xs
        paragraph.maximumLineHeight = 16
        return [
            .font: UIFont.nunito(ofSize: 12),
            .foregroundColor: UIColor.HayaseTheme.foreground,
            .paragraphStyle: paragraph,
        ]
    }

    func configure(text: String, background: UIColor, corners: CACornerMask) {
        textView.attributedText = NSAttributedString(string: text, attributes: Self.attributes())
        backgroundColor = background
        layer.maskedCorners = corners
    }

    /// The size a bubble takes for `text` when it can be at most `maxWidth` wide, for callers that
    /// lay out by hand.
    static func size(for text: String, maxWidth: CGFloat) -> CGSize {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: max(0, maxWidth - 24), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(), context: nil)
        return CGSize(width: ceil(bounds.width) + 24, height: ceil(bounds.height) + 16)
    }
}

private final class ChatBubbleTextView: UITextView {
    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectEverything)))
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func selectEverything() {
        becomeFirstResponder()
        selectedRange = NSRange(location: 0, length: ((text ?? "") as NSString).length)
        UIMenuController.shared.showMenu(from: self, rect: bounds)
    }
}
