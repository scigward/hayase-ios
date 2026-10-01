import UIKit

/// interface/ui/sonner + svelte-sonner 0.3.28, top-right, expand=true.
@MainActor
enum AppErrorToast {
    private static weak var host: ErrorToastHostView?
    private static var recentlyShown: [String: Date] = [:]

    static func show(_ message: String, title: String, duration: TimeInterval = 15) {
        guard let window = (UIApplication.shared.delegate as? AppDelegate)?.window else { return }
        let now = Date()
        // Coalesce concurrent event/RPC reports, not deliberate retries later.
        recentlyShown = recentlyShown.filter { now.timeIntervalSince($0.value) < 1 }
        let identity = title + "\n" + message
        guard recentlyShown[identity] == nil else { return }
        recentlyShown[identity] = now
        let toastHost = overlay(in: window)
        toastHost.show(message: message, title: title, duration: duration)
        UIAccessibility.post(notification: .announcement, argument: title + "\n" + message)
    }

    /// A chat message from `MessageToast.svelte`, shown while the chat page is not.
    static func show(chatMessage: IRCChatMessage) {
        guard let window = (UIApplication.shared.delegate as? AppDelegate)?.window else { return }
        overlay(in: window).present(ChatMessageToastCardView(message: chatMessage))
    }

    /// `toast.promise`: update this same card instead of stacking a second toast.
    /// Loading has no timeout and cannot be swiped away before the promise settles.
    @discardableResult
    static func startPromise(title: String, description: String) -> UUID {
        let id = UUID()
        guard let window = (UIApplication.shared.delegate as? AppDelegate)?.window else { return id }
        overlay(in: window).show(message: description, title: title, duration: .infinity,
                                id: id, kind: .loading)
        UIAccessibility.post(notification: .announcement, argument: title + "\n" + description)
        return id
    }

    static func resolvePromise(_ id: UUID, title: String, failed: Bool = false,
                               duration: TimeInterval = 4) {
        host?.update(id: id, title: title, kind: failed ? .error : .success, duration: duration)
        UIAccessibility.post(notification: .announcement, argument: title)
    }

    static func dismiss(_ id: UUID) { host?.dismiss(id: id) }

    private static func overlay(in window: UIWindow) -> ErrorToastHostView {
        let overlay: ErrorToastHostView
        if let existing = host, existing.superview === window {
            overlay = existing
        } else {
            overlay = ErrorToastHostView(frame: window.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(overlay)
            host = overlay
        }
        window.bringSubviewToFront(overlay)
        return overlay
    }
}

@MainActor
enum TorrentErrorToast {
    static func show(_ message: String, title: String = "Torrent Process Error!") {
        AppErrorToast.show(message, title: title)
    }
}

/// Transparent overlay: never intercept navigation or video controls outside toasts.
private final class ErrorToastHostView: UIView {
    private var cards: [ToastCardView] = []

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let compact = bounds.width <= 600
        let width = compact ? max(0, bounds.width - 32) : CGFloat(356)
        let x = compact ? CGFloat(16) : bounds.width - max(32, safeAreaInsets.right) - width
        var y = compact ? CGFloat(20) : max(32, safeAreaInsets.top)
        for (index, card) in cards.enumerated() {
            let height = card.height(for: width)
            card.bounds.size = CGSize(width: width, height: height)
            card.center = CGPoint(x: x + width / 2, y: y + height / 2)
            card.isHidden = index >= 3
            y += height + 14
        }
    }

    func show(message: String, title: String, duration: TimeInterval,
              id: UUID = UUID(), kind: AppToastKind = .error) {
        present(ErrorToastCardView(message: message, title: title, duration: duration,
                                   id: id, kind: kind))
    }

    func present(_ card: ToastCardView) {
        layoutIfNeeded()
        card.onDismiss = { [weak self, weak card] swiped in
            guard let self, let card, self.cards.contains(where: { $0 === card }) else { return }
            self.cards.removeAll { $0 === card }
            self.setNeedsLayout()
            self.animate(duration: swiped ? 0.2 : 0.4, changes: {
                card.alpha = 0
                card.transform = CGAffineTransform(translationX: 0, y: -card.bounds.height)
                self.layoutIfNeeded()
            }, completion: { card.removeFromSuperview() })
        }
        cards.insert(card, at: 0)
        addSubview(card)
        let width = bounds.width <= 600 ? max(0, bounds.width - 32) : 356
        card.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: -card.height(for: width))
        // Establish the new card's geometry before animating stack movement.
        let height = card.height(for: width)
        let x = bounds.width <= 600 ? CGFloat(16) : bounds.width - max(32, safeAreaInsets.right) - width
        let y = bounds.width <= 600 ? CGFloat(20) : max(32, safeAreaInsets.top)
        card.bounds.size = CGSize(width: width, height: height)
        card.center = CGPoint(x: x + width / 2, y: y + height / 2)
        setNeedsLayout()
        animate(duration: 0.4, changes: {
            self.layoutIfNeeded()
            card.alpha = 1
            card.transform = .identity
        })
        card.startTimer()
    }

    func update(id: UUID, title: String, kind: AppToastKind, duration: TimeInterval) {
        guard let card = cards.first(where: { $0.id == id }) as? ErrorToastCardView else { return }
        card.update(title: title, kind: kind, duration: duration)
        setNeedsLayout()
        animate(duration: 0.4, changes: { self.layoutIfNeeded() })
    }

    func dismiss(id: UUID) { cards.first(where: { $0.id == id })?.dismiss() }

    private func animate(duration: TimeInterval, changes: @escaping () -> Void,
                         completion: (() -> Void)? = nil) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            changes()
            completion?()
            return
        }
        // CSS default ease: cubic-bezier(.25,.1,.25,1).
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.25, y: 0.1),
                                             controlPoint2: CGPoint(x: 0.25, y: 1))
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        animator.addAnimations(changes)
        animator.addCompletion { _ in completion?() }
        animator.startAnimation()
    }
}
