//
//  SetupPage.swift
//  Hayase
//
//  Mirrors: src/routes/setup/+page.svelte
//
//    <div class='space-y-3 lg:max-w-4xl h-full overflow-y-auto w-full py-8 flex flex-col items-center justify-center'>
//      <Logo class='w-52 h-52 object-contain mb-14 shrink-0' />
//      <div class='font-bold text-5xl text-center w-full overflow-x-clip flex justify-center'>
//        <div class='relative'>
//          Welcome to Hayase
//          <div class='animate-[hearbeat_1.5s_ease-in-out_infinite_alternate] absolute text-lg text-theme right-0 -top-5 xs:-right-20 xs:-top-2 rotate-12'>Previously known as Miru!</div>
//        </div>
//      </div>
//      <div class='text-muted-foreground pt-3 text-center px-3'>Let's set up your perfect streaming environment.</div>
//      <div class='flex items-center space-x-2 pt-12 pb-3 px-5'>
//        <Checkbox bind:checked />
//        <Label for='terms' class='text-md font-medium leading-none text-muted-foreground'>I agree to the <a …>Terms of Service</a> and <a …>Privacy Policy</a></Label>
//      </div>
//      <Button class='text-lg font-bold shrink-0' disabled={!checked} size='lg' href={checked ? '/#/setup/storage' : undefined} data-sveltekit-replacestate>{…}</Button>
//    </div>
//
//  Notes on what the classes come to:
//   - `text-md` is not a Tailwind size, but tailwind-merge takes it for a font size and drops the Label's
//     `text-sm`, so the label is the page's 16px, on a `leading-none` line of 16px.
//   - The `for='terms'` of the label names no element, so a tap on its text does nothing.
//   - The column is `justify-center`: a page too tall for the window loses its top, which cannot be scrolled to.
//

import UIKit

final class SetupWelcomePage: SetupPageView {
    private static let titleText = "Welcome to Hayase"
    private static let badgeText = "Previously known as Miru!"
    private static let subtitleText = "Let's set up your perfect streaming environment."
    private static let columnMaxWidth: CGFloat = 896      // lg:max-w-4xl
    private static let termsURL = "https://hayase.watch/terms"
    private static let privacyURL = "https://hayase.watch/privacy"

    private let scroll = UIScrollView()
    private let logo = LogoView()
    private let titleClip = HorizontalClipView()
    private let titleLabel = UILabel()
    private let badgeLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let checkbox = Checkbox()
    private let terms = SetupTermsLabel()
    private let startButton = SelectButton()

