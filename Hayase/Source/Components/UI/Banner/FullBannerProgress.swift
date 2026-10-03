//
//  FullBannerProgress.swift
//  Hayase
//
//  Mirrors: the row of progress badges at the bottom of interface
//  components/ui/banner/full-banner.svelte
//
//      <div class='flex w-full justify-center flex-nowrap overflow-clip'>
//        <div class='pt-2 pb-4' on:click={() => setCurrent(i)}>
//          <div class='bg-primary/20 mr-2 progress-badge overflow-clip rounded' style='height: 4px'
//               style:width={active ? '3rem' : '1.5rem'}>
//            <div class='progress-content h-full w-full' class:bg-custom={active} on:animationend=… />
//
//  `.progress-badge { transition: width .7s ease }`, and the active one runs
//  `animation: fill 15s linear`, which slides its content in from -100%.
//

import UIKit

final class FullBannerProgressView: UIView, CAAnimationDelegate {
    /// `animation: fill 15s linear`
    static let fillDuration: TimeInterval = 15
    private static let animationKey = "fillProgress"
    private static let activeWidth: CGFloat = 48     // 3rem
    private static let inactiveWidth: CGFloat = 24   // 1.5rem

    /// A badge was clicked.
    var onSelect: ((Int) -> Void)?
    /// The fill of the active badge ran to its end (`animationend`).
    var onFinished: (() -> Void)?

    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var slots: [ProgressSlot] = []
    private(set) var activeIndex = 0
    private var color: UIColor = .white
    /// Counts the fills that were started, so one that was cut short is not taken for a finished one.
    private var generation = 0
    /// `group-hover/banner`: while a pointer is over the banner the fill is held, shown full.
    private var isPointerOver = false
    /// How far the active badge had filled when the pointer arrived.
    private var frozenProgress: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true   // overflow-clip
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: Content

