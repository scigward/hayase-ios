//
//  Flags.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

final class PeerFlagsCellContent: UIView {
    private var representedFlags: [TorrentClientPeerRow.Flag]?
    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 22)
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
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(flags: [TorrentClientPeerRow.Flag]) {
        guard representedFlags != flags else { return }
        representedFlags = flags
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for flag in flags {
            stack.addArrangedSubview(Self.badge(for: flag))
        }
    }

    private static func badge(for flag: TorrentClientPeerRow.Flag) -> UIView {
        let container = PeerFlagBadge(text: label(for: flag))
        // Badge secondary + p-1: 12px icon, 4px padding and 1px border.
        container.backgroundColor = UIColor.HayaseTheme.secondary
        container.layer.cornerRadius = 6
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.clear.cgColor
        container.clipsToBounds = true
        container.accessibilityLabel = label(for: flag)

        let imageView = UIImageView(image: UIImage.hayaseIcon(iconName(for: flag), pointSize: 12))
        imageView.tintColor = tint(for: flag)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 22),
            container.heightAnchor.constraint(equalToConstant: 22),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
        ])
        return container
    }

    private static func iconName(for flag: TorrentClientPeerRow.Flag) -> String {
        switch flag {
        case .incoming: return "wifi"
        case .outgoing: return "wifi-off"
        case .utp: return "shield"
        case .encrypted: return "lock"
        }
    }

    private static func tint(for flag: TorrentClientPeerRow.Flag) -> UIColor {
        switch flag {
        case .incoming: return TorrentClientStyle.green500
        case .outgoing: return TorrentClientStyle.blue500
        case .utp: return TorrentClientStyle.purple500
        case .encrypted: return TorrentClientStyle.yellow500
        }
    }

    private static func label(for flag: TorrentClientPeerRow.Flag) -> String {
        switch flag {
        case .incoming: return "Incoming"
        case .outgoing: return "Outgoing"
        case .utp: return "uTP"
        case .encrypted: return "Encrypted"
        }
    }
}

/// Tooltip.Trigger/Content from the interface; keep the lightweight hover
/// label in the same window instead of presenting a native popover.
private final class PeerFlagBadge: UIControl {
    private let tooltipText: String
    private var tooltip: UIView?
    private var pendingTooltip: DispatchWorkItem?

    init(text: String) {
        tooltipText = text
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = text
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
    }

    required init?(coder: NSCoder) { return nil }
    override var canBecomeFocused: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { hideTooltip() }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                 with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        isFocused ? showTooltip() : hideTooltip()
    }

    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        if gesture.state == .began {
            let work = DispatchWorkItem { [weak self] in self?.showTooltip() }
            pendingTooltip?.cancel()
            pendingTooltip = work
            // Tooltip.Root's default hover delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        } else if gesture.state == .ended || gesture.state == .cancelled {
            hideTooltip()
        }
    }

    private func showTooltip() {
        pendingTooltip?.cancel()
        pendingTooltip = nil
        guard tooltip == nil, let window else { return }
        let label = TorrentClientLabel()
        label.lineHeight = 16
        label.text = tooltipText
        label.font = .nunito(ofSize: 12, weight: .semibold)
        label.textColor = UIColor.HayaseTheme.primaryForeground
        label.textAlignment = .center
        let width = ceil(label.intrinsicContentSize.width) + 24
        let height: CGFloat = 28 // text-xs leading-4 + py-1.5.
        let anchor = convert(bounds, to: window)
        let x = min(max(4, anchor.midX - width / 2), window.bounds.width - width - 4)
        let y = anchor.minY >= height + 8 ? anchor.minY - height - 4 : anchor.maxY + 4
        let content = UIView(frame: CGRect(x: x, y: y, width: width, height: height))
        content.backgroundColor = UIColor.HayaseTheme.primary
        content.layer.cornerRadius = 6
        content.clipsToBounds = true
        content.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            label.heightAnchor.constraint(equalToConstant: 16),
        ])
        window.addSubview(content)
        tooltip = content
        content.alpha = 0
        content.transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.95, y: 0.95)
        let animation = UIViewPropertyAnimator(duration: 0.15, timingParameters:
            UICubicTimingParameters(controlPoint1: CGPoint(x: 1.0 / 3.0, y: 1),
                                    controlPoint2: CGPoint(x: 2.0 / 3.0, y: 1)))
        animation.addAnimations { content.alpha = 1; content.transform = .identity }
        animation.startAnimation()
    }

    private func hideTooltip() {
        pendingTooltip?.cancel()
        pendingTooltip = nil
        guard let tooltip else { return }
        self.tooltip = nil
        UIView.animate(withDuration: 0.15, animations: {
            tooltip.alpha = 0
            tooltip.transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.95, y: 0.95)
        }, completion: { _ in tooltip.removeFromSuperview() })
    }
}
