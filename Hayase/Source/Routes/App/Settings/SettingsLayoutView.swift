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
        // the labels get their widths in a layout pass (`WrappingLabel`), the height is measured after it
        for _ in 0..<2 {
            page.setNeedsLayout()
            page.layoutIfNeeded()
        }
        // measured, laid out at that height, and measured again until the rows have the height their text needs
        var pageHeight: CGFloat = 0
        if !page.arrangedSubviews.isEmpty {
            for _ in 0..<3 {
                let fitted = ceil(page.systemLayoutSizeFitting(
                    CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
                let unchanged = abs(page.frame.height - fitted) < 0.5
                page.frame.size.height = fitted
                page.layoutIfNeeded()
                pageHeight = fitted
                if unchanged { break }
            }
        }
        let bottomPadding: CGFloat = wide ? 56 : (medium ? 40 : 80)
        let height = max(asideHeight, contentY + pageHeight + bottomPadding)
        scrollView.contentSize = CGSize(width: available, height: height)
        positionAside()
        updateStickyDates()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        positionAside()
        updateStickyDates()
    }

    private func updateStickyDates() {
        page.arrangedSubviews.compactMap { $0 as? SettingsChangelogView }
            .forEach { $0.updateStickyDates(in: scrollView) }
    }

    private func positionAside() {
        guard !navigation.isHidden else { return }
        // CSS sticky is bounded by the parent's scrollable content, including in
        // short landscape windows where the aside is taller than the viewport.
        let y = min(max(0, scrollView.contentOffset.y), max(0, scrollView.contentSize.height - asideHeight))
        navigation.frame = CGRect(x: asideX, y: y, width: asideWidth, height: asideHeight)
        navigation.setNeedsLayout()
    }
}
