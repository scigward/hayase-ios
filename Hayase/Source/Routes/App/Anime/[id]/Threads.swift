//
//  Threads.swift
//  Hayase
//

import UIKit

// MARK: - AniListThread

struct AniListThread {
    let id: Int
    let title: String
    let viewCount: Int
    let replyCount: Int
    let likeCount: Int
    let isLocked: Bool
    let createdAt: TimeInterval
    let userName: String?
    let avatarURL: String?
    let categories: [String]

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? Int else { return nil }
        self.id = id
        self.title = dict["title"] as? String ?? "Thread \(id)"
        self.viewCount = dict["viewCount"] as? Int ?? 0
        self.replyCount = dict["replyCount"] as? Int ?? 0
        self.likeCount = dict["likeCount"] as? Int ?? 0
        self.isLocked = dict["isLocked"] as? Bool ?? false
        self.createdAt = dict["createdAt"] as? TimeInterval ?? 0
        let user = dict["user"] as? [String: Any]
        self.userName = user?["name"] as? String
        let avatar = user?["avatar"] as? [String: Any]
        self.avatarURL = avatar?["large"] as? String
        let cats = dict["categories"] as? [[String: Any]] ?? []
        self.categories = cats.compactMap { $0["name"] as? String }.filter { $0 != "Anime" }
    }

    var sinceString: String {
        let diff = Date().timeIntervalSince1970 - createdAt
        switch diff {
        case ..<60:        return "just now"
        case ..<3600:      return "\(Int(diff/60))m ago"
        case ..<86400:     return "\(Int(diff/3600))h ago"
        case ..<2592000:   return "\(Int(diff/86400))d ago"
        default:           return "\(Int(diff/2592000))mo ago"
        }
    }
}

// MARK: - ThreadBadgeLabel

final class ThreadBadgeLabel: UILabel {
    let hPad: CGFloat = 12
    let vPad: CGFloat = 2

    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return CGSize(width: base.width + hPad * 2, height: base.height + vPad * 2)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: hPad, dy: vPad))
    }
}

// MARK: - ThreadCardView

final class ThreadCardView: UIView {

    var onTap: ((Int) -> Void)?
    private var threadID: Int = 0

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12.8, weight: .bold)
        l.textColor = .white
        l.numberOfLines = 1
        return l
    }()

    private let statsLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9.6)
        l.textColor = UIColor(white: 0.6, alpha: 1)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }()

    private let footerLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9.6)
        l.textColor = UIColor(white: 0.5, alpha: 1)
        return l
    }()

    private let badgeStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        return sv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = hayaseCardBackground
        layer.cornerRadius = 6
        clipsToBounds = true

        [titleLabel, statsLabel, footerLabel, badgeStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(lessThanOrEqualToConstant: 112),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: statsLabel.leadingAnchor, constant: -8),

            statsLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            statsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            footerLabel.topAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: 6),
            footerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            footerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            badgeStack.centerYAnchor.constraint(equalTo: footerLabel.centerYAnchor),
            badgeStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        addGestureRecognizer(tap)
    }

    @objc private func cardTapped() {
        onTap?(threadID)
    }

    func configure(with thread: AniListThread, accentColor: UIColor) {
        threadID = thread.id
        titleLabel.text = thread.title
        statsLabel.text = "♥ \(thread.likeCount)  👁 \(thread.viewCount)  💬 \(thread.replyCount)\(thread.isLocked ? "  🔒" : "")"

        var footerParts = [thread.sinceString]
        if let name = thread.userName { footerParts.append("by \(name)") }
        footerLabel.text = footerParts.joined(separator: " · ")

        badgeStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let contrastColor = ExtensionSearchViewController.luminanceContrastColor(for: accentColor)
        for cat in thread.categories.prefix(3) {
            let badge = ThreadBadgeLabel()
            badge.text = cat
            badge.font = .nunito(ofSize: 9.6, weight: .bold)
            badge.textColor = contrastColor
            badge.backgroundColor = accentColor
            badge.layer.cornerRadius = 4
            badge.clipsToBounds = true
            badge.textAlignment = .center
            badge.translatesAutoresizingMaskIntoConstraints = false
            badgeStack.addArrangedSubview(badge)
        }
    }

    func reset() {
        titleLabel.text = nil
        statsLabel.text = nil
        footerLabel.text = nil
        badgeStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        threadID = 0
        onTap = nil
    }
}

// MARK: - ThreadPairCell

final class ThreadPairCell: UITableViewCell {
    static let reuseID = "ThreadPairCell"

    let leftCard = ThreadCardView()
    let rightCard = ThreadCardView()
    var onTapThread: ((Int) -> Void)?

    private let stack = UIStackView()
    private let rightContainer = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        selectionStyle = .none

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 40
        stack.translatesAutoresizingMaskIntoConstraints = false

        leftCard.translatesAutoresizingMaskIntoConstraints = false
        rightCard.translatesAutoresizingMaskIntoConstraints = false

        rightContainer.addSubview(rightCard)
        stack.addArrangedSubview(leftCard)
        stack.addArrangedSubview(rightContainer)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 56),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -56),
            rightCard.topAnchor.constraint(equalTo: rightContainer.topAnchor),
            rightCard.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor),
            rightCard.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            rightCard.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor),
        ])
    }

    func configure(left: AniListThread, right: AniListThread?, accentColor: UIColor) {
        leftCard.configure(with: left, accentColor: accentColor)
        leftCard.onTap = { [weak self] id in self?.onTapThread?(id) }

        if let right = right {
            rightCard.configure(with: right, accentColor: accentColor)
            rightCard.onTap = { [weak self] id in self?.onTapThread?(id) }
            rightContainer.isHidden = false
        } else {
            rightCard.reset()
            rightContainer.isHidden = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        leftCard.reset()
        rightCard.reset()
        rightContainer.isHidden = false
        onTapThread = nil
    }
}
