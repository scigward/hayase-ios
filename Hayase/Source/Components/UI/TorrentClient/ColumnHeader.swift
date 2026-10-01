// Mirrors torrentclient/columnheader.svelte and Table.Head.
import UIKit

enum ColumnHeader {
    static func make(columns: [(String, CGFloat?)],
                     sortableColumnIndices: Set<Int> = [],
                     activeColumnIndex: Int? = nil,
                     sortAscending: Bool = true,
                     target: Any? = nil,
                     action: Selector? = nil,
                     selectAll: Bool? = nil,
                     onSort: ((Int, Bool) -> Void)? = nil) -> UIView {
        let header = UIView()
        header.backgroundColor = TorrentClientStyle.background
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 0
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8),
            // Table.Head's :has([role=checkbox]):pr-0 overrides last:pr-2.
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: selectAll == nil ? -8 : 0),
            stack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        for (index, column) in columns.enumerated() {
            let (title, fixedWidth) = column
            let view: UIView
            if let selected = selectAll, index == columns.count - 1 {
                let checkbox = TorrentClientCheckbox()
                checkbox.isSelected = selected
                checkbox.tag = index
                checkbox.accessibilityLabel = "Select all"
                if let target, let action { checkbox.addTarget(target, action: action, for: .touchUpInside) }
                checkbox.heightAnchor.constraint(equalToConstant: 32).isActive = true
                view = checkbox
            } else if sortableColumnIndices.contains(index) {
                let button = TorrentClientSortHeaderButton()
                button.setTitle(title, for: .normal)
                button.tag = index
                if let onSort { button.onSort = { onSort(index, $0) } }
                else if let target, let action { button.addTarget(target, action: action, for: .touchUpInside) }
                button.heightAnchor.constraint(equalToConstant: 32).isActive = true
                button.accessibilityValue = activeColumnIndex == index
                    ? (sortAscending ? "Ascending" : "Descending") : "Unsorted"
                view = button
            } else {
                let wrapper = UIView()
                let label = TorrentClientLabel()
                label.text = title
                label.font = .nunito(ofSize: 14, weight: .medium)
                label.textColor = TorrentClientStyle.mutedForeground
                label.translatesAutoresizingMaskIntoConstraints = false
                wrapper.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
                    label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
                    label.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
                    wrapper.heightAnchor.constraint(equalToConstant: 32),
                ])
                view = wrapper
            }

            if let width = fixedWidth {
                // Body cells each have px-4; header buttons span that whole area.
                // first:pl-2 / last:pr-2 live outside the button and are above;
                // the checkbox last column has pr-0 instead.
                view.widthAnchor.constraint(equalToConstant: width + 32).isActive = true
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
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
        return header
    }
}

private final class TorrentClientSortHeaderButton: SelectButton {
    var onSort: ((Bool) -> Void)?
    private var popover: TorrentClientSortPopover?

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyGhostVariant()
        restingTint = TorrentClientStyle.mutedForeground
        contentHorizontalAlignment = .left
        contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        titleLabel?.lineBreakMode = .byClipping
        addTarget(self, action: #selector(openSort), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func openSort() {
        guard let onSort else { return }
        if let popover { popover.close(); return }
        let menu = TorrentClientSortPopover(sourceView: self, onSort: onSort)
        menu.onDismiss = { [weak self] in
            self?.restingBackground = .clear
            self?.popover = nil
        }
        popover = menu
        restingBackground = UIColor.HayaseTheme.accent
        menu.show()
    }
}
