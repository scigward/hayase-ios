//
//  SettingsNav.swift
//  Hayase
//
//  Mirrors: src/lib/components/SettingsNav.svelte: the list of the settings pages, with the pill that moves to the
//  page that is open.
//

import UIKit

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
                button.baseBackground = medium ? .clear : UIColor.HayaseTheme.muted
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

// MARK: - HayaseNavTabButton

//  Made by scigward.
//
//  Mirrors: src/lib/components/SettingsNav.svelte (crossfading bg-primary pill, title transition-colors duration-300) and src/app.css (:active scale)

// MARK: - HayaseNavTabButton

/// A `Button` of the settings navigation: `variant={isActive ? 'default' : 'ghost'}` with `bg-muted md:bg-transparent`.
/// The ghost one gets `select:bg-secondary-foreground/20 select:text-accent-foreground` while it is hovered, focused or
/// pressed; the one of the open page has the pill (`bg-primary`) over its own background, so only its text stays put.
/// Being a `SelectButton` it also has the 0.98 of `:active` and the 150ms of `transition-colors`.
final class HayaseNavTabButton: SelectButton {
    private let pill = UIView()
    private(set) var isCurrentTab = false
    /// `bg-muted md:bg-transparent`
    var baseBackground: UIColor = .clear {
        didSet { applyVariant() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        pill.backgroundColor = UIColor.HayaseTheme.primary
        pill.layer.cornerRadius = 6  // rounded-md
        pill.alpha = 0
        pill.isUserInteractionEnabled = false
        pill.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(pill, at: 0)
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: topAnchor),
            pill.leadingAnchor.constraint(equalTo: leadingAnchor),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyVariant()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func applyVariant() {
        restingBackground = baseBackground
        if isCurrentTab {
            // default: text-primary-foreground select:bg-primary/60, under the pill
            selectedBackground = UIColor.HayaseTheme.primary.withAlphaComponent(0.6)
            restingTint = UIColor.HayaseTheme.primaryForeground
            selectedTint = UIColor.HayaseTheme.primaryForeground
        } else {
            // ghost: select:bg-secondary-foreground/20 select:text-accent-foreground
            selectedBackground = UIColor.HayaseTheme.secondaryForeground.withAlphaComponent(0.2)
            restingTint = UIColor.HayaseTheme.foreground
            selectedTint = UIColor.HayaseTheme.accentForeground
        }
    }

    /// Marks `tag` as the current tab, moving the pill over from the previous one.
    static func select(tag: Int, in buttons: [HayaseNavTabButton], animated: Bool) {
        let previous = buttons.first { $0.isCurrentTab }
        let next = buttons.first { $0.tag == tag }
        for button in buttons {
            button.setCurrent(button.tag == tag, animated: animated)
        }
        guard animated, let previous, let next, previous !== next else { return }
        HayaseCrossfade.send(next.pill, from: previous.pill)
        HayaseCrossfade.receive(previous.pill, to: next.pill)
    }

    private func setCurrent(_ current: Bool, animated: Bool) {
        guard current != isCurrentTab else { return }
        isCurrentTab = current
        pill.alpha = current ? 1 : 0
        if animated, let label = titleLabel {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.3  // duration-300
            fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)  // transition-colors
            label.layer.add(fade, forKey: "hayaseTitleColor")
        }
        applyVariant()
    }
}
