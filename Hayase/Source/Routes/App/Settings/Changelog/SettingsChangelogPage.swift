//
//  SettingsChangelogPage.swift
//  Hayase
//
//  Mirrors: src/routes/app/settings/changelog/+page.svelte: the sections of the Changelog settings page.
//

import Foundation
import UIKit

extension SettingsSectionCatalog {
    static let changelogSections: [Section] = [
        Section(header: "", rows: [
            Row(title: "Changelog",
                description: "New updates and improvements to Hayase.",
                kind: .changelogPlaceholder),
        ], tab: .changelog),
    ]
}

// MARK: - ChangelogPage

// Mirrors: src/routes/app/settings/changelog/+page.svelte

final class SettingsChangelogView: UIView, SettingsResponsiveView {

    private let rootStack = UIStackView()
    private let intro = UIStackView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let entries = UIStackView()
    private var configuration: (String, String, [HayaseChangelogEntry]?, String?)?
    private var isWide = false

    override func layoutSubviews() {
        super.layoutSubviews()
        let margins = UIEdgeInsets(top: 0, left: isWide ? bounds.width * 0.25 : 16,
                                   bottom: 0, right: isWide ? 0 : 16)
        if intro.layoutMargins != margins { intro.layoutMargins = margins }
    }

    func updateLayout(viewportWidth: CGFloat) {
        guard isWide != (viewportWidth >= 640), let configuration else { return }
        configure(title: configuration.0, description: configuration.1, wide: viewportWidth >= 640,
                  loadedEntries: configuration.2, error: configuration.3)
    }

    /// Mirrors the date's `sticky top-0` within each wide changelog grid row.
    func updateStickyDates(in scrollView: UIScrollView) {
        entries.arrangedSubviews.compactMap { $0 as? HayaseChangelogEntryView }
            .forEach { $0.updateStickyDate(in: scrollView) }
    }

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

        intro.axis = .vertical
        intro.spacing = 12
        intro.addArrangedSubview(titleLabel)
        intro.addArrangedSubview(descriptionLabel)
        intro.isLayoutMarginsRelativeArrangement = true
        intro.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)


        entries.axis = .vertical
        entries.spacing = 0

        rootStack.axis = .vertical
        let introContainer = UIView()
        introContainer.heightAnchor.constraint(equalToConstant: 240).isActive = true
        intro.translatesAutoresizingMaskIntoConstraints = false
        introContainer.addSubview(intro)
        NSLayoutConstraint.activate([
            intro.centerYAnchor.constraint(equalTo: introContainer.centerYAnchor),
            intro.leadingAnchor.constraint(equalTo: introContainer.leadingAnchor),
            intro.trailingAnchor.constraint(equalTo: introContainer.trailingAnchor),
        ])
        rootStack.addArrangedSubview(introContainer)
        rootStack.addArrangedSubview(entries)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: self.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }

    func configure(title: String,
                   description: String,
                   wide: Bool,
                   loadedEntries: [HayaseChangelogEntry]?,
                   error: String?) {
        configuration = (title, description, loadedEntries, error)
        isWide = wide
        titleLabel.font = .nunito(ofSize: 36, weight: .bold)
        titleLabel.attributedText = SettingsTypography.label(title, size: 36, lineHeight: 40, weight: .bold).attributedText
        descriptionLabel.font = .nunito(ofSize: 14)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.attributedText = SettingsTypography.label(description, size: 14, lineHeight: 20,
            color: UIColor.HayaseTheme.mutedForeground).attributedText
        let left = wide ? max(0, self.bounds.width * 0.25) : 16
        intro.layoutMargins = UIEdgeInsets(top: 0, left: left, bottom: 0, right: wide ? 0 : 16)
        intro.alignment = .fill

        entries.arrangedSubviews.forEach {
            entries.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if let loadedEntries {
            loadedEntries.forEach {
                entries.addArrangedSubview(HayaseChangelogEntryView(entry: $0, wide: wide))
            }
        } else if let error {
            entries.addArrangedSubview(HayaseChangelogMessageView(
                title: "Failed to load changelog",
                message: error, wide: wide))
        } else {
            for _ in 0..<5 {
                let entry = HayaseChangelogSkeletonEntry()
                entry.configure(wide: wide)
                entries.addArrangedSubview(entry)
            }
        }
    }
}

