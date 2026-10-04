//
//  TooltipContent.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/tooltip/tooltip-content.svelte on bits-ui's Tooltip
//
//    bg-primary text-primary-foreground z-50 overflow-hidden rounded-md px-3 py-1.5 text-xs
//
//  The content opens above its trigger, centred, 4pt away (`sideOffset`), once the pointer has been
//  over the trigger for 700ms (`openDelay`), and goes with the pointer. It flies in over 150ms with
//  `flyAndScale` (8pt up, from 95%) and cubicOut. A touch has no hover, so only an iPad pointer opens it.
//

import UIKit
import ObjectiveC

private var tooltipKey = 0

extension UIView {
    /// `<Tooltip.Root><Tooltip.Trigger>…</Tooltip.Trigger><Tooltip.Content>text</Tooltip.Content></Tooltip.Root>`
    func attachTooltip(_ text: String, maximumWidth: CGFloat? = nil) {
        let tooltip = Tooltip(trigger: self, text: text, maximumWidth: maximumWidth)
        objc_setAssociatedObject(self, &tooltipKey, tooltip, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

final class Tooltip: NSObject {
    private static let openDelay: TimeInterval = 0.7 // bits-ui's 700ms, not 700 seconds
    private static let sideOffset: CGFloat = 4
    private static let transition: TimeInterval = 0.15
    /// svelte/easing cubicOut
    private static let cubicOut = (CGPoint(x: 0.33, y: 1), CGPoint(x: 0.68, y: 1))

    private weak var trigger: UIView?
    private let text: String
    private let maximumWidth: CGFloat?
    private var pendingOpen: DispatchWorkItem?
    private var bubble: TooltipBubble?
    private var watchdog: Timer?
    private var isHovering = false
    private var hoverRecognizer: UIHoverGestureRecognizer?

    init(trigger: UIView, text: String, maximumWidth: CGFloat? = nil) {
        self.trigger = trigger
        self.text = text
        self.maximumWidth = maximumWidth
        super.init()
        let recognizer = UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:)))
        hoverRecognizer = recognizer
        trigger.addGestureRecognizer(recognizer)
    }

    deinit {
        if let hoverRecognizer { trigger?.removeGestureRecognizer(hoverRecognizer) }
        pendingOpen?.cancel()
        watchdog?.invalidate()
        bubble?.removeFromSuperview()
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began:
            isHovering = true
            scheduleOpen()
        case .ended, .cancelled, .failed:
            isHovering = false
            close()
        default:
            break
        }
    }

    private func scheduleOpen() {
        pendingOpen?.cancel()
        guard bubble == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.open() }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.openDelay, execute: work)
    }

    private func open() {
        guard isHovering, bubble == nil, let trigger, trigger.window != nil,
              let host = trigger.window?.rootViewController?.view else { return }
        let bubble = TooltipBubble(text: text, maximumWidth: min(maximumWidth ?? host.bounds.width, host.bounds.width))
        host.addSubview(bubble)
        let size = bubble.intrinsicContentSize
        let anchor = trigger.convert(trigger.bounds, to: host)
        // side: top, align: center; flipped under the trigger when there is no room above it
        var y = anchor.minY - Self.sideOffset - size.height
        if y < 0 { y = anchor.maxY + Self.sideOffset }
        var x = anchor.midX - size.width / 2
        x = min(max(x, 0), max(0, host.bounds.width - size.width))
        bubble.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        self.bubble = bubble

        bubble.alpha = 0
        bubble.transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.95, y: 0.95)
        UIViewPropertyAnimator(duration: Self.transition, controlPoint1: Self.cubicOut.0,
                               controlPoint2: Self.cubicOut.1) {
            bubble.alpha = 1
            bubble.transform = .identity
        }.startAnimation()

        // The trigger can go away under a pointer that never leaves it (the page changes).
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.trigger?.window == nil || self.trigger?.isHidden == true { self.close() }
        }
    }

    private func close() {
        pendingOpen?.cancel()
        pendingOpen = nil
        watchdog?.invalidate()
        watchdog = nil
        guard let bubble else { return }
        self.bubble = nil
        UIViewPropertyAnimator(duration: Self.transition, controlPoint1: Self.cubicOut.0,
                               controlPoint2: Self.cubicOut.1) {
            bubble.alpha = 0
            bubble.transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.95, y: 0.95)
        }.startAnimation()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.transition) { bubble.removeFromSuperview() }
    }
}

/// `rounded-md px-3 py-1.5 text-xs`: 12pt text on a 16pt line, padded 12pt by 6pt.
private final class TooltipBubble: UIView {
    private let label = UILabel()
    private let maximumWidth: CGFloat

    init(text: String, maximumWidth: CGFloat) {
        self.maximumWidth = max(24, maximumWidth)
        super.init(frame: .zero)
        backgroundColor = UIColor.HayaseTheme.primary
        layer.cornerRadius = 6
        clipsToBounds = true
        isUserInteractionEnabled = false
        label.numberOfLines = 0
        label.attributedText = CSSText.string(text, font: .nunito(ofSize: 12),
                                              color: UIColor.HayaseTheme.primaryForeground,
                                              lineHeight: 16, lineBreak: .byWordWrapping)
        addSubview(label)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: CGSize {
        let text = label.sizeThatFits(CGSize(width: maximumWidth - 24, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: min(maximumWidth, ceil(text.width) + 24), height: ceil(text.height) + 12)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 12, dy: 6)
    }
}