    override init(frame: CGRect) {
        super.init(frame: frame)

        scroll.showsVerticalScrollIndicator = false      // *::-webkit-scrollbar { display: none }
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delaysContentTouches = false
        addSubview(scroll)

        scroll.addSubview(logo)

        // font-bold text-5xl text-center: 48pt on a 48pt line
        titleLabel.numberOfLines = 0
        titleLabel.attributedText = CSSText.string(Self.titleText, font: .nunito(ofSize: 48, weight: .bold),
                                                   color: UIColor.HayaseTheme.foreground, lineHeight: 48,
                                                   alignment: .center, lineBreak: .byWordWrapping)
        titleClip.addSubview(titleLabel)

        // absolute text-lg text-theme rotate-12, in the bold of the row it is in: 18pt on a 28pt line
        badgeLabel.numberOfLines = 0
        badgeLabel.attributedText = CSSText.string(Self.badgeText, font: .nunito(ofSize: 18, weight: .bold),
                                                   color: UIColor.HayaseTheme.theme, lineHeight: 28,
                                                   lineBreak: .byWordWrapping)
        badgeLabel.transform = CGAffineTransform(rotationAngle: 12 * .pi / 180)    // rotate-12
        titleClip.addSubview(badgeLabel)
        scroll.addSubview(titleClip)

        // text-muted-foreground text-center, on the 24pt line of the page
        subtitleLabel.numberOfLines = 0
        subtitleLabel.attributedText = CSSText.string(Self.subtitleText, font: .nunito(ofSize: 16),
                                                      color: UIColor.HayaseTheme.mutedForeground, lineHeight: 24,
                                                      alignment: .center, lineBreak: .byWordWrapping)
        scroll.addSubview(subtitleLabel)

        scroll.addSubview(checkbox)
        terms.configure(links: [("Terms of Service", Self.termsURL), ("Privacy Policy", Self.privacyURL)])
        scroll.addSubview(terms)
        checkbox.addAction(UIAction { [weak self] _ in self?.checkedChanged() }, for: .valueChanged)

        // <Button size='lg' class='text-lg font-bold'>: h-10 px-8
        startButton.applyPrimaryVariant()
        startButton.titleLabel?.font = .nunito(ofSize: 18, weight: .bold)
        startButton.dimsWhenDisabled = true
        startButton.addAction(UIAction { [weak self] _ in self?.navigate?(.storage) }, for: .touchUpInside)
        scroll.addSubview(startButton)
        checkedChanged()
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// `{!checked ? 'Accept terms to continue' : 'Start Setup'}`, and `disabled={!checked}`
    private func checkedChanged() {
        let checked = checkbox.isChecked
        startButton.isEnabled = checked
        startButton.setTitle(checked ? "Start Setup" : "Accept terms to continue", for: .normal)
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        startBadgeAnimation()
    }

    /// `hearbeat 1.5s ease-in-out infinite alternate`: from the page's scale of 1 to 0.85 and back,
    /// on top of the `rotate-12`.
    private func startBadgeAnimation() {
        badgeLabel.layer.removeAnimation(forKey: "hearbeat")
        let rotation = CATransform3DMakeRotation(12 * .pi / 180, 0, 0, 1)
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: CATransform3DScale(rotation, 1, 1, 1))
        animation.toValue = NSValue(caTransform3D: CATransform3DScale(rotation, 0.85, 0.85, 1))
        animation.duration = 1.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        badgeLabel.layer.add(animation, forKey: "hearbeat")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = bounds.height
        guard width > 0 else { return }
        // w-full, lg:max-w-4xl, centred by the container's items-center
        let large = viewportWidth >= 1024
        let columnWidth = large ? min(width, Self.columnMaxWidth) : width
        scroll.frame = CGRect(x: (width - columnWidth) / 2, y: 0, width: columnWidth, height: height)
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Logo: w-52 h-52 mb-14
        let logoSide: CGFloat = 208
        var y: CGFloat = 0
        let logoY = y
        y += logoSide + 56

        // Title: space-y-3, and the relative box is as wide as the text, down to the row
        y += 12
        let titleTop = y
        let titleNatural = ceil(titleLabel.sizeThatFits(unbounded).width)
        let titleBoxWidth = min(titleNatural, columnWidth)
        let titleHeight = ceil(titleLabel.sizeThatFits(CGSize(width: titleBoxWidth, height: .greatestFiniteMagnitude)).height)
        y += titleHeight

        // Subtitle: space-y-3, pt-3 px-3
        y += 12
        let subtitleTop = y + 12
        let subtitleNatural = ceil(subtitleLabel.sizeThatFits(unbounded).width)
        let subtitleWidth = min(subtitleNatural, max(0, columnWidth - 24))
        let subtitleHeight = ceil(subtitleLabel.sizeThatFits(CGSize(width: subtitleWidth, height: .greatestFiniteMagnitude)).height)
        y = subtitleTop + subtitleHeight

        // Terms: space-y-3, pt-12 pb-3 px-5, the box and the label 8pt apart (space-x-2)
        y += 12
        let termsRowTop = y
        let termsNatural = ceil(terms.sizeThatFits(unbounded).width)
        let termsRowWidth = min(termsNatural + 20 + Checkbox.side + 8 + 20, columnWidth)
        let termsWidth = max(0, termsRowWidth - 40 - Checkbox.side - 8)
        let termsHeight = ceil(terms.sizeThatFits(CGSize(width: termsWidth, height: .greatestFiniteMagnitude)).height)
        let termsContent = max(Checkbox.side, termsHeight)
        y = termsRowTop + 48 + termsContent + 12

        // Button: space-y-3, h-10 px-8
        y += 12
        let buttonTop = y
        let buttonText = ceil(startButton.titleLabel?.sizeThatFits(unbounded).width ?? 0)
        let buttonWidth = buttonText + 64
        y += 40
        let contentHeight = y

        // py-8 around a column that is justify-center
        let inner = max(0, height - 64)
        let startY = 32 + (inner - contentHeight) / 2
        let center = columnWidth / 2

        logo.frame = CGRect(x: center - logoSide / 2, y: startY + logoY, width: logoSide, height: logoSide)

        titleClip.frame = CGRect(x: 0, y: startY + titleTop, width: columnWidth, height: titleHeight)
        let titleBoxX = (columnWidth - titleBoxWidth) / 2
        titleLabel.frame = CGRect(x: titleBoxX, y: 0, width: titleBoxWidth, height: titleHeight)
        // right-0 -top-5, and from xs (480) -right-20 -top-2
        let extra: CGFloat = viewportWidth >= 480 ? 80 : 0
        let badgeAvailable = titleBoxWidth + extra
        let badgeNatural = ceil(badgeLabel.sizeThatFits(unbounded).width)
        let badgeWidth = min(badgeNatural + 0.5, badgeAvailable)
        let badgeHeight = ceil(badgeLabel.sizeThatFits(CGSize(width: badgeWidth, height: .greatestFiniteMagnitude)).height)
        let badgeRight = titleBoxX + titleBoxWidth + extra
        let badgeTop: CGFloat = viewportWidth >= 480 ? -8 : -20
        // The transform is the label's own (the rotation and its pulse), so it is placed by centre
        badgeLabel.bounds = CGRect(x: 0, y: 0, width: badgeWidth, height: badgeHeight)
        badgeLabel.center = CGPoint(x: badgeRight - badgeWidth / 2, y: badgeTop + badgeHeight / 2)

        subtitleLabel.frame = CGRect(x: center - subtitleWidth / 2, y: startY + subtitleTop,
                                     width: subtitleWidth, height: subtitleHeight)

        let rowX = center - termsRowWidth / 2
        let contentTop = startY + termsRowTop + 48
        checkbox.frame = CGRect(x: rowX + 20, y: contentTop + (termsContent - Checkbox.side) / 2,
                                width: Checkbox.side, height: Checkbox.side)
        terms.frame = CGRect(x: rowX + 20 + Checkbox.side + 8, y: contentTop + (termsContent - termsHeight) / 2,
                             width: termsWidth, height: termsHeight)

        startButton.frame = CGRect(x: center - buttonWidth / 2, y: startY + buttonTop, width: buttonWidth, height: 40)

        scroll.contentSize = CGSize(width: columnWidth, height: max(height, startY + contentHeight + 32))
    }
}

