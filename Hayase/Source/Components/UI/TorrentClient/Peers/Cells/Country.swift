//
//  Country.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

final class PeerCountryCellContent: UIView {
    private let flagView = TwemojiFlagView()

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
        let stack = UIStackView(arrangedSubviews: [flagView, countryLabel])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            flagView.widthAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(ip: String) {
        representedIP = ip
        flagView.configure(code: nil)
        countryLabel.text = "?"

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let location = TorrentClientGeoIP.shared.lookup(ip)
            DispatchQueue.main.async {
                guard let self, self.representedIP == ip else { return }
                guard let location else {
                    self.flagView.configure(code: nil)
                    self.countryLabel.text = "?"
                    return
                }
                self.flagView.configure(code: location.country)
                self.countryLabel.text = location.country
            }
        }
    }
}
