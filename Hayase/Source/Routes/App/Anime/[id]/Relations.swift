//
//  Relations.swift
//  Hayase
//

import UIKit

// MARK: - HorizontalCardsCell

final class HorizontalCardsCell: UITableViewCell {
    static let relationsReuseID  = "HorizontalRelationsCell"
    static let staffReuseID      = "HorizontalStaffCell"

    let collectionView: UICollectionView

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 90, height: 140)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        contentView.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func applyPaddingForSizeClass(isRegular: Bool) {
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            let sidePad: CGFloat = isRegular ? 56 : 16
            layout.sectionInset = UIEdgeInsets(top: 0, left: sidePad, bottom: 0, right: sidePad)
        }
    }
}

// MARK: - RelationCardCell

final class RelationCardCell: UICollectionViewCell {
    static let reuseID = "RelationCardCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.layer.cornerRadius = 6
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let typeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 8, weight: .medium)
        l.textColor = .white
        l.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.85)
        l.layer.cornerRadius = 3
        l.clipsToBounds = true
        return l
    }()

    private var imageTask: URLSessionDataTask?
    private var currentURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        [imageView, titleLabel, typeLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 1.35),

            typeLabel.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 4),
            typeLabel.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -4),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with relation: AnimeRelation) {
        let displayType = relation.relationType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        typeLabel.text = " \(displayType) "
        titleLabel.text = relation.media.titleEnglish ?? relation.media.titleRomaji
        loadImage(from: relation.media.coverURL)
    }

    private func loadImage(from urlString: String?) {
        imageTask?.cancel()
        imageTask = nil
        currentURL = urlString
        imageView.image = nil
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        let captured = urlString
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                if self?.currentURL == captured {
                    UIView.transition(with: self?.imageView ?? UIImageView(),
                                      duration: 0.2, options: .transitionCrossDissolve,
                                      animations: { self?.imageView.image = img })
                }
            }
        }
        imageTask?.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel(); imageTask = nil; currentURL = nil
        imageView.image = nil; titleLabel.text = nil; typeLabel.text = nil
    }
}

// MARK: - StaffCardCell

final class StaffCardCell: UICollectionViewCell {
    static let reuseID = "StaffCardCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.layer.cornerRadius = 6
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let roleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 8)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        return l
    }()

    private var imageTask: URLSessionDataTask?
    private var currentURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [nameLabel, roleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        [imageView, stack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 1.35),

            stack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with member: AnimeStaffMember) {
        nameLabel.text = member.name
        roleLabel.text = member.role
        imageTask?.cancel(); imageTask = nil
        currentURL = member.imageURL
        imageView.image = nil
        guard let urlStr = member.imageURL, let url = URL(string: urlStr) else { return }
        let captured = urlStr
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                if self?.currentURL == captured {
                    UIView.transition(with: self?.imageView ?? UIImageView(),
                                      duration: 0.2, options: .transitionCrossDissolve,
                                      animations: { self?.imageView.image = img })
                }
            }
        }
        imageTask?.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel(); imageTask = nil; currentURL = nil
        imageView.image = nil; nameLabel.text = nil; roleLabel.text = nil
    }
}

// MARK: - ScoreBarChartView + StatsCell

final class ScoreBarChartView: UIView {
    private var arrangedStack: UIStackView?

    func configure(with points: [AnimeScorePoint]) {
        arrangedStack?.removeFromSuperview()
        arrangedStack = nil
        guard !points.isEmpty else { return }
        let maxAmount = points.map { $0.amount }.max() ?? 1
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .bottom
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        arrangedStack = stack
        for point in points {
            let col = UIView()
            let bar = UIView()
            let alpha = 0.4 + 0.6 * CGFloat(point.score) / 100.0
            bar.backgroundColor = UIColor.systemIndigo.withAlphaComponent(alpha)
            bar.layer.cornerRadius = 2
            bar.translatesAutoresizingMaskIntoConstraints = false
            let lbl = UILabel()
            lbl.text = "\(point.score)"
            lbl.font = .nunito(ofSize: 7)
            lbl.textColor = .tertiaryLabel
            lbl.textAlignment = .center
            lbl.translatesAutoresizingMaskIntoConstraints = false
            col.addSubview(bar)
            col.addSubview(lbl)
            let fraction = max(0.04, CGFloat(point.amount) / CGFloat(maxAmount))
            NSLayoutConstraint.activate([
                lbl.bottomAnchor.constraint(equalTo: col.bottomAnchor),
                lbl.leadingAnchor.constraint(equalTo: col.leadingAnchor),
                lbl.trailingAnchor.constraint(equalTo: col.trailingAnchor),
                lbl.heightAnchor.constraint(equalToConstant: 14),
                bar.leadingAnchor.constraint(equalTo: col.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: col.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: lbl.topAnchor, constant: -2),
                bar.heightAnchor.constraint(equalTo: col.heightAnchor, multiplier: fraction * 0.85),
            ])
            stack.addArrangedSubview(col)
        }
    }
}

