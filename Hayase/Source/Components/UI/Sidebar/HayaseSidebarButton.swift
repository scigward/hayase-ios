//
//  HayaseSidebarButton.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/lib/components/ui/sidebar/SidebarButton.svelte
//

import UIKit

// MARK: - HayaseSidebarButton

final class HayaseSidebarButton: UIButton {
    enum SidebarSize {
        case desktop
        case mobile
    }

    private static let primaryColor = UIColor.HayaseTheme.primary
    private static let primaryForeground = UIColor.HayaseTheme.primaryForeground
    private static let donateColor = UIColor(red: 250/255, green: 104/255, blue: 182/255, alpha: 1)

    private let route: HayaseSidebarRoute?
    private let sizeMode: SidebarSize
    private let activeBackground = UIView()
    private let iconView = UIImageView()
    private let dotView = UIView()
    private var iconImage: UIImage?
    private var iconRenderingMode: UIImage.RenderingMode = .alwaysTemplate
    private var iconSizeConstraint: NSLayoutConstraint?
    private var iconCenterXConstraint: NSLayoutConstraint?
    private(set) var isActiveRoute = false

    var onPress: (() -> Void)?

    init(route: HayaseSidebarRoute?, size: SidebarSize) {
        self.route = route
        self.sizeMode = size
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        self.route = nil
        self.sizeMode = .desktop
        super.init(coder: coder)
        setup()
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1,
                           delay: 0,
                           options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.98, y: 0.98)  // app.css :active scale(.98)
                    : .identity
            }
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        tintColor = tintForInactiveState()
        layer.cornerRadius = sizeMode == .mobile ? 6 : 6
        clipsToBounds = false
        adjustsImageWhenHighlighted = false
        accessibilityLabel = route?.accessibilityTitle

        activeBackground.translatesAutoresizingMaskIntoConstraints = false
        activeBackground.backgroundColor = Self.primaryColor
        activeBackground.layer.cornerRadius = 6
        activeBackground.isUserInteractionEnabled = false
        activeBackground.alpha = 0
        insertSubview(activeBackground, at: 0)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = tintColor
        iconView.isUserInteractionEnabled = false
        if route == .donate {
            iconView.layer.shadowColor = Self.donateColor.cgColor
            iconView.layer.shadowOpacity = 0.9
            iconView.layer.shadowRadius = 8
            iconView.layer.shadowOffset = .zero
        }
        addSubview(iconView)

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.backgroundColor = UIColor(red: 0.22, green: 0.82, blue: 0.34, alpha: 1)
        dotView.layer.cornerRadius = 4
        dotView.isHidden = true
        dotView.isUserInteractionEnabled = false
        addSubview(dotView)

        // Desktop mirrors SidebarButton.svelte: default h-9, md:w-12,
        // md:pl-4, px-2. That makes the 18pt icon sit 4pt right of
        // geometric center. Mobile mirrors icon-lg exactly.
        let side: CGFloat = sizeMode == .mobile ? 48 : 36
        let width: CGFloat = 48
        let iconSize = iconView.widthAnchor.constraint(equalToConstant: 18)
        let iconCenterX = iconView.centerXAnchor.constraint(equalTo: centerXAnchor,
                                                            constant: sizeMode == .desktop ? 4 : 0)
        iconSizeConstraint = iconSize
        iconCenterXConstraint = iconCenterX
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: side),
            activeBackground.topAnchor.constraint(equalTo: topAnchor),
            activeBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            activeBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            activeBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconCenterX,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconSize,
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),
            dotView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            dotView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])

        if sizeMode == .desktop {
            activeBackground.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }

        iconImage = route == .donate
            ? UIImage.hayaseFilledIcon("heart", pointSize: 18)
            : route.map { UIImage.hayaseIcon($0.iconName) } ?? UIImage.hayaseIcon("circle")
        setSidebarImage(iconImage, pointSize: 18, renderingMode: .alwaysTemplate)
        setImage(nil, for: .normal)
        imageEdgeInsets = .zero

        addTarget(self, action: #selector(didTap), for: .touchUpInside)
    }

    var activePill: UIView { activeBackground }

    func setActive(_ active: Bool, animated: Bool) {
        isActiveRoute = active
        activeBackground.alpha = active ? 1 : 0
        let changes = {
            self.tintColor = active ? Self.primaryForeground : self.tintForInactiveState()
            self.iconView.tintColor = self.tintColor
            self.applyIconImage()
        }
        guard animated else {
            changes()
            return
        }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.3  // duration-300
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)  // transition-colors
        iconView.layer.add(fade, forKey: "hayaseTint")
        UIViewPropertyAnimator(duration: 0.3, controlPoint1: CGPoint(x: 0.4, y: 0), controlPoint2: CGPoint(x: 0.2, y: 1), animations: changes).startAnimation()
    }

    func setStatusDotVisible(_ visible: Bool) {
        dotView.isHidden = !visible
    }

    func setSidebarImage(_ image: UIImage?, pointSize: CGFloat, renderingMode: UIImage.RenderingMode) {
        iconRenderingMode = renderingMode
        iconImage = image?.withRenderingMode(renderingMode)
        iconSizeConstraint?.constant = pointSize
        applyIconImage()
    }

    private func applyIconImage() {
        if iconRenderingMode == .alwaysOriginal {
            iconView.image = iconImage
        } else {
            let tint = isActiveRoute ? Self.primaryForeground : tintForInactiveState()
            iconView.image = iconImage?.withTintColor(tint, renderingMode: .alwaysOriginal)
            iconView.tintColor = tintColor
        }
    }

    private func tintForInactiveState() -> UIColor {
        if route == .donate {
            return Self.donateColor
        }
        return UIColor.HayaseTheme.foreground
    }

    @objc private func didTap() {
        onPress?()
    }
}
