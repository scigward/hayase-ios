//
//  SidebarButton.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/lib/components/ui/sidebar/SidebarButton.svelte, and the buttons in sidebarlist.svelte
//

import UIKit

// MARK: - HayaseSidebarButton

/// A sidebar button: the `ghost` Button that becomes `default` (with the crossfading pill) while
/// its route is open, and plays its animated icon (`animated-icon`) whenever it is hovered, focused
/// or pressed. `route` is nil for the menu button of the narrow layout.
final class HayaseSidebarButton: UIButton, ActiveElementObserver {
    enum SidebarSize {
        case desktop
        case mobile
    }

    private static let donateColor = UIColor(red: 250/255, green: 104/255, blue: 182/255, alpha: 1)

    private let route: HayaseSidebarRoute?
    private let sizeMode: SidebarSize
    private let activeBackground = UIView()
    private let iconView = UIImageView()
    private let animatedIcon: LayeredIconView?
    private let dotView = UIView()
    private var iconImage: UIImage?
    private var iconSizeConstraint: NSLayoutConstraint?
    private(set) var isActiveRoute = false
    /// Tailwind's `select:`: hovered, focus-visible or active.
    private var isSelectedState = false
    private var isPointerOver = false

    var onPress: (() -> Void)?

    /// `transition-colors` with `duration-300`; the settings button has `!transition-none`, and the
    /// menu button keeps the plain 150ms.
    var colorDuration: TimeInterval

    init(route: HayaseSidebarRoute?, size: SidebarSize) {
        self.route = route
        self.sizeMode = size
        self.animatedIcon = Self.iconKind(for: route).map { LayeredIconView(kind: $0) }
        self.colorDuration = route == .settings ? 0 : 0.3
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        self.route = nil
        self.sizeMode = .desktop
        self.animatedIcon = nil
        self.colorDuration = 0.3
        super.init(coder: coder)
        setup()
    }

    /// The icon each route has in sidebarlist.svelte; the profile one only while nobody is signed in.
    private static func iconKind(for route: HayaseSidebarRoute?) -> LayeredIconView.Kind? {
        switch route {
        case .home: return .home
        case .search: return .search
        case .schedule: return .calendar
        case .w2g: return .users
        case .chat: return .messages
        case .client: return .download
        case .settings: return .bolt
        case .profile: return .login
        case .donate, .none: return nil
        }
    }

    override var isHighlighted: Bool {
        didSet {
            updateSelectState()
            let transform = isHighlighted
                ? CGAffineTransform(scaleX: 0.98, y: 0.98)  // app.css :active scale(.98)
                : .identity
            guard route != .settings else {   // `!transition-none`: the press lands at once
                self.transform = transform
                return
            }
            UIView.animate(withDuration: 0.1,
                           delay: 0,
                           options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
                self.transform = transform
            }
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        layer.cornerRadius = 6   // rounded-md
        if sizeMode == .desktop {
            // md:rounded-l-none
            layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }
        // `contain-strict` on the donate button clips what its heart's glow spreads past the box
        clipsToBounds = route == .donate
        adjustsImageWhenHighlighted = false
        accessibilityLabel = route?.accessibilityTitle
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))

        activeBackground.translatesAutoresizingMaskIntoConstraints = false
        activeBackground.backgroundColor = UIColor.HayaseTheme.primary
        activeBackground.layer.cornerRadius = 6
        activeBackground.isUserInteractionEnabled = false
        activeBackground.alpha = 0
        insertSubview(activeBackground, at: 0)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        if route == .donate {
            // drop-shadow-[0_0_0.55rem_#fa68b6aa]
            iconView.layer.shadowColor = Self.donateColor.cgColor
            iconView.layer.shadowOpacity = 0xaa / 255
            iconView.layer.shadowRadius = 8.8
            iconView.layer.shadowOffset = .zero
        }
        addSubview(iconView)

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.backgroundColor = ScheduleStatusColor.color(for: "COMPLETED")   // StatusDot variant='COMPLETED'
        dotView.layer.cornerRadius = 4.4
        dotView.isHidden = true
        dotView.isUserInteractionEnabled = false
        addSubview(dotView)

