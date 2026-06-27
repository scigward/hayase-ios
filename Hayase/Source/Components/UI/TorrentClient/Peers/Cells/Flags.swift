//
//  Flags.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

final class PeerFlagsCellContent: UIView {
    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(flags: [TorrentClientPeerRow.Flag]) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for flag in flags {
            stack.addArrangedSubview(Self.badge(for: flag))
        }
    }

    private static func badge(for flag: TorrentClientPeerRow.Flag) -> UIView {
        let container = UIView()
        container.backgroundColor = TorrentClientStyle.muted
        container.layer.cornerRadius = 4
        container.clipsToBounds = true
        container.accessibilityLabel = label(for: flag)

        let imageView = UIImageView(image: UIImage.hayaseIcon(iconName(for: flag), pointSize: 12))
        imageView.tintColor = tint(for: flag)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 20),
            container.heightAnchor.constraint(equalToConstant: 20),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
        ])
        return container
    }

    private static func iconName(for flag: TorrentClientPeerRow.Flag) -> String {
        switch flag {
        case .incoming: return "wifi"
        case .outgoing: return "wifi-off"
        case .utp: return "shield"
        case .encrypted: return "lock"
        }
    }

    private static func tint(for flag: TorrentClientPeerRow.Flag) -> UIColor {
        switch flag {
        case .incoming: return .systemGreen
        case .outgoing: return .systemBlue
        case .utp: return .systemPurple
        case .encrypted: return .systemYellow
        }
    }

    private static func label(for flag: TorrentClientPeerRow.Flag) -> String {
        switch flag {
        case .incoming: return "Incoming"
        case .outgoing: return "Outgoing"
        case .utp: return "uTP"
        case .encrypted: return "Encrypted"
        }
    }
}
