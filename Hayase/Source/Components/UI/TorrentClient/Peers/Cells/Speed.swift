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
            case .download: return .systemGreen
            case .upload: return .systemBlue
            }
        }
    }

    private let imageView = UIImageView()
    private let label: UILabel = {
        let label = UILabel()
        label.font = .nunito(ofSize: 14)
        label.textColor = TorrentClientStyle.foreground
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        return label
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
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.axis = .horizontal
        stack.spacing = 8
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
        label.text = TorrentDetailViewController.fastPrettyBits(bytesPerSecond * 8) + "/s"
    }
}
