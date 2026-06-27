//
//  ColumnHeader.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

enum ColumnHeader {
    static func make(columns: [(String, CGFloat?)],
                     sortableColumnIndices: Set<Int> = [],
                     activeColumnIndex: Int? = nil,
                     sortAscending: Bool = true,
                     target: Any? = nil,
                     action: Selector? = nil) -> UIView {
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

        for (index, column) in columns.enumerated() {
            let (title, fixedWidth) = column
            let view: UIView
            if sortableColumnIndices.contains(index), let target, let action {
                let button = UIButton(type: .system)
                button.setTitle(title, for: .normal)
                button.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
                button.titleLabel?.lineBreakMode = .byClipping
                button.titleLabel?.adjustsFontSizeToFitWidth = true
                button.titleLabel?.minimumScaleFactor = 0.8
                button.setTitleColor(activeColumnIndex == index ? TorrentClientStyle.foreground : TorrentClientStyle.mutedForeground, for: .normal)
                button.contentHorizontalAlignment = .left
                button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
                button.tag = index
                button.addTarget(target, action: action, for: .touchUpInside)
                button.accessibilityValue = activeColumnIndex == index ? (sortAscending ? "Ascending" : "Descending") : "Unsorted"
                view = button
            } else {
                let label = UILabel()
                label.text = title
                label.font = .nunito(ofSize: 14, weight: .medium)
                label.textColor = TorrentClientStyle.mutedForeground
                label.lineBreakMode = .byClipping
                label.adjustsFontSizeToFitWidth = true
                label.minimumScaleFactor = 0.8
                view = label
            }

            if let width = fixedWidth {
                view.widthAnchor.constraint(equalToConstant: width).isActive = true
                view.setContentHuggingPriority(.required, for: .horizontal)
                view.setContentCompressionResistancePriority(.required, for: .horizontal)
            } else {
                view.setContentHuggingPriority(.defaultLow, for: .horizontal)
                view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            stack.addArrangedSubview(view)
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
