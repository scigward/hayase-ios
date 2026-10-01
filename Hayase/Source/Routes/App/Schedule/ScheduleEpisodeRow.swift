//
//  ScheduleEpisodeRow.swift
//  Hayase
//
//  Mirrors: the episode links of interface routes/app/schedule/+page.svelte, which its calendar
//  cells, its overflow tooltip and its mobile drawer repeat.
//

import UIKit

/// A tracked media's colour in the list: the same for the dot and for the check.
enum ScheduleStatusColor {
    static func color(for status: String) -> UIColor {
        switch status {
        case "CURRENT": return UIColor(red: 61/255, green: 180/255, blue: 242/255, alpha: 1)
        case "PLANNING": return UIColor(red: 247/255, green: 154/255, blue: 99/255, alpha: 1)
        case "COMPLETED": return UIColor(red: 123/255, green: 213/255, blue: 85/255, alpha: 1)
        case "PAUSED": return UIColor(red: 250/255, green: 122/255, blue: 122/255, alpha: 1)
        case "REPEATING": return UIColor(red: 59/255, green: 174/255, blue: 234/255, alpha: 1)
        case "DROPPED": return UIColor(red: 200/255, green: 80/255, blue: 80/255, alpha: 1)
        case "PENDING": return UIColor(red: 180/255, green: 180/255, blue: 180/255, alpha: 1)
        // `variant: 'CURRENT'` is the default
        default: return UIColor(red: 61/255, green: 180/255, blue: 242/255, alpha: 1)
        }
    }
}

/// `StatusDot`, or the `Check` that replaces it once the episode is watched: `size-[0.55rem]`, with
/// the check drawn at `strokeWidth={5}`.
private final class ScheduleStatusMark: UIView {
    static let size: CGFloat = 8.8   // 0.55rem
    private let isCheck: Bool
    private let color: UIColor

    init(color: UIColor, isCheck: Bool) {
        self.color = color
        self.isCheck = isCheck
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ rect: CGRect) {
        color.setFill()
        color.setStroke()
        if isCheck {
            let scale = bounds.width / 24
            let path = UIBezierPath(cgPath: SVGPath.path("M20 6 9 17l-5-5"))
            path.apply(CGAffineTransform(scaleX: scale, y: scale))
            path.lineWidth = 5 * scale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        } else {
            UIBezierPath(ovalIn: bounds).fill()
        }
    }
}

final class ScheduleEpisodeRow: UIControl {
    /// Where the row is shown: the calendar's cells, the drawer a day opens on small screens, or
    /// the tooltip that lists a day's episodes past the sixth.
    enum Style {
        case calendar, drawer, overflow
    }

    var onSelect: (() -> Void)?

    let episode: ScheduleAiringEpisode
    private let style: Style
    private let mark: ScheduleStatusMark?
    private let titleLabel = UILabel()
    private let numberLabel = UILabel()
    private let timeLabel = UILabel()
    private let showsNumber: Bool
    private let mutedColor = UIColor.HayaseTheme.mutedForeground
    private let highlightColor = UIColor.HayaseTheme.foreground
    private var isPointerOver = false

    /// `extraLarge`: the `xl` breakpoint, 1280, which shows the dot and the episode number in
    /// the calendar.
    init(episode: ScheduleAiringEpisode, style: Style, extraLarge: Bool) {
        self.episode = episode
        self.style = style
        showsNumber = style == .drawer || extraLarge

        var mark: ScheduleStatusMark?
        if let status = episode.entry?.status {
            let color = ScheduleStatusColor.color(for: status)
            if (episode.entry?.progress ?? 0) >= episode.episode {
                mark = ScheduleStatusMark(color: color, isCheck: true)
            } else if extraLarge {
                mark = ScheduleStatusMark(color: color, isCheck: false)
            }
        }
        self.mark = mark
        super.init(frame: .zero)

        let isPast = episode.airingAt < Date()
        titleLabel.font = .nunito(ofSize: 12, weight: .medium)   // font-medium
        titleLabel.text = episode.titlePreferred
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = style == .overflow
            ? (isPast ? mutedColor : UIColor.HayaseTheme.primaryForeground)
            : UIColor.HayaseTheme.foreground
        numberLabel.font = .nunito(ofSize: 12)
        numberLabel.text = "#\(episode.episode)"
        numberLabel.textColor = titleLabel.textColor
        numberLabel.isHidden = !showsNumber
        timeLabel.font = .nunito(ofSize: 12)
        timeLabel.text = Self.timeFormatter.string(from: episode.airingAt)
        timeLabel.textColor = mutedColor
        [titleLabel, numberLabel, timeLabel].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
        if let mark { addSubview(mark) }

        // The calendar and the drawer dim what has aired; the tooltip greys its text instead.
        alpha = style != .overflow && isPast ? 0.3 : 1
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        addTarget(self, action: #selector(selectEpisode), for: .touchUpInside)
        accessibilityLabel = [episode.titlePreferred, showsNumber ? numberLabel.text : nil, timeLabel.text]
            .compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = .link
        heightAnchor.constraint(equalToConstant: 16).isActive = true   // h-4
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// `format(airTime, 'HH:mm')`
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        let timeWidth = ceil(timeLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 16)).width)
        let timeFrame = CGRect(x: bounds.width - timeWidth, y: 0, width: timeWidth, height: bounds.height)
        timeLabel.frame = timeFrame
        var right = timeFrame.minX
        if showsNumber {
            let width = ceil(numberLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 16)).width)
            // `ml-auto mr-1`
            numberLabel.frame = CGRect(x: right - 4 - width, y: 0, width: width, height: bounds.height)
            right = numberLabel.frame.minX
        }
        var left: CGFloat = 0
        if let mark {
            mark.frame = CGRect(x: 0, y: (bounds.height - ScheduleStatusMark.size) / 2,
                                width: ScheduleStatusMark.size, height: ScheduleStatusMark.size)
            left = ScheduleStatusMark.size + 4   // me-1
        }
        // `pr-2` after the title
        let natural = ceil(titleLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 16)).width)
        titleLabel.frame = CGRect(x: left, y: 0, width: max(0, min(natural, right - 8 - left)), height: bounds.height)
    }

    // MARK: - Select state

    override var isHighlighted: Bool {
        didSet { updateTimeColor() }
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isPointerOver = recognizer.state == .began || recognizer.state == .changed
        updateTimeColor()
        if style == .calendar {
            if isPointerOver {
                ScheduleTooltip.shared.showCover(for: episode, from: self)
            } else {
                ScheduleTooltip.shared.scheduleHide()
            }
        }
    }

    /// `group-select:text-foreground`
    private func updateTimeColor() {
        timeLabel.textColor = isHighlighted || isPointerOver ? highlightColor : mutedColor
    }

    @objc private func selectEpisode() {
        ScheduleTooltip.shared.hide()
        onSelect?()
    }
}