final class StatsCell: UITableViewCell {
    static let reuseID = "AniDetailStatsCell"

    private let chartView = ScoreBarChartView()
    private let statusStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func makeTitle(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .nunito(ofSize: 14, weight: .semibold)
        l.textColor = .label
        return l
    }

    private func setup() {
        backgroundColor = .clear
        selectionStyle = .none
        chartView.translatesAutoresizingMaskIntoConstraints = false
        statusStack.axis = .vertical
        statusStack.spacing = 10
        let mainStack = UIStackView(arrangedSubviews: [
            makeTitle("Score Distribution"), chartView,
            makeTitle("Watching Status"), statusStack,
        ])
        mainStack.axis = .vertical
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            chartView.heightAnchor.constraint(equalToConstant: 90),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    func configure(scores: [AnimeScorePoint], statuses: [AnimeStatusCount]) {
        chartView.configure(with: scores)
        statusStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let total = statuses.reduce(0) { $0 + $1.amount }
        for status in statuses {
            let fraction = total > 0 ? Float(status.amount) / Float(total) : 0
            let name = status.status.replacingOccurrences(of: "_", with: " ").capitalized
            let nameLabel = UILabel()
            nameLabel.text = name
            nameLabel.font = .nunito(ofSize: 11)
            nameLabel.textColor = .label
            nameLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
            let progress = UIProgressView(progressViewStyle: .default)
            progress.setProgress(fraction, animated: false)
            progress.progressTintColor = Self.statusColor(for: status.status)
            progress.trackTintColor = .systemGray5
            let countLabel = UILabel()
            countLabel.text = "\(status.amount)"
            countLabel.font = .nunito(ofSize: 11)
            countLabel.textColor = .secondaryLabel
            countLabel.textAlignment = .right
            countLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
            let row = UIStackView(arrangedSubviews: [nameLabel, progress, countLabel])
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            statusStack.addArrangedSubview(row)
        }
    }

    private static func statusColor(for status: String) -> UIColor {
        switch status {
        case "CURRENT":   return UIColor(red: 61/255,  green: 180/255, blue: 242/255, alpha: 1)
        case "PLANNING":  return UIColor(red: 247/255, green: 154/255, blue: 99/255,  alpha: 1)
        case "COMPLETED": return UIColor(red: 123/255, green: 213/255, blue: 85/255,  alpha: 1)
        case "PAUSED":    return UIColor(red: 250/255, green: 122/255, blue: 122/255, alpha: 1)
        case "REPEATING": return UIColor(red: 59/255,  green: 174/255, blue: 234/255, alpha: 1)
        default:          return UIColor(red: 200/255, green: 80/255,  blue: 80/255,  alpha: 1)
        }
    }
}

// MARK: - Relations fetching

extension AnimeDetailViewController {

    func makeRelationsCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: HorizontalCardsCell.relationsReuseID,
            for: indexPath) as? HorizontalCardsCell else { return UITableViewCell() }
        cell.collectionView.tag = 100
        cell.collectionView.dataSource = self
        cell.collectionView.delegate = self
        cell.collectionView.register(RelationCardCell.self,
                                     forCellWithReuseIdentifier: RelationCardCell.reuseID)
        cell.applyPaddingForSizeClass(isRegular: traitCollection.horizontalSizeClass == .regular)
        cell.collectionView.reloadData()
        return cell
    }

    func fetchRelationsAndCharacters() {
        let id: Int?
        if let entity = animeEntity { id = entity.animeAnilistId?.intValue }
        else { id = animeItem?.id }
        guard let anilistId = id else { return }

        AnimeService.sharedAnimeService.fetchDetailForItem(id: anilistId) { [weak self] rels in
            guard let self = self else { return }
            self.relations = rels
            if !rels.isEmpty {
                self.tableView.reloadSections(IndexSet(integer: Section.relations.rawValue), with: .fade)
            }
        }

        if animeItem == nil || animeItem?.trailerYouTubeID == nil || animeItem?.malId == nil {
            AnimeService.sharedAnimeService.fetchTrailerAndGenres(id: anilistId) { [weak self] trailerID, genres, malId in
                guard let self else { return }
                let needsGenres = self.animeItem == nil || self.animeItem?.genres.isEmpty == true
                if needsGenres {
                    self.headerView?.updateGenresAndTrailer(genres: genres, trailerYouTubeID: trailerID)
                } else if let trailerID {
                    self.headerView?.updateTrailerButton(trailerYouTubeID: trailerID)
                }
                self.animeItem?.trailerYouTubeID = trailerID

                if let malId, self.headerView?.malId == nil {
                    self.headerView?.malId = malId
                    self.animeItem?.malId = malId
                    self.headerView?.updateMALButtonVisibility()
                }
            }
        }
    }
}