private final class HayaseChangelogEntryView: UIView {
    private let isWide: Bool
    private let dateContainer = UIView()
    private weak var stickyDateLabel: UILabel?
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    init(entry: HayaseChangelogEntry, wide: Bool) {
        isWide = wide
        super.init(frame: .zero)

        let separator = UIView()
        separator.backgroundColor = UIColor.HayaseTheme.border
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        let dateLabel = SettingsTypography.label(Self.dateFormatter.string(from: entry.date), size: 12, lineHeight: 16)

        let commitLabel = SettingsTypography.label(String(entry.sha.prefix(6)), size: 18, lineHeight: 28, weight: .bold)

        let bodyLabel = SettingsTypography.label(entry.body.replacingOccurrences(of: "- ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines), size: 16, lineHeight: 24,
            color: UIColor.HayaseTheme.mutedForeground)

        let body = UIStackView(arrangedSubviews: [commitLabel, bodyLabel])
        body.axis = .vertical
        body.alignment = .fill
        body.spacing = 12

        stickyDateLabel = dateLabel
        dateContainer.addSubview(dateLabel)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dateLabel.topAnchor.constraint(equalTo: dateContainer.topAnchor, constant: 12),
            dateLabel.leadingAnchor.constraint(equalTo: dateContainer.leadingAnchor),
            dateLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateContainer.trailingAnchor, constant: -12),
            dateLabel.bottomAnchor.constraint(lessThanOrEqualTo: dateContainer.bottomAnchor),
        ])

        let content = UIStackView()
        content.axis = wide ? .horizontal : .vertical
        content.alignment = .fill
        content.spacing = 0
        if wide {
            content.addArrangedSubview(dateContainer)
            content.addArrangedSubview(body)
            dateContainer.widthAnchor.constraint(equalTo: content.widthAnchor, multiplier: 0.25).isActive = true
        } else {
            content.addArrangedSubview(body)
            content.addArrangedSubview(dateContainer)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            // The settings page's space-y-3 sibling rule overrides Separator's my-6.
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            content.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 28),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: wide ? 0 : 16),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: wide ? 0 : -16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateStickyDate(in scrollView: UIScrollView) {
        guard isWide, let label = stickyDateLabel else { return }
        let normalTop = dateContainer.convert(dateContainer.bounds, to: scrollView).minY
        let viewportTop = scrollView.bounds.minY + scrollView.adjustedContentInset.top
        // The sticky element includes its pt-3 padding; retain that 12pt inset
        // both at the top of the viewport and at the end of its parent row.
        let maximum = max(0, dateContainer.bounds.height - label.bounds.height - 12)
        let translation = min(maximum, max(0, viewportTop - normalTop))
        label.transform = CGAffineTransform(translationX: 0, y: translation)
    }
}

private final class HayaseChangelogMessageView: UIView {
    init(title: String, message: String, wide: Bool) {
        super.init(frame: .zero)
        let titleLabel = SettingsTypography.label(title, size: 24, lineHeight: 32, weight: .bold)
        let messageLabel = SettingsTypography.label(message, size: 12, lineHeight: 16,
            color: UIColor.HayaseTheme.mutedForeground)
        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            // The page's sibling gap precedes the web error's h-60 container.
            heightAnchor.constraint(greaterThanOrEqualToConstant: 252),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: wide ? 0 : 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: wide ? 0 : -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class HayaseChangelogSkeletonEntry: UIView {
    private let dateContainer = UIView()
    private let dateSkeleton = HayaseChangelogSkeletonEntry.skeleton(width: 112, height: 8)
    private let body = UIStackView()
    private let content = UIStackView()
    private lazy var wideDateWidth = dateContainer.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.25)
    private var contentLeading: NSLayoutConstraint?
    private var contentTrailing: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let separator = UIView()
        separator.backgroundColor = UIColor.HayaseTheme.border
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        dateSkeleton.translatesAutoresizingMaskIntoConstraints = false
        dateContainer.addSubview(dateSkeleton)
        NSLayoutConstraint.activate([
            dateContainer.heightAnchor.constraint(equalToConstant: 8),
            dateSkeleton.topAnchor.constraint(equalTo: dateContainer.topAnchor),
            dateSkeleton.leadingAnchor.constraint(equalTo: dateContainer.leadingAnchor),
            dateSkeleton.bottomAnchor.constraint(lessThanOrEqualTo: dateContainer.bottomAnchor),
        ])

        let heading = Self.skeleton(width: 192, height: 16)
        let line1 = Self.skeleton(width: 128, height: 8)
        let line2 = Self.skeleton(width: 112, height: 8)
        body.addArrangedSubview(heading)
        body.addArrangedSubview(line1)
        body.addArrangedSubview(line2)
        body.axis = .vertical
        body.alignment = .leading
        body.spacing = 8
        body.setCustomSpacing(12, after: heading)
        content.axis = .horizontal
        content.alignment = .top
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(dateContainer)
        content.addArrangedSubview(body)
        addSubview(content)

        let leading = content.leadingAnchor.constraint(equalTo: leadingAnchor)
        let trailing = content.trailingAnchor.constraint(equalTo: trailingAnchor)
        contentLeading = leading
        contentTrailing = trailing
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            content.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 28),
            leading, trailing,
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
        configure(wide: true)
    }

    func configure(wide: Bool) {
        wideDateWidth.isActive = false
        for view in content.arrangedSubviews {
            content.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        content.axis = wide ? .horizontal : .vertical
        content.alignment = wide ? .top : .fill
        content.spacing = 0
        contentLeading?.constant = wide ? 0 : 16
        contentTrailing?.constant = wide ? 0 : -16
        if wide {
            content.addArrangedSubview(dateContainer)
            content.addArrangedSubview(body)
        } else {
            content.addArrangedSubview(body)
            content.addArrangedSubview(dateContainer)
        }
        wideDateWidth.isActive = wide
    }

    private static func skeleton(width: CGFloat, height: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.HayaseTheme.primary.withAlphaComponent(0.05)
        view.layer.cornerRadius = min(4, height / 2)
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.5
        pulse.duration = 1
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        view.layer.add(pulse, forKey: "hayasePulse")
        return view
    }
}
