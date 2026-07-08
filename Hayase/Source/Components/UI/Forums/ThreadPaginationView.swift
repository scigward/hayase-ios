//
//  ThreadPaginationView.swift
//  Hayase
//
//  Native UIKit counterpart for the forum comments pagination row.
//

import UIKit

final class ThreadPaginationView: UIView {
    private let row = UIStackView()
    private let rangeLabel = UILabel()
    private let buttonsRow = UIStackView()
    private var onPageSelected: ((Int) -> Void)?
    private var currentPage = 1
    private var totalPages = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        rangeLabel.font = .nunito(ofSize: 13)
        rangeLabel.textColor = UIColor.HayaseTheme.mutedForeground
        rangeLabel.numberOfLines = 1
        row.addArrangedSubview(rangeLabel)

        row.addArrangedSubview(UIView())

        buttonsRow.axis = .horizontal
        buttonsRow.alignment = .center
        buttonsRow.spacing = 8
        row.addArrangedSubview(buttonsRow)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    func configure(count: Int,
                   perPage: Int,
                   currentPage: Int,
                   onPageSelected: @escaping (Int) -> Void) {
        self.currentPage = currentPage
        self.totalPages = max(1, Int(ceil(Double(count) / Double(perPage))))
        self.onPageSelected = onPageSelected

        let start = count == 0 ? 0 : ((currentPage - 1) * perPage) + 1
        let end = min(currentPage * perPage, count)
        rangeLabel.attributedText = rangeText(start: start, end: end, count: count)

        buttonsRow.arrangedSubviews.forEach { view in
            buttonsRow.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let previousButton = pageIconButton(iconName: "chevron-left", enabled: currentPage > 1)
        previousButton.addTarget(self, action: #selector(previousPage), for: .touchUpInside)
        buttonsRow.addArrangedSubview(previousButton)

        if UIScreen.main.bounds.width >= 768 {
            for item in paginationItems(currentPage: currentPage, totalPages: totalPages) {
                switch item.type {
                case .ellipsis:
                    buttonsRow.addArrangedSubview(ellipsisLabel())
                case .page:
                    let button = pageButton(title: "\(item.page)", selected: item.page == currentPage)
                    button.tag = item.page
                    button.addTarget(self, action: #selector(selectPage(_:)), for: .touchUpInside)
                    buttonsRow.addArrangedSubview(button)
                }
            }
        }

        let nextButton = pageIconButton(iconName: "chevron-right", enabled: currentPage < totalPages)
        nextButton.addTarget(self, action: #selector(nextPage), for: .touchUpInside)
        buttonsRow.addArrangedSubview(nextButton)
    }

    private func rangeText(start: Int, end: Int, count: Int) -> NSAttributedString {
        let text = "Showing \(start) to \(end) of \(count) comments"
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: UIFont.nunito(ofSize: 13),
                .foregroundColor: UIColor.HayaseTheme.mutedForeground,
            ])
        for value in ["\(start)", "\(end)", "\(count)"] {
            let range = (text as NSString).range(of: value)
            if range.location != NSNotFound {
                attributed.addAttribute(.font, value: UIFont.nunito(ofSize: 13, weight: .bold), range: range)
            }
        }
        return attributed
    }

    private func pageIconButton(iconName: String, enabled: Bool) -> UIButton {
        let button = Button(iconName: iconName, pointSize: 16)
        button.backgroundColor = .clear
        button.isEnabled = enabled
        button.alpha = enabled ? 1 : 0.5
        return button
    }

    private func pageButton(title: String, selected: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .nunito(ofSize: 14)
        button.setTitleColor(UIColor.HayaseTheme.foreground, for: .normal)
        button.backgroundColor = selected ? UIColor.HayaseTheme.accent : .clear
        button.layer.cornerRadius = 6
        if selected {
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36),
        ])
        return button
    }

    private func ellipsisLabel() -> UILabel {
        let label = UILabel()
        label.text = "..."
        label.font = .nunito(ofSize: 14)
        label.textColor = UIColor.HayaseTheme.foreground
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 36),
            label.heightAnchor.constraint(equalToConstant: 36),
        ])
        return label
    }

    private enum ItemType {
        case page
        case ellipsis
    }

    private struct PaginationItem {
        let page: Int
        let type: ItemType
    }

    private func paginationItems(currentPage: Int, totalPages: Int) -> [PaginationItem] {
        let siblingCount = 1
        let edgeSize = 4 * siblingCount
        let startPage = max(1, totalPages - currentPage < edgeSize ? totalPages - edgeSize : currentPage - siblingCount)
        let endPage = min(totalPages, currentPage < edgeSize ? 1 + edgeSize : currentPage + siblingCount)
        var items: [PaginationItem] = []

        if startPage > 1 {
            items.append(PaginationItem(page: 1, type: .page))
            if startPage > 2 {
                items.append(PaginationItem(page: startPage - 1, type: .ellipsis))
            }
        }

        if startPage <= endPage {
            for page in startPage...endPage {
                items.append(PaginationItem(page: page, type: .page))
            }
        }

        if endPage < totalPages {
            if endPage < totalPages - 1 {
                items.append(PaginationItem(page: endPage + 1, type: .ellipsis))
            }
            items.append(PaginationItem(page: totalPages, type: .page))
        }
        return items
    }

    @objc private func previousPage() {
        onPageSelected?(max(1, currentPage - 1))
    }

    @objc private func nextPage() {
        onPageSelected?(min(totalPages, currentPage + 1))
    }

    @objc private func selectPage(_ sender: UIButton) {
        onPageSelected?(sender.tag)
    }
}

final class ThreadCommentSkeletonView: UIView {
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = hayaseCardBackground
        layer.cornerRadius = 6

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        stack.addArrangedSubview(bar(width: 150, height: 8, bottom: 0))
        stack.addArrangedSubview(bar(width: 112, height: 6, bottom: 0))
        stack.addArrangedSubview(bar(width: 80, height: 6, bottom: 0))
        stack.addArrangedSubview(UIView())
        stack.addArrangedSubview(bar(width: 96, height: 8, bottom: 0))

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 112),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
        ])
    }

    private func bar(width: CGFloat, height: CGFloat, bottom: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.HayaseTheme.primary.withAlphaComponent(0.05)
        view.layer.cornerRadius = height / 2
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height),
        ])
        return view
    }
}
