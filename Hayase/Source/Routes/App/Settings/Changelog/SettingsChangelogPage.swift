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

        titleLabel.font = .nunito(ofSize: 36, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        descriptionLabel.font = .nunito(ofSize: 14)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground

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
        titleLabel.text = title
        descriptionLabel.text = description
        let left = wide ? max(0, self.bounds.width * 0.25) : 16
        intro.layoutMargins = UIEdgeInsets(top: 0, left: left, bottom: 0, right: 16)
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
                message: error))
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
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    init(entry: HayaseChangelogEntry, wide: Bool) {
        super.init(frame: .zero)

        let separator = UIView()
        separator.backgroundColor = UIColor.HayaseTheme.border
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        let dateLabel = UILabel()
        dateLabel.text = Self.dateFormatter.string(from: entry.date)
        dateLabel.font = .nunito(ofSize: 12)
        dateLabel.textColor = UIColor.HayaseTheme.mutedForeground

        let commitLabel = UILabel()
        commitLabel.text = String(entry.sha.prefix(6))
        commitLabel.font = .nunito(ofSize: 18, weight: .bold)
        commitLabel.textColor = UIColor.HayaseTheme.foreground

        let bodyLabel = UILabel()
        bodyLabel.text = entry.body.replacingOccurrences(of: "- ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        bodyLabel.font = .nunito(ofSize: 16)
        bodyLabel.textColor = UIColor.HayaseTheme.mutedForeground
        bodyLabel.numberOfLines = 0

        let body = UIStackView(arrangedSubviews: [commitLabel, bodyLabel])
        body.axis = .vertical
        body.alignment = .fill
        body.spacing = 12

        let dateContainer = UIView()
        dateContainer.addSubview(dateLabel)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dateLabel.topAnchor.constraint(equalTo: dateContainer.topAnchor, constant: 12),
            dateLabel.leadingAnchor.constraint(equalTo: dateContainer.leadingAnchor),
            dateLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateContainer.trailingAnchor, constant: -12),
            dateLabel.bottomAnchor.constraint(equalTo: dateContainer.bottomAnchor),
        ])

        let content = UIStackView()
        content.axis = wide ? .horizontal : .vertical
        content.alignment = wide ? .top : .fill
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
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            content.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 40),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: wide ? 0 : 16),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class HayaseChangelogMessageView: UIView {
    init(title: String, message: String) {
        super.init(frame: .zero)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .nunito(ofSize: 24, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = .nunito(ofSize: 12)
        messageLabel.textColor = UIColor.HayaseTheme.mutedForeground
        messageLabel.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
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
            dateContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            dateSkeleton.topAnchor.constraint(equalTo: dateContainer.topAnchor, constant: 8),
            dateSkeleton.leadingAnchor.constraint(equalTo: dateContainer.leadingAnchor, constant: 16),
            dateSkeleton.trailingAnchor.constraint(lessThanOrEqualTo: dateContainer.trailingAnchor, constant: -12),
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

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            content.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 40),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
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
        content.spacing = wide ? 0 : 16
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
        pulse.fromValue = 0.45
        pulse.toValue = 1
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        view.layer.add(pulse, forKey: "hayasePulse")
        return view
    }
}
