//
//  SectionHeader.swift
//  Hayase
//
//  Mirrors: the header of each section of interface routes/app/home/+page.svelte
//
//      <div class='flex px-4 pt-5 items-end cursor-pointer text-muted-foreground relative z-[1]'>
//        <div class='font-semibold text-lg leading-none select:text-foreground' use:click={() => search(variables)}>{title}</div>
//        <div class='ml-auto text-xs select:text-foreground' use:click={() => search(variables)}>View More</div>
//
//  Both texts lead to the same search, and both turn `text-foreground` while hovered, focused or
//  pressed. `items-end` lines up the bottoms of their line boxes, not their baselines.
//

import UIKit

final class HomeSectionHeaderView: UICollectionReusableView {
    static let reuseID = "HomeSectionHeader"
    /// `pt-5` and the 18pt line of the title
    static let height: CGFloat = 38

    /// Either text was clicked.
    var onViewMore: (() -> Void)?

    // text-lg leading-none: 18pt on a line of 18pt
    private let titleControl = HeaderTextControl(font: .nunito(ofSize: 18, weight: .semibold), lineHeight: 18)
    // text-xs: 12pt on a line of 16pt
    private let viewMoreControl = HeaderTextControl(font: .nunito(ofSize: 12), lineHeight: 16)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        viewMoreControl.setText("View More")
        [titleControl, viewMoreControl].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.addTarget(self, action: #selector(tapped), for: .touchUpInside)
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            // px-4, and the row ends at the bottom of the tallest box: `items-end`
            titleControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleControl.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleControl.heightAnchor.constraint(equalToConstant: 18),
            viewMoreControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            viewMoreControl.bottomAnchor.constraint(equalTo: bottomAnchor),
            viewMoreControl.heightAnchor.constraint(equalToConstant: 16),
            viewMoreControl.leadingAnchor.constraint(greaterThanOrEqualTo: titleControl.trailingAnchor),
        ])
    }

    @objc private func tapped() { onViewMore?() }

    func configure(title: String) {
        titleControl.setText(title)
        accessibilityLabel = title
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onViewMore = nil
    }
}

// MARK: - HeaderTextControl

/// A text with `select:text-foreground`: muted until it is hovered or pressed. Like every element
/// that can be focused, it also shrinks to 98% while it is pressed.
private final class HeaderTextControl: UIControl {
    private let label = UILabel()
    private let font: UIFont
    private let lineHeight: CGFloat
    private var text = ""
    private var isHovered = false
    private var pressAnimator: UIViewPropertyAnimator?

    init(font: UIFont, lineHeight: CGFloat) {
        self.font = font
        self.lineHeight = lineHeight
        super.init(frame: .zero)
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        accessibilityTraits = .button
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setText(_ text: String) {
        self.text = text
        applyText()
    }

    private func applyText() {
        let selected = isHighlighted || isHovered
        label.attributedText = CSSText.string(text, font: font,
                                              color: selected ? UIColor.HayaseTheme.foreground : UIColor.HayaseTheme.mutedForeground,
                                              lineHeight: lineHeight)
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isHovered = recognizer.state == .began || recognizer.state == .changed
        applyText()
    }

    override var isHighlighted: Bool {
        didSet {
            applyText()
            pressAnimator?.stopAnimation(true)
            pressAnimator = nil
            guard isHighlighted else {
                transform = .identity
                return
            }
            let animator = UIViewPropertyAnimator(duration: 0.1,
                                                  controlPoint1: CGPoint(x: 0.42, y: 0),
                                                  controlPoint2: CGPoint(x: 0.58, y: 1)) {
                self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            }
            pressAnimator = animator
            animator.startAnimation()
        }
    }
}