/// `overflow-x-clip`: what goes out of the row's width is cut, and nothing is cut above or below it.
private final class HorizontalClipView: UIView {
    private let maskLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.mask = maskLayer
        maskLayer.fillColor = UIColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        maskLayer.frame = bounds
        maskLayer.path = UIBezierPath(rect: CGRect(x: 0, y: -10_000, width: bounds.width, height: bounds.height + 20_000)).cgPath
    }
}

/// The Label of the terms: `font-medium leading-none text-muted-foreground`, with two links that are
/// `text-foreground underline py-2 px-1`. An inline box's padding is part of the link, so the
/// text is spaced out by 4pt either side of it and a tap within 4pt across and 8pt above and below counts.
private final class SetupTermsLabel: UILabel {
    private struct Link {
        let range: NSRange
        let url: URL
        let title: String
    }

    private var links: [Link] = []
    private static let padding = CGSize(width: 4, height: 8)    // px-1 py-2

    override init(frame: CGRect) {
        super.init(frame: frame)
        numberOfLines = 0
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// "I agree to the <link> and <link>"
    func configure(links specs: [(title: String, url: String)]) {
        let font = UIFont.nunito(ofSize: 16, weight: .medium)
        let muted = CSSText.attributes(font: font, color: UIColor.HayaseTheme.mutedForeground, lineHeight: 16,
                                       lineBreak: .byWordWrapping)
        let linked = CSSText.attributes(font: font, color: UIColor.HayaseTheme.foreground, lineHeight: 16,
                                        lineBreak: .byWordWrapping)
        // A kern of 4pt on the space before a link, and on the one after it, is the padding of the inline box.
        func spacer() -> NSAttributedString {
            var attributes = muted
            attributes[.kern] = Self.padding.width
            return NSAttributedString(string: " ", attributes: attributes)
        }
        let text = NSMutableAttributedString(string: "I agree to the", attributes: muted)
        links = []
        for (index, spec) in specs.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "and", attributes: muted)) }
            text.append(spacer())
            var attributes = linked
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            let start = text.length
            text.append(NSAttributedString(string: spec.title, attributes: attributes))
            if let url = URL(string: spec.url) {
                links.append(Link(range: NSRange(location: start, length: spec.title.count), url: url, title: spec.title))
            }
            if index < specs.count - 1 { text.append(spacer()) }
        }
        // the padding after the last link
        var tail = muted
        tail[.kern] = Self.padding.width
        text.append(NSAttributedString(string: "\u{200B}", attributes: tail))
        attributedText = text

        accessibilityCustomActions = links.map { link in
            UIAccessibilityCustomAction(name: link.title) { _ in
                UIApplication.shared.open(link.url)
                return true
            }
        }
        isAccessibilityElement = true
        accessibilityLabel = "I agree to the " + links.map(\.title).joined(separator: " and ")
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let text = attributedText, bounds.width > 0 else { return }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        let point = recognizer.location(in: self)
        let contentHeight = UIFont.nunito(ofSize: 16, weight: .medium).lineHeight
        for link in links {
            let glyphs = manager.glyphRange(forCharacterRange: link.range, actualCharacterRange: nil)
            var hit = false
            manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                            in: container) { rect, _ in
                // The box of an inline element is the font's content area, with the padding around it
                let area = CGRect(x: rect.minX - Self.padding.width, y: rect.midY - contentHeight / 2 - Self.padding.height,
                                  width: rect.width + 2 * Self.padding.width, height: contentHeight + 2 * Self.padding.height)
                if area.contains(point) { hit = true }
            }
            if hit {
                UIApplication.shared.open(link.url)
                return
            }
        }
    }
}
