//
//  HomePage+DataSource.swift
//  Hayase
//
//  Mirrors: the `{#each $sectionQueries}` of interface routes/app/home/+page.svelte, and the
//  `goto('/#/app/search', { state: { search: variables } })` that its titles and buttons lead to.
//

import UIKit

// MARK: - UICollectionViewDataSource

extension HomeViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        // The banner, then a row for every section
        homeSections.rows.count + 1
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        if section == 0 { return 1 }
        guard let row = homeSections.rows[safe: section - 1] else { return 0 }
        return QueryCard.itemCount(for: row)
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.section == 0 {
            let cell = Banner.cell(for: bannerState, in: collectionView, at: indexPath)
            cell.layer.zPosition = 0
            if let banner = cell as? FullBannerCell, case .loaded(let items) = bannerState {
                wire(banner, items: items)
            }
            return cell
        }

        guard let row = homeSections.rows[safe: indexPath.section - 1] else {
            return collectionView.dequeueReusableCell(withReuseIdentifier: SkeletonCardCell.reuseID, for: indexPath)
        }
        return QueryCard.cell(for: row, in: collectionView, at: indexPath, host: self)
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        // The banner has no header: it is not in the layout
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: HomeSectionHeaderView.reuseID,
            for: indexPath) as? HomeSectionHeaderView ?? HomeSectionHeaderView(frame: .zero)
        header.layer.zPosition = 10
        if let section = homeSections.rows[safe: indexPath.section - 1] {
            header.configure(title: section.title)
            // `search(variables)`
            header.onViewMore = { [weak self] in
                self?.search(section)
            }
        }
        return header
    }

    /// The featured media's callbacks. They are set before it is given its media, which tells
    /// them which one it shows first.
    private func wire(_ cell: FullBannerCell, items: [AnimeItem]) {
        cell.onFeaturedChanged = { [weak self] id in self?.selectedFeaturedID = id }
        cell.onBackdropImageChanged = { [weak self, weak cell] urlString, image in
            let mediaID = cell?.currentItem?.id
            DispatchQueue.main.async {
                guard let self, let cell,
                      cell.currentItem?.id == mediaID,
                      self.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) === cell else { return }
                self.backdropView.setBackdrop(urlString: urlString, image: image)
                self.syncBannerToCurrentScrollPosition()
            }
        }
        // The title, or the logo, is the link to the media
        cell.onTitleTapped = { [weak self] item in
            guard let self else { return }
            Router.shared.navigateToAnime(item, hostTabIndex: self.hayaseTabIndex)
        }
        // play.svelte: the play button starts the episode search, not the page
        cell.onPlayTapped = { [weak self] item in
            self?.hayasePreviewCardActions().play(item)
        }
        cell.onFavorite = { item in
            AniListTracking.shared.toggleFavourite(mediaID: item.id)
        }
        cell.onBookmark = { item in
            AniListTracking.shared.toggleBookmark(media: item)
        }
        cell.onFilter = { [weak self] filter in
            self?.search(filter)
        }
        cell.configure(with: items, selectedID: selectedFeaturedID)
    }
}

// MARK: - UICollectionViewDelegate

extension HomeViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView,
                        willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        guard indexPath.section > 0 else { return }
        homeSections.resume(row: indexPath.section - 1)
    }

    /// Only a card is selected. The banner is not a button: its title and buttons are.
    private func card(at indexPath: IndexPath) -> AnimeItem? {
        guard indexPath.section > 0,
              let row = homeSections.rows[safe: indexPath.section - 1],
              case .loaded = row.contentState else { return nil }
        return row.items[safe: indexPath.item]
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        card(at: indexPath) != nil
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        card(at: indexPath) != nil
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        guard let item = card(at: indexPath) else { return }
        // `use:hover={[onclick, onhover]}`: a touch shows the preview first and goes to the media
        // on the second
        if let cell = collectionView.cellForItem(at: indexPath) as? AnimeCollectionViewCell,
           Hover.shared.handleTouchSelection(source: cell,
                                             host: self,
                                             media: item,
                                             actions: hayasePreviewCardActions(),
                                             alignsToCardStart: indexPath.item == 0) {
            return
        }
        Router.shared.navigateToAnime(item, hostTabIndex: hayaseTabIndex)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        Hover.shared.scrollDidOccur()
        syncBannerToCurrentScrollPosition()
    }
}

// MARK: - Search

extension HomeViewController {
    /// `goto('/#/app/search', { state: { search: variables } })` for a section.
    func search(_ section: HomeSectionData) {
        let state = Route.SearchState(
            genres: section.filterGenre.map { SearchValues.genreSet.contains($0) ? [$0] : [] } ?? [],
            tags: section.filterGenre.map { SearchValues.genreSet.contains($0) ? [] : [$0] } ?? [],
            year: section.filterYear,
            season: section.filterSeason,
            formats: section.filterFormats,
            statuses: section.filterStatus ?? [],
            sort: section.filterSort,
            onList: section.filterOnList,
            ids: section.filterIDs)
        Router.shared.navigate(.search(state), hostTabIndex: hayaseTabIndex)
    }

    /// `goto('/#/app/search', { state: { search: { … } } })` for a button of the banner.
    func search(_ filter: BannerFilter) {
        var state = Route.SearchState()
        switch filter {
        case .format(let format):
            state.formats = format.map { [$0] } ?? []
        case .status(let status):
            state.statuses = status.map { [$0] } ?? []
        case .season(let season, let year):
            state.season = season
            state.year = year.map(String.init)
        case .score:
            state.sort = "SCORE_DESC"
        case .genre(let genre):
            let isGenre = SearchValues.genreSet.contains(genre)
            state.genres = isGenre ? [genre] : []
            state.tags = isGenre ? [] : [genre]
        }
        Router.shared.navigate(.search(state), hostTabIndex: hayaseTabIndex)
    }
}
