//
//  FullBannerTitle.swift
//  Hayase
//
//  Mirrors: the title of interface components/ui/banner/full-banner.svelte
//
//      <a class='text-foreground font-black text-3xl lg:text-4xl line-clamp-2 w-[900px] max-w-[85%]
//                leading-tight text-balance fade-in hover:text-muted-foreground hover:underline
//                cursor-pointer text-shadow-lg' href='/#/app/anime/{current.id}'>
//        {#await episodesCached(currentId) then metadata}
//          … <Load {src} alt={title(current)} class='drop-shadow-lg w-[30rem]' /> … or {title(current)}
//
//  The link holds the title or, when ani.zip has one, the logo of the show. It is the only part of
//  the banner that goes to the page of the media.
//

import UIKit

final class FullBannerTitleLink: UIControl, NoActiveScale {
    /// `w-[900px]`
    static let maxWidth: CGFloat = 900
    /// `max-w-[85%]`
    static let maxWidthFraction: CGFloat = 0.85

    let titleLabel: TextShadowLabel = {
        let label = TextShadowLabel()
        // text-3xl leading-tight = 30pt on 37.5pt lines (lg: text-4xl, 36pt on 45pt lines)
        label.lineHeight = 37.5
        label.font = .nunito(ofSize: 30, weight: .black)
        label.textColor = UIColor.HayaseTheme.foreground   // text-foreground
        label.numberOfLines = 2                            // line-clamp-2
        label.textAlignment = .center
        label.balancesText = true                          // text-balance
        return label
    }()

    /// The logo: transparent title art from ani.zip.
    let logoView: DropShadowImageView = {
        let view = DropShadowImageView()
        view.isHidden = true
        return view
    }()

    /// `items-center` below `lg`, `lg:items-start` from there
    let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    var onTap: (() -> Void)?

    private var pressAnimator: UIViewPropertyAnimator?
    private var isHovered = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityTraits = .link

        contentStack.addArrangedSubview(logoView)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.isUserInteractionEnabled = false   // the link takes the touches
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Sizes the link against the column it is in: `w-[900px] max-w-[85%]`.
    func constrainWidth(to column: UIView) {
        let wide = widthAnchor.constraint(equalToConstant: Self.maxWidth)
        wide.priority = .defaultLow
        NSLayoutConstraint.activate([
            wide,
            widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth),
            widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor, multiplier: Self.maxWidthFraction),
        ])
    }

    /// Lets the text wrap at the width the link has, which `text-balance` then narrows.
    func updateBalance(columnWidth: CGFloat) {
        titleLabel.balanceMaxWidth = max(0, min(Self.maxWidth, columnWidth * Self.maxWidthFraction))
    }

    func setLargeLayout(_ large: Bool) {
        contentStack.alignment = large ? .leading : .center
        titleLabel.textAlignment = large ? .left : .center              // lg:text-left
        titleLabel.font = .nunito(ofSize: large ? 36 : 30, weight: .black)
        titleLabel.lineHeight = large ? 45 : 37.5
    }

    @objc private func tapped() {
        onTap?()
    }

    // hover:text-muted-foreground hover:underline
    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isHovered = recognizer.state == .began || recognizer.state == .changed
        titleLabel.textColor = isHovered ? UIColor.HayaseTheme.mutedForeground : UIColor.HayaseTheme.foreground
        titleLabel.underlinesText = isHovered
    }

    // a[href]:active { transform: scale(0.98) }
    override var isHighlighted: Bool {
        didSet {
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
