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

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.backgroundColor = UIColor(white: 0.16, alpha: 1)
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 10
        iv.isHidden = true
        return iv
    }()

    private let badgeStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        return sv
    }()

    private var avatarTask: URLSessionDataTask?
    private var currentAvatarURL: String?
    private var footerLeadingToAvatar: NSLayoutConstraint?
    private var footerLeadingToCard: NSLayoutConstraint?

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

        [titleLabel, statsView, avatarImageView, footerLabel, badgeStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        footerLeadingToAvatar = footerLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 6)
        footerLeadingToCard = footerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        footerLeadingToCard?.isActive = true

        NSLayoutConstraint.activate([
            heightAnchor.constraint(lessThanOrEqualToConstant: 112),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: statsView.leadingAnchor, constant: -8),

            statsView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            statsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            avatarImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            avatarImageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            avatarImageView.widthAnchor.constraint(equalToConstant: 20),
            avatarImageView.heightAnchor.constraint(equalToConstant: 20),

            footerLabel.topAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: 6),
            footerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            footerLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeStack.leadingAnchor, constant: -8),

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
        configureAvatar(urlString: thread.avatarURL)

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
        avatarTask?.cancel()
        avatarTask = nil
        currentAvatarURL = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
        footerLeadingToAvatar?.isActive = false
        footerLeadingToCard?.isActive = true
        titleLabel.text = nil
        statsView.configure(likes: 0, views: 0, replies: 0, locked: false)
        footerLabel.text = nil
        badgeStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        threadID = 0
        onTap = nil
    }

    private func configureAvatar(urlString: String?) {
        avatarTask?.cancel()
        avatarTask = nil
        currentAvatarURL = urlString
        avatarImageView.image = nil
        guard let urlString, let url = URL(string: urlString) else {
            avatarImageView.isHidden = true
            footerLeadingToAvatar?.isActive = false
            footerLeadingToCard?.isActive = true
            return
        }
        avatarImageView.isHidden = false
        footerLeadingToCard?.isActive = false
        footerLeadingToAvatar?.isActive = true

        let captured = urlString
        avatarTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard self?.currentAvatarURL == captured else { return }
                self?.avatarImageView.image = image
            }
        }
        avatarTask?.resume()
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
        guard let id = routeAnimeID else { return }
        threadsLoading = true
        tableView.reloadSections(IndexSet(integer: Section.threads.rawValue), with: .none)

        AniListClient.shared.threadsResult(mediaID: id) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let parsed):
                self.threads = parsed
            case .failure(let error):
                NSLog("[AnimeDetail] Threads failed: %@", error.description)
                self.threads = []
            }
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
                if let animeID = self.routeAnimeID {
                    Router.shared.navigateToAnimeThread(animeID: animeID, threadID: thread.id, title: thread.title,
                                                       hostTabIndex: self.tabBarController?.selectedIndex)
                } else {
                    let threadVC = ThreadDetailViewController(threadID: thread.id, title: thread.title)
                    self.navigationController?.pushViewController(threadVC, animated: true)
                }
            }
            return cell
        }

        if threadsLoading || threads.isEmpty {
            return makeEmptyStateCell(
                text: animePageErrorDescription ?? "Ooops! Looks like there's nothing here yet!",
                loading: threadsLoading)
        }
        guard let thread = threads[safe: indexPath.row] else { return UITableViewCell() }
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none

        let card = ThreadCardView()
        let accentColor = animeItem.flatMap { item in
            ExtensionSearchViewController.uiColor(fromHex: item.coverColor ?? "") } ?? UIColor(white: 0.15, alpha: 1)
        card.configure(with: thread, accentColor: accentColor)
        card.onTap = { [weak self] threadID in
            guard let self = self else { return }
            guard let thread = self.threads.first(where: { $0.id == threadID }) else { return }
            if let animeID = self.routeAnimeID {
                Router.shared.navigateToAnimeThread(animeID: animeID, threadID: thread.id, title: thread.title,
                                                   hostTabIndex: self.tabBarController?.selectedIndex)
            } else {
                let threadVC = ThreadDetailViewController(threadID: thread.id, title: thread.title)
                self.navigationController?.pushViewController(threadVC, animated: true)
            }
        }
        card.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(card)

        let sidePad: CGFloat = traitCollection.horizontalSizeClass == .regular ? 56 : 16

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 14),
            card.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -14),
            card.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: sidePad),
            card.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -sidePad),
            card.heightAnchor.constraint(lessThanOrEqualToConstant: 112),
        ])
        return cell
    }
}
