//
//  ChatMessageToastCardView.swift
//  Hayase
//
//  Mirrors: interface components/ui/chat MessageToast.svelte, shown with `toast.custom` and
//  `!bg-transparent w-full !shadow-none`: no card around it, only the avatar and the bubble.
//

import UIKit

final class ChatMessageToastCardView: UIView, ToastCardView {
    let id = UUID()
    var onDismiss: ((Bool) -> Void)?

    private static let avatarSize: CGFloat = 32   // size-8
    /// svelte-sonner's default toast duration.
    private static let duration: TimeInterval = 4

    private let message: IRCChatMessage
    private let profile = FollowerAvatarStackView()
    private let nameLabel = UILabel()
    private let timeLabel = UILabel()
    private let bubble = ChatBubbleView()
    private var timer: Timer?
    private var startedAt: Date?
    private var remaining = ChatMessageToastCardView.duration
    private var dismissing = false

    init(message: IRCChatMessage) {
        self.message = message
        super.init(frame: .zero)

        nameLabel.font = .nunito(ofSize: 14, weight: .bold)
        nameLabel.textColor = UIColor.HayaseTheme.foreground
        nameLabel.text = message.user.name
        timeLabel.font = .nunito(ofSize: 10)
        timeLabel.textColor = UIColor.HayaseTheme.mutedForeground
        timeLabel.text = ChatTime.string(for: message.date)
        // rounded-t-xl rounded-l-xl
        bubble.configure(text: message.message, background: UIColor.HayaseTheme.muted,
                         corners: [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner])

        let user = message.user
        let summary = AniListUserSummary(id: Int(user.id) ?? 0, name: user.name, avatarURL: user.avatarURL)
        profile.configure(users: [summary], avatarSize: Self.avatarSize, ringWidth: 4,
                          ringColor: UIColor.HayaseTheme.background) { id, completion in
            guard !user.isGuest else {
                completion(nil)
                return
            }
            AniListClient.shared.fetchUserProfileResult(id: id) { result in
                completion(try? result.get())
            }
        }
        [profile, nameLabel, timeLabel, bubble].forEach(addSubview)

        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
        isAccessibilityElement = true
        accessibilityLabel = user.name + "\n" + message.message
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit { timer?.invalidate() }

    // MARK: - Layout

    /// `flex-row-reverse`: the avatar on the right, then a column of `px-2` whose bubble may be
    /// at most `100% - 100px` of what is left of it.
    private struct Metrics {
        let bubble: CGSize
        let nameWidth: CGFloat
        let timeWidth: CGFloat
        let height: CGFloat
    }

    private func metrics(for width: CGFloat) -> Metrics {
        let column = width - Self.avatarSize - 16
        let bubble = ChatBubbleView.size(for: message.message, maxWidth: max(0, column - 100))
        let nameWidth = ceil(nameLabel.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: 20)).width)
        let timeWidth = ceil(timeLabel.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: 20)).width)
        // header 20 + pb-1 4, bubble, mb-1 4
        return Metrics(bubble: bubble, nameWidth: nameWidth, timeWidth: timeWidth, height: 24 + bubble.height + 4)
    }

    func height(for width: CGFloat) -> CGFloat {
        metrics(for: width).height
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = metrics(for: bounds.width)
        profile.frame = CGRect(x: bounds.width - Self.avatarSize, y: 0, width: Self.avatarSize, height: Self.avatarSize)
        let columnRight = bounds.width - Self.avatarSize - 8
        // px-1, then the time after pl-2 of the name
        let timeRight = columnRight - 4
        timeLabel.frame = CGRect(x: timeRight - m.timeWidth, y: 2, width: m.timeWidth, height: 16)
        nameLabel.frame = CGRect(x: timeLabel.frame.minX - 8 - m.nameWidth, y: 0, width: m.nameWidth, height: 20)
        bubble.frame = CGRect(x: columnRight - m.bubble.width, y: 24, width: m.bubble.width, height: m.bubble.height)
    }

    // MARK: - Lifetime

    func startTimer() {
        guard !dismissing, timer == nil else { return }
        startedAt = Date()
        let timer = Timer(timeInterval: max(0.01, remaining), repeats: false) { [weak self] _ in self?.dismiss(swiped: false) }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pauseTimer() {
        if let startedAt { remaining -= Date().timeIntervalSince(startedAt) }
        startedAt = nil
        timer?.invalidate()
        timer = nil
    }

    func dismiss(swiped: Bool) {
        guard !dismissing else { return }
        dismissing = true
        pauseTimer()
        onDismiss?(swiped)
    }

    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        if gesture.state == .began { pauseTimer() }
        else if gesture.state == .ended || gesture.state == .cancelled { startTimer() }
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        let amount = min(0, gesture.translation(in: superview).y)
        switch gesture.state {
        case .began:
            pauseTimer()
        case .changed:
            transform = CGAffineTransform(translationX: 0, y: amount)
        case .ended, .cancelled:
            if gesture.state == .ended && amount <= -20 {
                dismiss(swiped: true)
            } else {
                UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.4) { self.transform = .identity }
                startTimer()
            }
        default:
            break
        }
    }
}

/// `date.toLocaleTimeString()`: the time of day with seconds, as the device formats it.
enum ChatTime {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    static func string(for date: Date) -> String {
        formatter.string(from: date)
    }
}
