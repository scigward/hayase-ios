//
//  Threads.swift
//  Hayase
//

import UIKit

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

// MARK: - ThreadStatsView

final class ThreadStatsView: UIView {
    private let stack = UIStackView()
    private let likesLabel = UILabel()
    private let viewsLabel = UILabel()
    private let repliesLabel = UILabel()
    private let lockView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        stack.addArrangedSubview(makeItem(icon: "heart", label: likesLabel))
        stack.addArrangedSubview(makeItem(icon: "eye", label: viewsLabel))
        stack.addArrangedSubview(makeItem(icon: "messages-square", label: repliesLabel))

        lockView.image = UIImage.hayaseIcon("lock", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        lockView.tintColor = UIColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1)
        lockView.contentMode = .scaleAspectFit
        lockView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            lockView.widthAnchor.constraint(equalToConstant: 12),
            lockView.heightAnchor.constraint(equalToConstant: 12),
        ])
        stack.addArrangedSubview(lockView)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func makeItem(icon: String, label: UILabel) -> UIStackView {
        let imageView = UIImageView(image: UIImage.hayaseIcon(icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)))
        imageView.tintColor = UIColor(white: 0.6, alpha: 1)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
        ])

        label.font = .nunito(ofSize: 9.6)
        label.textColor = UIColor(white: 0.6, alpha: 1)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let item = UIStackView(arrangedSubviews: [imageView, label])
        item.axis = .horizontal
        item.spacing = 4
        item.alignment = .center
        return item
    }

    func configure(likes: Int, views: Int, replies: Int, locked: Bool) {
        likesLabel.text = "\(likes)"
        viewsLabel.text = "\(views)"
        repliesLabel.text = "\(replies)"
        lockView.isHidden = !locked
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

    private let statsView = ThreadStatsView()

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

        [titleLabel, statsView, footerLabel, badgeStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(lessThanOrEqualToConstant: 112),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: statsView.leadingAnchor, constant: -8),

            statsView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            statsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

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
        statsView.configure(likes: thread.likeCount, views: thread.viewCount, replies: thread.replyCount, locked: thread.isLocked)

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
        statsView.configure(likes: 0, views: 0, replies: 0, locked: false)
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

// MARK: - Thread fetching

extension AnimeDetailViewController {

    func fetchThreads() {
        guard let id = animeItem?.id else { return }
        threadsLoading = true
        tableView.reloadSections(IndexSet(integer: Section.threads.rawValue), with: .none)

        AniListClient.shared.threads(mediaID: id) { [weak self] parsed in
            guard let self else { return }
            self.threads = parsed
            self.threadsLoading = false
            if self.activeSection == .threads {
                self.tableView.reloadSections(IndexSet(integer: Section.threads.rawValue), with: .fade)
            }
        }
    }

    func makeThreadCell(for indexPath: IndexPath) -> UITableViewCell {
        let cols = threadColumnCount
        if cols >= 2 && !threadsLoading && !threads.isEmpty {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ThreadPairCell.reuseID, for: indexPath) as? ThreadPairCell else {
                return UITableViewCell()
            }
            let accentColor = animeItem.flatMap { item in
                ExtensionSearchViewController.uiColor(fromHex: item.coverColor ?? "") } ?? UIColor(white: 0.15, alpha: 1)
            let leftIdx = indexPath.row * 2
            let rightIdx = leftIdx + 1
            guard let leftThread = threads[safe: leftIdx] else { return UITableViewCell() }
            let rightThread = threads[safe: rightIdx]
            cell.configure(left: leftThread, right: rightThread, accentColor: accentColor)
            cell.onTapThread = { [weak self] threadID in
                guard let self = self else { return }
                guard let thread = self.threads.first(where: { $0.id == threadID }) else { return }
                let threadVC = ThreadDetailViewController(threadID: thread.id, title: thread.title)
                self.navigationController?.pushViewController(threadVC, animated: true)
            }
            return cell
        }

        if threadsLoading || threads.isEmpty {
            return makeEmptyStateCell(
                text: "No threads found.",
                loading: threadsLoading)
        }
        guard let thread = threads[safe: indexPath.row] else { return UITableViewCell() }
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .default

        let card = UIView()
        card.backgroundColor = hayaseCardBackground
        card.layer.cornerRadius = 6
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(card)

        let titleLabel = UILabel()
        titleLabel.text = thread.title
        titleLabel.font = .nunito(ofSize: 12.8, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let statsView = ThreadStatsView()
        statsView.configure(likes: thread.likeCount, views: thread.viewCount, replies: thread.replyCount, locked: thread.isLocked)
        statsView.translatesAutoresizingMaskIntoConstraints = false

        let footerLabel = UILabel()
        var footerParts = [thread.sinceString]
        if let name = thread.userName { footerParts.append("by \(name)") }
        footerLabel.text = footerParts.joined(separator: " · ")
        footerLabel.font = .nunito(ofSize: 9.6)
        footerLabel.textColor = UIColor(white: 0.5, alpha: 1)
        footerLabel.translatesAutoresizingMaskIntoConstraints = false

        let accentColor = animeItem.flatMap { item in
            ExtensionSearchViewController.uiColor(fromHex: item.coverColor ?? "") } ?? UIColor(white: 0.15, alpha: 1)
        let badgeStack = UIStackView()
        badgeStack.axis = .horizontal
        badgeStack.spacing = 8
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        for cat in thread.categories.prefix(3) {
            let badge = ThreadBadgeLabel()
            badge.text = cat
            badge.font = .nunito(ofSize: 9.6, weight: .bold)
            badge.textColor = ExtensionSearchViewController.luminanceContrastColor(for: accentColor)
            badge.backgroundColor = accentColor
            badge.layer.cornerRadius = 4
            badge.clipsToBounds = true
            badge.textAlignment = .center
            badge.translatesAutoresizingMaskIntoConstraints = false
            badgeStack.addArrangedSubview(badge)
        }

        card.addSubview(titleLabel)
        card.addSubview(statsView)
        card.addSubview(footerLabel)
        card.addSubview(badgeStack)

        let sidePad: CGFloat = traitCollection.horizontalSizeClass == .regular ? 56 : 16

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 14),
            card.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -14),
            card.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: sidePad),
            card.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -sidePad),
            card.heightAnchor.constraint(lessThanOrEqualToConstant: 112),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: statsView.leadingAnchor, constant: -8),

            statsView.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            statsView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            footerLabel.topAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: 6),
            footerLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            footerLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            badgeStack.centerYAnchor.constraint(equalTo: footerLabel.centerYAnchor),
            badgeStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return cell
    }
}
