//
//  Speed.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

final class PeerSpeedCellContent: UIView {
    enum Kind {
        case download
        case upload

        var iconName: String {
            switch self {
            case .download: return "download"
            case .upload: return "upload"
            }
        }

        var tint: UIColor {
            switch self {
            case .download: return TorrentClientStyle.green500
            case .upload: return TorrentClientStyle.blue500
            }
        }
    }

    private let imageView = UIImageView()
    private let label: UILabel = {
        let label = TorrentClientLabel()
        label.font = .nunito(ofSize: 14)
        label.textColor = TorrentClientStyle.foreground
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        return label
    }()

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 20) // Table.Root text-sm.
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
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.axis = .horizontal
        stack.spacing = 10 // gap-x-2 plus the interface icon's mr-0.5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(bytesPerSecond: UInt64, kind: Kind) {
        imageView.image = UIImage.hayaseIcon(kind.iconName, pointSize: 12)
        imageView.tintColor = kind.tint
        label.text = TorrentFormat.fastPrettyBits(bytesPerSecond * 8) + "/s"
    }
}
