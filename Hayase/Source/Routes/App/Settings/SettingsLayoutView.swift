// Mirrors: src/routes/app/settings/+layout.svelte and SettingsNav.svelte
import UIKit

final class SettingsLayoutView: UIView, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    let navigation = SettingsNavigationView()
    private let titleLabel = SettingsTypography.label("Settings", size: 24, lineHeight: 32, weight: .bold)
    private let subtitleLabel = SettingsTypography.label("Manage your app settings, preferences and accounts.",
                                                         size: 16, lineHeight: 24,
                                                         color: UIColor.HayaseTheme.mutedForeground)
    private let separator = UIView()
    private let page = UIStackView()
    private var asideHeight: CGFloat = 0
    private var asideX: CGFloat = 0
    private var asideWidth: CGFloat = 0
    var isIndex = false { didSet { setNeedsLayout() } }
    var viewportWidth: CGFloat {
        window?.rootViewController?.view.bounds.width ?? bounds.width
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.HayaseTheme.background
        separator.backgroundColor = UIColor.HayaseTheme.border
        [titleLabel, subtitleLabel, separator, scrollView].forEach { addSubview($0) }
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.delegate = self
        page.axis = .vertical
        page.spacing = 12
        scrollView.addSubview(page)
        scrollView.addSubview(navigation)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard window != nil,
              let rect = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboard = convert(rect, from: nil)
        let overlap = max(0, bounds.maxY - keyboard.minY)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }

    func setContent(_ views: [UIView]) {
        page.arrangedSubviews.forEach { page.removeArrangedSubview($0); $0.removeFromSuperview() }
        views.forEach { page.addArrangedSubview($0) }
        setNeedsLayout()
    }

    func invalidateContentSize() { setNeedsLayout() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let viewport = viewportWidth
        let medium = viewport >= 768
        let wide = viewport >= 1024
        let padding: CGFloat = medium ? 40 : 12
        let available = max(0, bounds.width - padding * 2)
        let headingWidth = wide ? min(1440, available) : available
        let headingX = (bounds.width - headingWidth) / 2
        let headingTop = safeAreaInsets.top + padding
        titleLabel.frame = CGRect(x: headingX, y: headingTop, width: headingWidth, height: 32)
        let subtitleHeight = ceil(subtitleLabel.sizeThatFits(CGSize(width: headingWidth, height: .greatestFiniteMagnitude)).height)
        subtitleLabel.frame = CGRect(x: headingX, y: titleLabel.frame.maxY + 2,
                                     width: headingWidth, height: subtitleHeight)
        let margin: CGFloat = medium ? 24 : 12
        separator.frame = CGRect(x: headingX, y: subtitleLabel.frame.maxY + margin, width: headingWidth, height: 1)
        let bodyY = separator.frame.maxY + margin
        scrollView.frame = CGRect(x: padding, y: bodyY, width: available, height: max(0, bounds.height - bodyY))

        page.arrangedSubviews.compactMap { $0 as? SettingsResponsiveView }
            .forEach { $0.updateLayout(viewportWidth: viewport) }
        navigation.viewportWidth = viewport
        navigation.isHidden = !medium && !isIndex
        let bodyWidth = wide ? min(1440, available) : available
        asideX = (available - bodyWidth) / 2
        asideWidth = wide ? min(240, max(0, bodyWidth - 48)) : bodyWidth
        let minimumAside = navigation.sizeThatFits(CGSize(width: asideWidth, height: .greatestFiniteMagnitude)).height
        asideHeight = navigation.isHidden ? 0 : (wide ? max(minimumAside, scrollView.bounds.height) : minimumAside)
        let contentX = wide ? asideX + asideWidth + 48 : asideX
        let contentWidth = max(0, wide ? bodyWidth - asideWidth - 48 : bodyWidth)
        let contentY = wide ? 0 : asideHeight
        page.frame = CGRect(x: contentX, y: contentY, width: contentWidth, height: page.bounds.height)
        let pageHeight = page.arrangedSubviews.isEmpty ? 0 : page.systemLayoutSizeFitting(
            CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        page.frame.size.height = ceil(pageHeight)
        page.layoutIfNeeded()
        let bottomPadding: CGFloat = wide ? 56 : (medium ? 40 : 80)
        let height = max(asideHeight, contentY + pageHeight + bottomPadding)
        scrollView.contentSize = CGSize(width: available, height: height)
        positionAside()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { positionAside() }

    private func positionAside() {
        guard !navigation.isHidden else { return }
        // CSS sticky is bounded by the parent's scrollable content, including in
        // short landscape windows where the aside is taller than the viewport.
        let y = min(max(0, scrollView.contentOffset.y), max(0, scrollView.contentSize.height - asideHeight))
        navigation.frame = CGRect(x: asideX, y: y, width: asideWidth, height: asideHeight)
        navigation.setNeedsLayout()
    }
}

final class SettingsNavigationView: UIView {
    var viewportWidth: CGFloat = 0
    var onSelect: ((SettingsTab) -> Void)?
    var onLicense: (() -> Void)?
    private let support = UIView()
    private let supportTitle = SettingsTypography.label("Support the Project", size: 16, lineHeight: 24, weight: .bold,
                                                       color: UIColor.HayaseTheme.secondary)
    private let supportDescription = SettingsTypography.label("Please consider supporting the development of Hayase by donating!",
                                                             size: 12, lineHeight: 16, color: UIColor.HayaseTheme.secondary)
    private let donate = SettingsSupportButton(frame: .zero)
    private var tabs: [HayaseNavTabButton] = []
    private var footer: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        support.backgroundColor = UIColor(red: 232 / 255, green: 121 / 255, blue: 249 / 255, alpha: 1)
        support.layer.cornerRadius = 4
        support.clipsToBounds = true
        support.layer.contents = HayaseSettingsArtwork.flowers?.cgImage
        support.layer.contentsGravity = .resizeAspectFill
        addSubview(support)
        [supportTitle, supportDescription, donate].forEach { support.addSubview($0) }
        donate.addAction(UIAction { _ in
            guard let url = URL(string: "https://github.com/sponsors/ThaUnknown/") else { return }
            UIApplication.shared.open(url)
        }, for: .touchUpInside)
        for tab in SettingsTab.allCases {
            let button = HayaseNavTabButton(frame: .zero)
            button.tag = tab.rawValue
            button.setTitle(tab.title, for: .normal)
            button.titleLabel?.font = .nunito(ofSize: 14, weight: .semibold)
            button.contentHorizontalAlignment = .leading
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(tab) }, for: .touchUpInside)
            addSubview(button)
            tabs.append(button)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        for text in ["Interface v6.4.573", "Native \(version)", "iOS \(UIDevice.current.systemVersion) \(UIDevice.current.model)"] {
            let label = SettingsTypography.label(text, size: 12, lineHeight: 16, weight: .light,
                                                color: UIColor.HayaseTheme.mutedForeground)
            footer.append(label)
        }
        let license = UIButton(type: .custom)
        license.setAttributedTitle(NSAttributedString(string: "License Information", attributes: [
            .font: UIFont.nunito(ofSize: 12, weight: .light),
            .foregroundColor: UIColor.HayaseTheme.foreground, .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]), for: .normal)
        license.contentHorizontalAlignment = .leading
        license.addAction(UIAction { [weak self] _ in self?.onLicense?() }, for: .touchUpInside)
        footer.append(license)
        footer.forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(_ tab: SettingsTab?, animated: Bool) {
        HayaseNavTabButton.select(tag: tab?.rawValue ?? -1, in: tabs, animated: animated)
        tabs.forEach { $0.accessibilityTraits = $0.isCurrentTab ? [.button, .selected] : .button }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: arrange(width: size.width, height: 0, apply: false))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        _ = arrange(width: bounds.width, height: bounds.height, apply: true)
    }

    private func arrange(width: CGFloat, height: CGFloat, apply: Bool) -> CGFloat {
        let medium = viewportWidth >= 768
        let wide = viewportWidth >= 1024
        let horizontal = medium && !wide
        let gap: CGFloat = viewportWidth >= 640 ? 8 : 4
        let inner = max(0, width - 48)
        let messageHeight = ceil(supportDescription.sizeThatFits(CGSize(width: inner, height: .greatestFiniteMagnitude)).height)
        let supportHeight = 32 + 24 + gap + messageHeight + gap + 32
        if apply {
            backgroundColor = medium ? UIColor.HayaseTheme.background : .clear
            support.frame = CGRect(x: 0, y: 0, width: width, height: supportHeight)
            supportTitle.frame = CGRect(x: 24, y: 16, width: inner, height: 24)
            supportDescription.frame = CGRect(x: 24, y: 40 + gap, width: inner, height: messageHeight)
            donate.frame = CGRect(x: 24, y: 40 + gap + messageHeight + gap, width: wide ? inner : min(160, inner), height: 32)
        }
        var y = supportHeight + 16
        var x: CGFloat = 0
        for button in tabs {
            let buttonHeight: CGFloat = medium ? 36 : 40
            let buttonWidth = horizontal ? ceil(button.titleLabel?.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 36)).width ?? 0) + 32 : width
            if apply {
                button.frame = CGRect(x: x, y: y, width: buttonWidth, height: buttonHeight)
                button.contentEdgeInsets = UIEdgeInsets(top: 0, left: medium ? 16 : 32, bottom: 0, right: medium ? 16 : 32)
                button.backgroundColor = medium ? .clear : UIColor.HayaseTheme.muted
            }
            if horizontal { x += buttonWidth + 8 } else { y += buttonHeight + 4 }
        }
        y += horizontal ? 36 : -4
        if viewportWidth < 640 { y += 8 }
        let footerPadding: CGFloat = medium ? 20 : 12
        let footerX: CGFloat = viewportWidth >= 640 ? 8 : 16
        let footerWidth = max(0, width - 2 * footerX)
        var positions: [CGRect] = []
        x = 0
        var footerY: CGFloat = 0
        for item in footer {
            let itemWidth = min(footerWidth, ceil(item.sizeThatFits(CGSize(width: footerWidth, height: .greatestFiniteMagnitude)).width))
            if !wide && x > 0 && x + itemWidth > footerWidth { x = 0; footerY += 18 }
            positions.append(CGRect(x: wide ? 0 : x, y: footerY, width: wide ? footerWidth : itemWidth, height: 16))
            if wide { footerY += 18 } else { x += itemWidth + 16 }
        }
        let footerHeight = footerY + (wide ? -2 : 16) + 2 * footerPadding
        let footerTop = max(y, height - footerHeight)
        if apply {
            for (item, rect) in zip(footer, positions) {
                item.frame = rect.offsetBy(dx: footerX, dy: footerTop + footerPadding)
            }
        }
        return y + footerHeight
    }
}
