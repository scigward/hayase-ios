import UIKit
import UIKit.UIGestureRecognizerSubclass

/// interface/ui/sonner + svelte-sonner 0.3.28, top-right, expand=true.
@MainActor
enum AppErrorToast {
    private static weak var host: ErrorToastHostView?

    static func show(_ message: String, title: String, duration: TimeInterval = 15) {
        guard let window = (UIApplication.shared.delegate as? AppDelegate)?.window else { return }
        let toastHost = overlay(in: window)
        toastHost.show(message: message, title: title, duration: duration)
        UIAccessibility.post(notification: .announcement, argument: title + "\n" + message)
    }

    /// `toast.success(title, { description, action })`: the default duration of svelte-sonner is 4 seconds.
    static func success(_ title: String, description: String = "", action: ToastAction? = nil,
                        duration: TimeInterval = 4) {
        guard let window = (UIApplication.shared.delegate as? AppDelegate)?.window else { return }
        overlay(in: window).show(message: description, title: title, duration: duration, kind: .success,
                                 action: action)
    }

    /// A chat message from `MessageToast.svelte`, shown while the chat page is not.
    static func show(chatMessage: ChatMessageContent) {
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
    private var removing: Set<UUID> = []
    private let viewport = UIView()
    private weak var observedWindow: UIWindow?
    private var touchObserver: SonnerStackTouchObserver?
    private var hoverObserver: UIHoverGestureRecognizer?
    private var hoverLocation: CGPoint?
    private var pointerOver = false
    private var touching = false
    private var timersPaused = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(viewport)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged(_:)),
                                               name: Settings.didChange, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let touchObserver { observedWindow?.removeGestureRecognizer(touchObserver) }
        if let hoverObserver { observedWindow?.removeGestureRecognizer(hoverObserver) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let touchObserver { observedWindow?.removeGestureRecognizer(touchObserver) }
        if let hoverObserver { observedWindow?.removeGestureRecognizer(hoverObserver) }
        observedWindow = window
        hoverLocation = nil
        pointerOver = false
        touching = false
        updateTimerPause()
        guard let window else { return }
        // Observe, but do not consume, touches/pointer movement across the entire stack and its gaps.
        let touchObserver = SonnerStackTouchObserver(host: self)
        self.touchObserver = touchObserver
        window.addGestureRecognizer(touchObserver)
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:)))
        hover.cancelsTouchesInView = false
        hoverObserver = hover
        window.addGestureRecognizer(hover)
    }

    @objc private func settingsChanged(_ notification: Notification) {
        if notification.userInfo?["key"] as? String == Settings.Keys.uiScale { setNeedsLayout() }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self || hit === viewport ? nil : hit
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Toaster lives inside the web's scaled viewport, not outside its zoomed interface.
        let scale = CGFloat(min(max(Settings.uiScale, 0.3), 2.5))
        viewport.bounds = CGRect(origin: .zero, size: CGSize(width: bounds.width / scale, height: bounds.height / scale))
        viewport.center = CGPoint(x: bounds.midX, y: bounds.midY)
        viewport.transform = CGAffineTransform(scaleX: scale, y: scale)
        let compact = viewport.bounds.width <= 600
        let width = compact ? max(0, viewport.bounds.width - 32) : CGFloat(356)
        let x = compact ? CGFloat(16) : viewport.bounds.width - max(32, safeAreaInsets.right / scale) - width
        let top = compact ? CGFloat(20) : max(32, safeAreaInsets.top / scale)
        var offset: CGFloat = 0
        for (index, card) in cards.enumerated() {
            guard !removing.contains(card.id) else { continue }
            let height = card.height(for: width)
            card.bounds.size = CGSize(width: width, height: height)
            // Toast.svelte rounds offsets, not the card's fractional CSS line-box height.
            card.center = CGPoint(x: x + width / 2, y: top + offset.rounded() + height / 2)
            card.alpha = index < 3 ? 1 : 0
            card.isUserInteractionEnabled = index < 3
            offset += height + 14
        }
        refreshPointerContainment()
    }

    fileprivate func containsToastRegion(_ point: CGPoint, in window: UIView) -> Bool {
        let point = viewport.convert(point, from: window)
        var region = CGRect.null
        for card in cards.prefix(3) {
            // Retain the untransformed ghost area while swiping/removing, as Sonner's pseudo-elements do.
            let rect = CGRect(x: card.center.x - card.bounds.width / 2,
                              y: card.center.y - card.bounds.height / 2,
                              width: card.bounds.width, height: card.bounds.height)
            region = region.union(rect.insetBy(dx: 0, dy: -15))
        }
        return region.contains(point)
    }

    fileprivate func setTouching(_ value: Bool) { touching = value; updateTimerPause() }

    @objc private func hoverChanged(_ gesture: UIHoverGestureRecognizer) {
        if let window, gesture.state == .began || gesture.state == .changed {
            hoverLocation = gesture.location(in: window)
        } else { hoverLocation = nil }
        refreshPointerContainment()
    }

    private func refreshPointerContainment() {
        // Stack reflow can move away from a stationary pointer without a hover event.
        if let window, let hoverLocation {
            pointerOver = containsToastRegion(hoverLocation, in: window)
        } else { pointerOver = false }
        updateTimerPause()
    }

    private func updateTimerPause() {
        let paused = pointerOver || touching
        guard paused != timersPaused else { return }
        timersPaused = paused
        cards.forEach { $0.setTimerPaused(paused) }
    }

    func show(message: String, title: String, duration: TimeInterval,
              id: UUID = UUID(), kind: AppToastKind = .error, action: ToastAction? = nil) {
        present(ErrorToastCardView(message: message, title: title, duration: duration,
                                   id: id, kind: kind, action: action))
    }

    func present(_ card: ToastCardView) {
        layoutIfNeeded()
        card.onDismiss = { [weak self, weak card] swiped in
            guard let self, let card, self.cards.contains(where: { $0 === card }) else { return }
            guard self.removing.insert(card.id).inserted else { return }
            self.setNeedsLayout()
            // Height disappears now; its toast index remains until the 200ms unmount boundary.
            SonnerAnimation.animate(duration: 0.4, changes: { self.layoutIfNeeded() })
            let swipe = swiped ? card.transform.ty : 0
            SonnerAnimation.animate(duration: swiped ? 0.2 : 0.4, easeOut: swiped, changes: {
                card.alpha = 0
                card.transform = CGAffineTransform(translationX: 0, y: swipe - card.bounds.height)
            })
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak card] in
                guard let self, let card else { return }
                self.cards.removeAll { $0 === card }
                self.removing.remove(card.id)
                card.removeFromSuperview()
                self.setNeedsLayout()
                SonnerAnimation.animate(duration: 0.4, changes: { self.layoutIfNeeded() })
            }
        }
        cards.insert(card, at: 0)
        viewport.addSubview(card)
        let width = viewport.bounds.width <= 600 ? max(0, viewport.bounds.width - 32) : 356
        card.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: -card.height(for: width))
        // Establish the new card's geometry before animating stack movement.
        let height = card.height(for: width)
        let scale = CGFloat(min(max(Settings.uiScale, 0.3), 2.5))
        let x = viewport.bounds.width <= 600 ? CGFloat(16) : viewport.bounds.width - max(32, safeAreaInsets.right / scale) - width
        let y = viewport.bounds.width <= 600 ? CGFloat(20) : max(32, safeAreaInsets.top / scale)
        card.bounds.size = CGSize(width: width, height: height)
        card.center = CGPoint(x: x + width / 2, y: y + height / 2)
        setNeedsLayout()
        SonnerAnimation.animate(duration: 0.4, changes: {
            self.layoutIfNeeded()
            card.alpha = 1
            card.transform = .identity
        })
        card.setTimerPaused(timersPaused)
        card.startTimer()
    }

    func update(id: UUID, title: String, kind: AppToastKind, duration: TimeInterval) {
        guard let card = cards.first(where: { $0.id == id }) as? ErrorToastCardView else { return }
        card.update(title: title, kind: kind, duration: duration)
        setNeedsLayout()
        SonnerAnimation.animate(duration: 0.4, changes: { self.layoutIfNeeded() })
    }

    func dismiss(id: UUID) { cards.first(where: { $0.id == id })?.dismiss(swiped: false) }

}
/// Non-consuming pointerdown/up observer: even a loading toast or an action pauses every timer.
private final class SonnerStackTouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var host: ErrorToastHostView?
    private var touches: Set<UITouch> = []
    init(host: ErrorToastHostView) {
        self.host = host
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let host, let window = host.window else { return }
        self.touches.formUnion(touches.filter { host.containsToastRegion($0.location(in: window), in: window) })
        host.setTouching(!self.touches.isEmpty)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        self.touches.subtract(touches)
        host?.setTouching(!self.touches.isEmpty)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { touchesEnded(touches, with: event) }
    override func reset() { touches.removeAll(); host?.setTouching(false) }
}

enum SonnerAnimation {
    static func animate(duration: TimeInterval, easeOut: Bool = false, changes: @escaping () -> Void) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }
        let timing = UICubicTimingParameters(controlPoint1: easeOut ? .zero : CGPoint(x: 0.25, y: 0.1),
                                             controlPoint2: CGPoint(x: easeOut ? 0.58 : 0.25, y: 1))
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        animator.addAnimations(changes)
        animator.startAnimation()
    }
}
