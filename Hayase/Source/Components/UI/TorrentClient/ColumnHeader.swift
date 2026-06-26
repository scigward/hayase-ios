//
//  ColumnHeader.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

enum ColumnHeader {
    static func make(columns: [(String, CGFloat?)]) -> UIView {
        let header = UIView()
        header.backgroundColor = TorrentClientStyle.background

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        for (title, fixedWidth) in columns {
            let label = UILabel()
            label.text = title
            label.font = .nunito(ofSize: 12, weight: .medium)
            label.textColor = TorrentClientStyle.mutedForeground
            if let width = fixedWidth {
                label.widthAnchor.constraint(equalToConstant: width).isActive = true
                label.setContentHuggingPriority(.required, for: .horizontal)
                label.setContentCompressionResistancePriority(.required, for: .horizontal)
            } else {
                label.setContentHuggingPriority(.defaultLow, for: .horizontal)
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            stack.addArrangedSubview(label)
        }

        let separator = UIView()
        TorrentClientStyle.configureSeparator(separator)
        separator.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        return header
    }
}
