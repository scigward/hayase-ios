//
//  Country.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

final class PeerCountryCellContent: UIView {
    private let emojiLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20)
        label.textAlignment = .center
        return label
    }()

    private let countryLabel: UILabel = {
        let label = UILabel()
        label.font = .nunito(ofSize: 14)
        label.textColor = TorrentClientStyle.mutedForeground
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private var representedIP: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let stack = UIStackView(arrangedSubviews: [emojiLabel, countryLabel])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            emojiLabel.widthAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(ip: String) {
        representedIP = ip
        emojiLabel.text = nil
        countryLabel.text = "?"

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let location = TorrentClientGeoIP.shared.lookup(ip)
            DispatchQueue.main.async {
                guard let self, self.representedIP == ip else { return }
                guard let location else {
                    self.emojiLabel.text = nil
                    self.countryLabel.text = "?"
                    return
                }
                self.emojiLabel.text = Self.codeToEmoji(location.country)
                self.countryLabel.text = location.country
            }
        }
    }

    private static func codeToEmoji(_ code: String) -> String {
        if code == "ALL" { return "🌎" }
        let base: UInt32 = 0x1F1E6 - 65
        let scalars = code.uppercased().unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            UnicodeScalar(base + scalar.value)
        }
        return scalars.map { String($0) }.joined()
    }
}