        // Desktop mirrors SidebarButton.svelte: default h-9, md:w-12,
        // md:pl-4, px-2. That makes the 18pt icon sit 4pt right of
        // geometric center. Mobile mirrors icon-lg exactly.
        let side: CGFloat = sizeMode == .mobile ? 48 : 36
        let width: CGFloat = 48
        let centerOffset: CGFloat = sizeMode == .desktop ? 4 : 0
        let iconSize = iconView.widthAnchor.constraint(equalToConstant: 18)
        iconSizeConstraint = iconSize
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: side),
            activeBackground.topAnchor.constraint(equalTo: topAnchor),
            activeBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            activeBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            activeBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor, constant: centerOffset),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconSize,
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 8.8),   // size-[0.55rem]
            dotView.heightAnchor.constraint(equalToConstant: 8.8),
            dotView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            dotView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])

        if sizeMode == .desktop {
            activeBackground.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }

        if let animatedIcon {
            animatedIcon.translatesAutoresizingMaskIntoConstraints = false
            insertSubview(animatedIcon, belowSubview: dotView)
            NSLayoutConstraint.activate([
                animatedIcon.centerXAnchor.constraint(equalTo: centerXAnchor, constant: centerOffset),
                animatedIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
                animatedIcon.widthAnchor.constraint(equalToConstant: 18),
                animatedIcon.heightAnchor.constraint(equalToConstant: 18),
            ])
            iconView.isHidden = true
        } else if route == .donate {
            setSidebarImage(UIImage.hayaseFilledIcon("heart", pointSize: 18), pointSize: 18, renderingMode: .alwaysTemplate)
        }

        applyState(animated: false)
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
    }

    var activePill: UIView { activeBackground }

    func setActive(_ active: Bool, animated: Bool) {
        isActiveRoute = active
        activeBackground.alpha = active ? 1 : 0
        applyState(animated: animated)
    }

    func setStatusDotVisible(_ visible: Bool) {
        dotView.isHidden = !visible
    }

    /// An image in the icon's place: the menu button's menu and cross, the donate heart.
    func setSidebarImage(_ image: UIImage?, pointSize: CGFloat, renderingMode: UIImage.RenderingMode) {
        iconImage = image?.withRenderingMode(renderingMode)
        iconSizeConstraint?.constant = pointSize
        iconView.image = iconImage
        iconView.isHidden = false
        animatedIcon?.isHidden = true
    }

    /// The profile button: the viewer's avatar (`size-6 rounded-md`), or the login icon without one.
    func setAvatar(_ avatar: UIImage?) {
        guard route == .profile else { return }
        iconView.image = avatar?.withRenderingMode(.alwaysOriginal)
        iconSizeConstraint?.constant = 24
        iconView.isHidden = avatar == nil
        animatedIcon?.isHidden = avatar != nil
    }

    /// The donate heart's `animate-[hearbeat_1s_ease-in-out_infinite_alternate]`, which runs
    /// while the app is active.
    func setHeartbeat(_ active: Bool) {
        guard route == .donate else { return }
        guard active else {
            iconView.layer.removeAnimation(forKey: "heartbeat")
            return
        }
        guard iconView.layer.animation(forKey: "heartbeat") == nil else { return }
        let beat = CABasicAnimation(keyPath: "transform.scale")
        beat.fromValue = 1
        beat.toValue = 0.85
        beat.duration = 1
        beat.autoreverses = true
        beat.repeatCount = .infinity
        beat.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        iconView.layer.add(beat, forKey: "heartbeat")
    }

    // MARK: - Select state

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        let hovering = recognizer.state == .began || recognizer.state == .changed
        isPointerOver = hovering
        updateSelectState()
        if !hovering && !isHighlighted {
            animatedIcon?.cancelAnimations()
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        updateSelectState()
    }

    func activeElementDidChange() {
        updateSelectState()
    }

    private func updateSelectState() {
        let selected = isEnabled && (isHighlighted || isPointerOver || isActiveElement)
        guard selected != isSelectedState else { return }
        isSelectedState = selected
        applyState(animated: true)
        animatedIcon?.selectionChanged(selected)
    }

    /// The colours of the button's variant: `ghost` (select:bg-secondary-foreground/20
    /// select:text-accent-foreground), or `default` while its route is open (select:bg-primary/60,
    /// with the pill at select:bg-primary/70). The donate heart stays pink and clear.
    private func applyState(animated: Bool) {
        let selected = isSelectedState
        let background: UIColor
        let tint: UIColor
        if route == .donate {
            background = .clear   // select:!bg-transparent
            tint = Self.donateColor
        } else if isActiveRoute {
            background = selected ? UIColor.HayaseTheme.primary.withAlphaComponent(0.6) : .clear
            tint = UIColor.HayaseTheme.primaryForeground
        } else {
            background = selected ? UIColor.HayaseTheme.secondaryForeground.withAlphaComponent(0.2) : .clear
            tint = selected ? UIColor.HayaseTheme.accentForeground : UIColor.HayaseTheme.foreground
        }
        activeBackground.backgroundColor = selected
            ? UIColor.HayaseTheme.primary.withAlphaComponent(0.7)
            : UIColor.HayaseTheme.primary
        tintColor = tint
        iconView.tintColor = tint

        let duration = animated ? colorDuration : 0
        animatedIcon?.setTint(tint, duration: duration)
        guard duration > 0, window != nil else {
            backgroundColor = background
            return
        }
        UIViewPropertyAnimator(duration: duration,
                               controlPoint1: CGPoint(x: 0.4, y: 0),
                               controlPoint2: CGPoint(x: 0.2, y: 1)) {  // Tailwind transition-colors
            self.backgroundColor = background
        }.startAnimation()
    }

    @objc private func didTap() {
        onPress?()
    }
}