    /// Builds the badges again, `activeIndex` being the one that fills. Nothing slides: a new
    /// banner comes with its badges in place.
    func configure(count: Int, activeIndex: Int, color: UIColor) {
        slots.forEach { $0.removeFromSuperview() }
        slots = (0..<count).map { index -> ProgressSlot in
            let slot = ProgressSlot()
            slot.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(slotTapped(_:))))
            slot.tag = index
            stack.addArrangedSubview(slot)
            return slot
        }
        self.activeIndex = activeIndex
        self.color = color
        apply(animated: false)
    }

    /// Moves the fill to another badge, which widens as the old one narrows.
    func setActive(_ index: Int, color: UIColor, animated: Bool = true) {
        activeIndex = index
        self.color = color
        apply(animated: animated)
    }

    /// The colour of the media, which the fill takes (`bg-custom`).
    func setColor(_ color: UIColor) {
        self.color = color
        slots[safe: activeIndex]?.fill.backgroundColor = color
    }

    private func apply(animated: Bool) {
        let slides = animated && bounds.width > 0
        if slides {
            // Everything else the banner has changed is laid out first, outside the animation below:
            // that one is for the badges alone, and anything laid out inside it would slide, too.
            UIView.performWithoutAnimation {
                superview?.layoutIfNeeded()
            }
        }
        generation += 1
        for (index, slot) in slots.enumerated() {
            let active = index == activeIndex
            slot.barWidth = active ? Self.activeWidth : Self.inactiveWidth
            slot.fill.layer.removeAnimation(forKey: Self.animationKey)
            slot.fill.backgroundColor = active ? color : .clear
        }
        if let fill = slots[safe: activeIndex]?.fill {
            startFill(fill, from: 0)
        }
        // transition: width .7s ease. Nothing to animate from until the row has been laid out.
        guard slides else {
            layoutIfNeeded()
            return
        }
        UIViewPropertyAnimator(duration: 0.7,
                               controlPoint1: CGPoint(x: 0.25, y: 0.1),
                               controlPoint2: CGPoint(x: 0.25, y: 1)) {
            self.layoutIfNeeded()
        }.startAnimation()
    }

    @objc private func slotTapped(_ recognizer: UITapGestureRecognizer) {
        guard let index = recognizer.view?.tag, index != activeIndex else { return }
        onSelect?(index)
    }

    // MARK: Fill

    /// The interface slides the fill in from -100% of its own width, so it always covers the
    /// elapsed fraction of the badge, even while the badge is still widening. Scaling from the
    /// leading edge is the same picture.
    private func startFill(_ fill: UIView, from progress: CGFloat) {
        guard window != nil else { return }
        guard !isPointerOver else {
            frozenProgress = progress
            return
        }
        let animation = CABasicAnimation(keyPath: "transform.scale.x")
        animation.fromValue = progress
        animation.toValue = 1
        animation.duration = Self.fillDuration * Double(1 - progress)
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        animation.delegate = self
        animation.setValue(generation, forKey: "generation")
        fill.layer.add(animation, forKey: Self.animationKey)
    }

    /// The pointer over the banner freezes the rotation with the active badge shown full;
    /// moving off lets it carry on from where it stopped.
    func setPointerOver(_ over: Bool) {
        guard let fill = slots[safe: activeIndex]?.fill else { return }
        if over {
            isPointerOver = true
            if fill.layer.animation(forKey: Self.animationKey) != nil {
                frozenProgress = (fill.layer.presentation()?.value(forKeyPath: "transform.scale.x") as? CGFloat) ?? 0
                generation += 1   // the removal below must not count as a finished fill
                fill.layer.removeAnimation(forKey: Self.animationKey)
            }
        } else {
            isPointerOver = false
            let progress = frozenProgress ?? 0
            frozenProgress = nil
            startFill(fill, from: progress)
        }
    }

    func animationDidStop(_ animation: CAAnimation, finished: Bool) {
        guard finished, window != nil, slots.count > 1,
              animation.value(forKey: "generation") as? Int == generation else { return }
        onFinished?()
    }

    // MARK: Lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !slots.isEmpty else { return }
        apply(animated: false)
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        guard newWindow == nil else { return }
        generation += 1
        slots.forEach { $0.fill.layer.removeAnimation(forKey: Self.animationKey) }
    }

    /// Takes the fills off the badges for good, as when the cell is reused.
    func reset() {
        generation += 1
        isPointerOver = false
        frozenProgress = nil
        slots.forEach {
            $0.fill.layer.removeAnimation(forKey: Self.animationKey)
            $0.removeFromSuperview()
        }
        slots = []
    }
}

// MARK: - ProgressSlot

/// One `pt-2 pb-4` wrapper with its `progress-badge`. The badge is 4pt tall and carries `mr-2`,
/// which the wrapper, as wide as its content, includes: all of it is clickable.
private final class ProgressSlot: UIView {
    let fill = UIView()
    private let track = UIView()
    private var widthConstraint: NSLayoutConstraint!

    var barWidth: CGFloat = 24 {
        didSet { widthConstraint.constant = barWidth + 8 }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        track.translatesAutoresizingMaskIntoConstraints = false
        track.backgroundColor = UIColor.HayaseTheme.primary.withAlphaComponent(0.2)   // bg-primary/20
        track.layer.cornerRadius = 2                                                    // rounded, on 4pt
        track.clipsToBounds = true
        addSubview(track)
        // The fill is laid out by hand and anchored at its leading edge, because Auto Layout positions
        // a view as if it were anchored at its centre; with a moved anchor it puts the fill half a
        // badge too far left or right.
        fill.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        track.addSubview(fill)

        widthConstraint = widthAnchor.constraint(equalToConstant: barWidth + 8)
        NSLayoutConstraint.activate([
            widthConstraint,
            heightAnchor.constraint(equalToConstant: 28),                          // pt-2 + 4 + pb-4
            track.topAnchor.constraint(equalTo: topAnchor, constant: 8),           // pt-2
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), // mr-2
            track.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fill.bounds = CGRect(origin: .zero, size: track.bounds.size)
        fill.layer.position = CGPoint(x: 0, y: track.bounds.height / 2)
    }
}
