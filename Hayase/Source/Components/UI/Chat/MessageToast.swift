//
//  MessageToast.swift
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
    /// The custom component inherits Sonner's system UI font rather than the page's Nunito.
    private static let bubbleFont = UIFont.systemFont(ofSize: 12)
    private static let nameLineHeight: CGFloat = 20   // text-sm
    private static let timeLineHeight: CGFloat = 16.25   // 10px * leading-relaxed (1.625)
    /// svelte-sonner's default toast duration.
    private static let duration: TimeInterval = 4

    private let message: ChatMessageContent
    private let profile = FollowerAvatarStackView()
    private let nameLabel = UILabel()
    private let timeLabel = UILabel()
    private let bubble = ChatBubbleView()
    private var timer: Timer?
    private var startedAt: Date?
    private var remaining = ChatMessageToastCardView.duration
    private var dismissing = false
    private var timerPaused = false
    private var swipeGesture: SonnerToastGesture?

    init(message: ChatMessageContent) {
        self.message = message
        super.init(frame: .zero)

        nameLabel.font = .systemFont(ofSize: 14, weight: .bold)
        nameLabel.textColor = UIColor.HayaseTheme.foreground
        nameLabel.attributedText = CSSText.string(SonnerText.normal(message.name), font: nameLabel.font,
            color: UIColor.HayaseTheme.foreground, lineHeight: Self.nameLineHeight, lineBreak: .byWordWrapping)
        nameLabel.numberOfLines = 0
        timeLabel.font = .systemFont(ofSize: 10)
        timeLabel.textColor = UIColor.HayaseTheme.mutedForeground
        timeLabel.attributedText = CSSText.string(SonnerText.normal(ChatTime.string(for: message.date)), font: timeLabel.font,
            color: UIColor.HayaseTheme.mutedForeground, lineHeight: Self.timeLineHeight, lineBreak: .byWordWrapping)
        timeLabel.numberOfLines = 0
        // rounded-t-xl rounded-l-xl
        bubble.configure(text: message.text, background: UIColor.HayaseTheme.muted,
                         corners: [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner],
                         font: Self.bubbleFont, cssLineBox: true)

        let summary = AniListUserSummary(id: Int(message.userID) ?? 0, name: message.name, avatarURL: message.avatarURL)
        let isGuest = message.isGuest
        profile.configure(users: [summary], avatarSize: Self.avatarSize, ringWidth: 4,
                          ringColor: UIColor.HayaseTheme.background, toastAppearance: true) { id, completion in
            guard !isGuest else {
                completion(nil)
                return
            }
            AniListClient.shared.fetchUserProfileResult(id: id) { result in
                completion(try? result.get())
            }
        }
        [profile, nameLabel, timeLabel, bubble].forEach(addSubview)

        swipeGesture = SonnerToastGesture(card: self)
        isAccessibilityElement = true
        accessibilityLabel = message.name + "\n" + message.text
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
        let name: CGSize
        let time: CGSize
        let headerHeight: CGFloat
        let height: CGFloat
    }

    private func metrics(for width: CGFloat) -> Metrics {
        let column = width - Self.avatarSize - 16
        let bubble = ChatBubbleView.size(for: message.text, maxWidth: max(0, column - 100),
                                        font: Self.bubbleFont, cssLineBox: true)
        let nameWidth = nameLabel.attributedText?.size().width ?? 0
        let timeWidth = timeLabel.attributedText?.size().width ?? 0
        // Header px-1 (8) and the time's pl-2 (8) do not shrink; both text items do.
        let available = max(0, column - 16)
        let intrinsic = nameWidth + timeWidth
        let shrink = intrinsic > 0 ? min(1, available / intrinsic) : 1
        var nameSpace = nameWidth * shrink
        var timeSpace = timeWidth * shrink
        // overflow-wrap:anywhere lowers flex min-content widths to one unbroken grapheme.
        // Flex freezes a text item at that minimum and gives the remaining width to its sibling.
        let nameMinimum = Self.minimumContentWidth(of: nameLabel)
        let timeMinimum = Self.minimumContentWidth(of: timeLabel)
        if available < nameMinimum + timeMinimum {
            nameSpace = nameMinimum
            timeSpace = timeMinimum
        } else if nameSpace < nameMinimum {
            nameSpace = nameMinimum
            timeSpace = min(timeWidth, available - nameMinimum)
        } else if timeSpace < timeMinimum {
            timeSpace = timeMinimum
            nameSpace = min(nameWidth, available - timeMinimum)
        }
        let name = Self.size(of: nameLabel, width: nameSpace, lineHeight: Self.nameLineHeight)
        let time = Self.size(of: timeLabel, width: timeSpace, lineHeight: Self.timeLineHeight)
        let headerHeight = max(name.height, time.height)
        return Metrics(bubble: bubble, name: name, time: time, headerHeight: headerHeight,
                       height: max(Self.avatarSize, headerHeight + 4 + bubble.height + 4))
    }

    private static func minimumContentWidth(of label: UILabel) -> CGFloat {
        guard let text = label.text, let font = label.font else { return 0 }
        return text.map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    }

    private static func size(of label: UILabel, width: CGFloat, lineHeight: CGFloat) -> CGSize {
        guard let text = label.attributedText, text.length > 0 else { return .zero }
        let width = max(1, width)
        let measured = label.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        // UILabel rounds its fitted height; retain the fractional CSS line boxes themselves.
        let lines = max(1, (measured.height / lineHeight).rounded())
        return CGSize(width: width, height: lines * lineHeight)
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
        timeLabel.frame = CGRect(x: timeRight - m.time.width, y: (m.headerHeight - m.time.height) / 2,
                                 width: m.time.width, height: m.time.height)
        nameLabel.frame = CGRect(x: timeLabel.frame.minX - 8 - m.name.width, y: (m.headerHeight - m.name.height) / 2,
                                 width: m.name.width, height: m.name.height)
        bubble.frame = CGRect(x: columnRight - m.bubble.width, y: m.headerHeight + 4,
                              width: m.bubble.width, height: m.bubble.height)
    }

    // MARK: - Lifetime

    func startTimer() {
        guard !timerPaused, !dismissing, timer == nil else { return }
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

    func setTimerPaused(_ paused: Bool) {
        timerPaused = paused
        if paused { pauseTimer() } else { startTimer() }
    }

    func dismiss(swiped: Bool) {
        guard !dismissing else { return }
        dismissing = true
        pauseTimer()
        onDismiss?(swiped)
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
