//
//  Page.swift
//  Hayase
//

import UIKit

// MARK: - HTabBar

final class HTabBar: UIView {
    var onChange: ((Int) -> Void)?
    var selectedIndex: Int = 0 { didSet { updateSelection() } }
    var accentColor: UIColor = UIColor(white: 0.98, alpha: 1) { didSet { updateSelection() } }

    var isVertical: Bool = true {
        didSet {
            guard oldValue != isVertical else { return }
            applyOrientation()
        }
    }

    private let stack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 4
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    private var buttons: [UIButton] = []

    private var horizontalHeightConstraint: NSLayoutConstraint?
    private var stackHeightConstraint: NSLayoutConstraint?

    init(titles: [String]) {
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        layer.cornerRadius = 8
        clipsToBounds = true

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        for (i, title) in titles.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 32, bottom: 4, right: 32)
            btn.layer.cornerRadius = 6
            btn.clipsToBounds = true
            btn.tag = i
            btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(btn)
            buttons.append(btn)
        }
        updateSelection()
        applyOrientation()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        if isVertical {
            let maxButtonWidth = buttons.reduce(CGFloat(0)) { max($0, $1.intrinsicContentSize.width) }
            let totalButtonHeight = buttons.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.height }
            let totalSpacing = CGFloat(max(buttons.count - 1, 0)) * stack.spacing
            let width = maxButtonWidth + 8
            let height = totalButtonHeight + totalSpacing + 8
            return CGSize(width: width, height: height)
        } else {
            let totalButtonWidth = buttons.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width }
            let totalSpacing = CGFloat(max(buttons.count - 1, 0)) * stack.spacing
            let width = totalButtonWidth + totalSpacing + 8
            return CGSize(width: width, height: UIView.noIntrinsicMetric)
        }
    }

    @objc private func tabTapped(_ sender: UIButton) {
        selectedIndex = sender.tag
        onChange?(sender.tag)
    }

    private func updateSelection() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        accentColor.getRed(&r, green: &g, blue: &b, alpha: nil)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let contrastColor: UIColor = luminance > 0.5 ? UIColor(white: 0.04, alpha: 1) : .white
        for (i, btn) in buttons.enumerated() {
            if i == selectedIndex {
                btn.backgroundColor = accentColor
                btn.setTitleColor(contrastColor, for: .normal)
                btn.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
            } else {
                btn.backgroundColor = .clear
                btn.setTitleColor(UIColor(white: 0.649, alpha: 1), for: .normal)
                btn.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
            }
        }
    }

    private func applyOrientation() {
        if isVertical {
            stack.axis = .vertical
            stack.spacing = 4
            horizontalHeightConstraint?.isActive = false
            stackHeightConstraint?.isActive = false
        } else {
            stack.axis = .horizontal
            stack.spacing = 0
            if horizontalHeightConstraint == nil {
                horizontalHeightConstraint = heightAnchor.constraint(equalToConstant: 36)
            }
            horizontalHeightConstraint?.isActive = true
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}
