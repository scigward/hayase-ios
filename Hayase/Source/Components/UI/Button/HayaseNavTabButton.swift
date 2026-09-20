//
//  HayaseNavTabButton.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/lib/components/SettingsNav.svelte (crossfading bg-primary pill, title transition-colors duration-300) and src/app.css (:active scale)
//

import UIKit

// MARK: - HayaseNavTabButton

final class HayaseNavTabButton: UIButton {
    private let pill = UIView()
    private(set) var isCurrentTab = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        pill.backgroundColor = UIColor.HayaseTheme.primary
        pill.layer.cornerRadius = 6  // rounded-md
        pill.alpha = 0
        pill.isUserInteractionEnabled = false
        pill.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(pill, at: 0)
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: topAnchor),
            pill.leadingAnchor.constraint(equalTo: leadingAnchor),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setTitleColor(UIColor.HayaseTheme.foreground, for: .normal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            guard isHighlighted else {
                transform = .identity
                return
            }
            UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {  // transition: all 0.1s ease-in-out
                self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)  // scale(0.98)
            }
        }
    }

    /// Marks `tag` as the current tab, moving the pill over from the previous one.
    static func select(tag: Int, in buttons: [HayaseNavTabButton], animated: Bool) {
        let previous = buttons.first { $0.isCurrentTab }
        let next = buttons.first { $0.tag == tag }
        for button in buttons {
            button.setCurrent(button.tag == tag, animated: animated)
        }
        guard animated, let previous, let next, previous !== next else { return }
        HayaseCrossfade.send(next.pill, from: previous.pill)
        HayaseCrossfade.receive(previous.pill, to: next.pill)
    }

    private func setCurrent(_ current: Bool, animated: Bool) {
        guard current != isCurrentTab else { return }
        isCurrentTab = current
        pill.alpha = current ? 1 : 0
        if animated, let label = titleLabel {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.3  // duration-300
            fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)  // transition-colors
            label.layer.add(fade, forKey: "hayaseTitleColor")
        }
        setTitleColor(current ? UIColor.HayaseTheme.primaryForeground : UIColor.HayaseTheme.foreground, for: .normal)
    }
}
