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
    static let skeletonItemCount = 50

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
        collectionView.register(SkeletonCardCell.self,
                                forCellWithReuseIdentifier: SkeletonCardCell.reuseID)
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
        let sidePad = isRegular
            ? AnimeDetailViewController.interfacePageSideInset(for: availableWidth)
            : CGFloat(16)
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
        let requestID = UUID()
        animePageRequestID = requestID
        recommendationsLoading = true
        animePageErrorDescription = nil
        followingEntriesByEpisode.removeAll()
        headerView?.clearFollowingAvatars()
        reloadAnimePagePayloadSections()

        AniListClient.shared.fetchAnimePageResult(id: id) { [weak self] result in
            guard let self,
                  self.routeAnimeID == id,
                  self.animePageRequestID == requestID else { return }

            self.recommendationsLoading = false
            switch result {
            case .success(let payload):
                self.animePageErrorDescription = nil
                if let media = payload.media {
                    let merged = self.animeItem?.mergingRouteMedia(media) ?? media
                    self.animeItem = merged
                    self.applyViewerState(from: merged)
                    Router.shared.cacheAnimeItem(merged)
                    self.headerView?.updateAnimePageDetails(with: merged)
                    if let accent = ExtensionSearchViewController.uiColor(fromHex: merged.coverColor) {
                        self.currentAnimeAccent = accent
                        self.tabBar.accentColor = accent
                    }
                    if !merged.relations.isEmpty {
                        self.relations = merged.relations
                    }
                    if let graph = payload.relationGraph {
                        self.applyRelationGraph(graph)
                        self.expandRelationGraphIfNeeded(graph)
                    }
                }

                self.recommendations = payload.recommendations
                self.threads = payload.threads
                self.threadTotalCount = payload.threadTotal
                self.followingEntriesByEpisode = Dictionary(grouping: payload.followingEntries, by: \.progress)
                    .mapValues { entries in entries.map(\.user) }
                self.headerView?.updateFollowingAvatars(users: payload.followingEntries.map(\.user))

                self.reloadAnimePagePayloadSections()
                self.fetchLegacyAnimeDetailsIfNeeded()
            case .failure(let error):
                NSLog("[AnimeDetail] AnimePage failed: %@", error.description)
                self.animePageErrorDescription = error.description
                self.recommendations = []
                self.threads = []
                self.threadTotalCount = 0
                self.followingEntriesByEpisode.removeAll()
                self.headerView?.clearFollowingAvatars()
                self.reloadAnimePagePayloadSections()
                self.fetchLegacyAnimeDetailsIfNeeded()
            }
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
        if recommendationsLoading {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: RecommendationGridCell.reuseID,
                for: indexPath) as? RecommendationGridCell else {
                return UITableViewCell()
            }
            cell.collectionView.tag = 401
            cell.collectionView.dataSource = self
            cell.collectionView.delegate = self
            cell.configure(itemCount: RecommendationGridCell.skeletonItemCount,
                           availableWidth: tableView.bounds.width,
                           isRegular: traitCollection.horizontalSizeClass == .regular)
            return cell
        }

        guard !recommendations.isEmpty else {
            return makeEmptyStateCell(text: animePageErrorDescription ?? "Looks like there's nothing here yet!", loading: false)
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
