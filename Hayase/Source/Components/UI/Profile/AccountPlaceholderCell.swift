//
//  AccountPlaceholderCell.swift
//  Hayase
//
//  Mirrors: src/routes/app/settings/accounts/+page.svelte (unwired account card presentation)
//

import UIKit

final class HayaseAccountPlaceholderCell: UITableViewCell {
    static let reuseID = "HayaseAccountPlaceholderCell"

    private let nameLabel = UILabel()
    private let serviceLabel = UILabel()
    private let serviceMark = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        buildLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildLayout()
    }

    private func buildLayout() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        let card = UIView()
        card.layer.cornerRadius = 6
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        let header = UIView()
        header.backgroundColor = UIColor.HayaseTheme.accent
        header.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(header)

        let footer = UIView()
        footer.backgroundColor = UIColor.HayaseTheme.muted
        footer.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(footer)

        nameLabel.text = "Not logged in"
        nameLabel.font = .nunito(ofSize: 14)
        nameLabel.textColor = UIColor.HayaseTheme.foreground
        serviceLabel.font = .nunito(ofSize: 9)
        serviceLabel.textColor = UIColor.HayaseTheme.mutedForeground
        let identity = UIStackView(arrangedSubviews: [nameLabel, serviceLabel])
        identity.axis = .vertical
        identity.spacing = 1
        identity.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(identity)

        serviceMark.font = .nunito(ofSize: 16, weight: .bold)
        serviceMark.textColor = UIColor.HayaseTheme.foreground
        serviceMark.textAlignment = .center
        serviceMark.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(serviceMark)

        let login = UIButton(type: .system)
        login.setTitle("Login", for: .normal)
        login.titleLabel?.font = .nunito(ofSize: 13, weight: .medium)
        login.setTitleColor(UIColor.HayaseTheme.secondaryForeground, for: .normal)
        login.backgroundColor = UIColor.HayaseTheme.secondary
        login.layer.cornerRadius = 6
        login.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        login.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(login)

        let sync = UISwitch()
        sync.onTintColor = UIColor.HayaseTheme.primary
        sync.thumbTintColor = UIColor.HayaseTheme.primaryForeground
        sync.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        let syncLabel = UILabel()
        syncLabel.text = "Enable Sync"
        syncLabel.font = .nunito(ofSize: 13)
        syncLabel.textColor = UIColor.HayaseTheme.foreground
        let syncStack = UIStackView(arrangedSubviews: [sync, syncLabel])
        syncStack.axis = .horizontal
        syncStack.alignment = .center
        syncStack.spacing = 6
        syncStack.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(syncStack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            header.topAnchor.constraint(equalTo: card.topAnchor),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 64),
            footer.topAnchor.constraint(equalTo: header.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 68),
            identity.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            identity.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            serviceMark.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),
            serviceMark.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            serviceMark.widthAnchor.constraint(equalToConstant: 24),
            serviceMark.heightAnchor.constraint(equalToConstant: 24),
            login.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24),
            login.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            syncStack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -24),
            syncStack.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            login.trailingAnchor.constraint(lessThanOrEqualTo: syncStack.leadingAnchor, constant: -8),
        ])
    }

    func configure(service: String) {
        serviceLabel.text = service
        serviceMark.text = String(service.prefix(1))
    }
}
