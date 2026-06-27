//  Recommendation.swift
//  Hayase
//
//  Created by scigward.
//  Mirrors: routes/app/anime/[id]/recommendation.svelte
//

import UIKit

// MARK: - RecommendationGridCell

final class RecommendationGridCell: UITableViewCell {
    static let reuseID = "RecommendationGridCell"

    let collectionView: UICollectionView

    private var heightConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 16
        layout.itemSize = CGSize(width: AnimeCollectionViewCell.outerWidth,
                                 height: AnimeCollectionViewCell.outerHeight)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        let layout = UICollectionViewFlowLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(AnimeCollectionViewCell.self,
                                forCellWithReuseIdentifier: AnimeCollectionViewCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(collectionView)

        let height = collectionView.heightAnchor.constraint(equalToConstant: 0)
        height.priority = .required
        heightConstraint = height

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: contentView.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            height,
        ])
    }

    func configure(itemCount: Int, availableWidth: CGFloat, isRegular: Bool) {
        let sidePad: CGFloat = isRegular ? AnimeDetailViewController.gridOuterPad : 16
        let topPad: CGFloat = 12
        let bottomPad: CGFloat = 16
        let gap: CGFloat = 16
        let itemWidth = AnimeCollectionViewCell.outerWidth
        let itemHeight = AnimeCollectionViewCell.outerHeight
        let usableWidth = max(0, availableWidth - sidePad * 2)
        let columns = max(1, Int((usableWidth + gap) / (itemWidth + gap)))
        let rows = itemCount == 0 ? 0 : Int(ceil(Double(itemCount) / Double(columns)))
        let contentHeight = rows == 0
            ? 88
            : topPad + bottomPad + CGFloat(rows) * itemHeight + CGFloat(max(rows - 1, 0)) * gap

        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.itemSize = CGSize(width: itemWidth, height: itemHeight)
            layout.minimumInteritemSpacing = gap
            layout.minimumLineSpacing = gap
            layout.sectionInset = UIEdgeInsets(top: topPad, left: sidePad, bottom: bottomPad, right: sidePad)
            layout.invalidateLayout()
        }
        heightConstraint?.constant = contentHeight
        collectionView.reloadData()
    }
}

// MARK: - AnimeDetailViewController + Recommendations

extension AnimeDetailViewController {

    func fetchAnimePageData() {
        guard let id = routeAnimeID, id > 0 else { return }
        AniListClient.shared.fetchAnimePage(id: id) { [weak self] payload in
            guard let self, self.routeAnimeID == id else { return }

            if let media = payload.media {
                self.animeItem = media
                Router.shared.cacheAnimeItem(media)
                self.headerView?.updateAnimePageDetails(with: media)
                if let accent = ExtensionSearchViewController.uiColor(fromHex: media.coverColor) {
                    self.currentAnimeAccent = accent
                    self.tabBar.accentColor = accent
                }
                if !media.relations.isEmpty {
                    self.relations = media.relations
                }
            }

            self.recommendations = payload.recommendations
            self.threads = payload.threads
            self.threadTotalCount = payload.threadTotal
            self.followingEntriesByEpisode = Dictionary(grouping: payload.followingEntries, by: \.progress)
                .mapValues { entries in Array(entries.prefix(4)).map(\.user) }

            self.reloadAnimePagePayloadSections()
        }
    }

    private func reloadAnimePagePayloadSections() {
        guard tableView != nil else { return }
        let sections = IndexSet([
            Section.header.rawValue,
            Section.episodes.rawValue,
            Section.relations.rawValue,
            Section.threads.rawValue,
            Section.recommendations.rawValue,
        ])
        tableView.reloadSections(sections, with: .none)
    }

    func makeRecommendationCell(for indexPath: IndexPath) -> UITableViewCell {
        guard !recommendations.isEmpty else {
            return makeEmptyStateCell(text: "Ooops! Looks like there's nothing here yet!", loading: false)
        }
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: RecommendationGridCell.reuseID,
            for: indexPath) as? RecommendationGridCell else {
            return UITableViewCell()
        }
        cell.collectionView.tag = 400
        cell.collectionView.dataSource = self
        cell.collectionView.delegate = self
        cell.configure(itemCount: recommendations.count,
                       availableWidth: tableView.bounds.width,
                       isRegular: traitCollection.horizontalSizeClass == .regular)
        return cell
    }
}
