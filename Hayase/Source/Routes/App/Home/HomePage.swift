//
//  HomePage.swift
//  Hayase
//
//  Mirrors: interface routes/app/home/+page.svelte
//
//      <div class='grow h-full min-w-0 -ml-14 pl-14 overflow-y-scroll' on:scroll={handleScroll}>
//        <Banner />
//        {#each $sectionQueries as { title, query, variables }}
//          <div class='flex px-4 pt-5 …'> title, View More </div>
//          <div class='flex overflow-x-scroll …'> <QueryCard {query} /> </div>
//
//  The page is a banner and a row of cards for every section. What the pieces are is in
//  components/ui/banner and components/ui/cards; the sections and their queries (`HomeSections`) and the
//  header of a section (`HomeSectionHeaderView`) are at the end of this file, and in the extensions the data
//  source and what scrolling does to the banner.
//

import CoreData
import UIKit

final class HomeViewController: UIViewController {
    var renderedDisplayPreferences: Settings.DisplayPreferences?

    // MARK: - Content

    let homeSections = HomeSections()
    /// What the banner's query has to show; it is the first section of the collection view.
    var bannerState: BannerState = .fetching
    let bannerQuery = PageQuery<[AnimeItem]>()
    private var bannerObserverID: UUID?

    var collectionView: UICollectionView!

    // MARK: - The banner image
    // banner-image.svelte is not part of the route: it is drawn behind it, and the route says
    // whether it has been scrolled out of sight (`hideBanner`).

    let backdropView = BannerImageView()
    let backdropCoverView: UIView = {
        let view = UIView()
        view.backgroundColor = hayasePageBackground
        view.alpha = 0
        view.isUserInteractionEnabled = false
        return view
    }()
    var isBackdropCovered = false
    var backdropCoverTransitionID = 0
    var pendingBannerRevealWorkItem: DispatchWorkItem?
    let bannerRevealDelay: DispatchTimeInterval = .milliseconds(120)
    private var backdropLeadingConstraint: NSLayoutConstraint?
    private var backdropTrailingConstraint: NSLayoutConstraint?

    var selectedFeaturedID: Int?
    private var hasAppeared = false

    // MARK: - Init (set tabBarItem before viewDidLoad so tab bar reads it at launch)

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Home",
            image: UIImage.hayaseIcon("house"),
            selectedImage: UIImage.hayaseIcon("house"))
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Clip at the view level so the banner does not overflow beyond the screen,
        // but the collection view itself doesn't clip (the banner runs past its own height).
        view.clipsToBounds = true
        title = nil   // home/+page.svelte has no title: the content starts at the top
        setupBackdrop()
        setupCollectionView()
        homeSections.delegate = self
        load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hayase has no top nav bar on Home, the content starts at the top
        navigationController?.setNavigationBarHidden(true, animated: animated)
        collectionView.indexPathsForSelectedItems?.forEach {
            collectionView.deselectItem(at: $0, animated: animated)
        }
        // The interface builds Home again on every visit, so the banner starts over.
        if hasAppeared { remountFeaturedBanner() }
        hasAppeared = true
        // Re-sync the banner with the current scroll position: `hideBanner.value = false` when the
        // page mounts, then `scrollTop > 100`. scrollViewDidScroll does not fire when the view
        // comes back (popping back from a detail page), so the banner could be stuck hidden.
        syncBannerToCurrentScrollPosition()
        (collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? FullBannerCell)?.republishSidebarBackdrop()
        let preferences = Settings.DisplayPreferences()
        if let previous = renderedDisplayPreferences, previous != preferences {
            if previous.showAdultContent != preferences.showAdultContent ||
                previous.accountLanguage != preferences.accountLanguage {
                load()
            } else {
                collectionView.reloadData()
            }
        }
        renderedDisplayPreferences = preferences
        homeSections.refreshIfLocalListsChanged()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Hover.shared.unhoverLastElement()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateBackdropLayout()
        disableOrthogonalScrollerClipping(in: collectionView, excluding: collectionView)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard isViewLoaded else { return }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.collectionView.setCollectionViewLayout(self.makeLayout(), animated: false)
            self.updateBackdropLayout(for: size.height)
        })
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded,
              traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass else { return }
        (collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? FullBannerCell)?.setNeedsLayout()
        updateBackdropLayout()
        // The height of the banner changes between 70vh and 80vh
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // With contentInsetAdjustmentBehavior = .never, manually account for the tab bar
        // so the last section's content isn't hidden under it
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom
    }

    deinit {
        pendingBannerRevealWorkItem?.cancel()
        if let bannerObserverID { bannerQuery.removeObserver(bannerObserverID) }
        bannerQuery.pause()
    }

    // MARK: - Setup

    private func setupBackdrop() {
        view.backgroundColor = hayasePageBackground
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        backdropCoverView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdropView)
        view.addSubview(backdropCoverView)
        let leading = backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let trailing = backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        backdropLeadingConstraint = leading
        backdropTrailingConstraint = trailing
        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            leading,
            trailing,
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backdropCoverView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropCoverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropCoverView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropCoverView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        updateBackdropLayout()
    }

    private func setupCollectionView() {
        collectionView = AnimeCardCollectionView(frame: .zero, collectionViewLayout: makeLayout())
        // The banner image is drawn behind the page. Keep the collection clear so the 90vh fade
        // can show behind the first section without being painted over by a hard black viewport.
        collectionView.backgroundColor = .clear
        // .never so the banner extends behind the status bar, as the interface's
        // `position:absolute; top:0; left:0` banner image does
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.bounces = false
        collectionView.alwaysBounceVertical = false
        Banner.register(in: collectionView)
        QueryCard.register(in: collectionView)
        collectionView.register(HomeSectionHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: HomeSectionHeaderView.reuseID)
        view.addSubview(collectionView)
        collectionView.clipsToBounds = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        let viewportWidth = view.window?.rootViewController?.view.bounds.width ?? view.bounds.width
        let viewHeight = view.bounds.height > 0 ? view.bounds.height : UIScreen.main.bounds.height
        let bannerHeight = Banner.height(viewportWidth: viewportWidth, viewHeight: viewHeight)
        return UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ -> NSCollectionLayoutSection? in
            if sectionIndex == 0 {
                return Banner.layoutSection(height: bannerHeight)
            }
            // The sections mirror home/+page.svelte:
            //   header: flex px-4 pt-5 items-end
            //   row:    flex overflow-x-scroll -mb-5 pb-5
            let rows = self?.homeSections.rows ?? []
            let state = rows[safe: sectionIndex - 1]?.contentState ?? .fetching
            let section = QueryCard.layoutSection(for: state)
            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                    heightDimension: .absolute(HomeSectionHeaderView.height))
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top)
            section.boundarySupplementaryItems = [header]
            return section
        }
    }

    private func disableOrthogonalScrollerClipping(in view: UIView, excluding rootScrollView: UIScrollView) {
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView, scrollView !== rootScrollView {
                scrollView.clipsToBounds = false
                scrollView.layer.masksToBounds = false
            }
            disableOrthogonalScrollerClipping(in: subview, excluding: rootScrollView)
        }
    }

    // MARK: - The banner image's place

    private func updateBackdropLayout(for height: CGFloat? = nil) {
        let viewHeight = height ?? (view.bounds.height > 0 ? view.bounds.height : UIScreen.main.bounds.height)
        let viewportSize = view.window?.bounds.size ?? view.bounds.size
        // `-ml-14 pl-14`: the image starts at the app's left edge, not after the 56pt sidebar
        backdropLeadingConstraint?.constant = Self.usesDesktopSidebar(viewportSize: viewportSize,
                                                                      traits: traitCollection) ? -56 : 0
        backdropTrailingConstraint?.constant = 0
        backdropView.configureForLayout(isRegular: viewportSize.width >= 768, viewHeight: viewHeight)
    }

    private static func usesDesktopSidebar(viewportSize: CGSize, traits: UITraitCollection) -> Bool {
        let isPhoneLandscape = traits.userInterfaceIdiom == .phone
            && viewportSize.width > viewportSize.height
            && viewportSize.width >= 568
        return viewportSize.width >= 768
            || traits.horizontalSizeClass == .regular
            || isPhoneLandscape
    }

    // MARK: - Loading

    /// Loads the page: the banner's query, which is not paused, and the sections.
    private func load() {
        backdropView.isHidden = false
        selectedFeaturedID = nil
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        loadBanner()
        homeSections.reload()
    }

    private func loadBanner() {
        if let bannerObserverID { bannerQuery.removeObserver(bannerObserverID) }
        bannerState = .fetching
        bannerObserverID = bannerQuery.observe { [weak self] state in
            self?.applyBannerState(state)
        }
        // Interface Banner is an active query. It is intentionally separate from
        // the paused row queries so the hero can load without waking every row.
        AniListClient.shared.fetchBannerItemsResult(policy: .cacheAndNetwork, query: bannerQuery) { _ in }
    }

    private func applyBannerState(_ state: PageQuery<[AnimeItem]>.State) {
        let next: BannerState
        switch state {
        case .idle, .paused:
            next = .fetching
        case .fetching(let previous):
            next = previous.map { BannerState.loaded($0) } ?? .fetching
        case .success(let items):
            next = .loaded(items)
        case .empty:
            next = .loaded([])
        case .failure(let error, let previous):
            next = previous.map { BannerState.loaded($0) }
                ?? .failed((error as? AniListRequestError)?.description ?? error.localizedDescription)
        }
        // the skeleton that is already there stays
        if case .fetching = bannerState, case .fetching = next { return }
        bannerState = next
        guard isViewLoaded, collectionView.numberOfSections > 0 else { return }
        let indexPath = IndexPath(item: 0, section: 0)
        if case .loaded(let items) = next,
           let cell = collectionView.cellForItem(at: indexPath) as? FullBannerCell {
            cell.configure(with: items, selectedID: selectedFeaturedID)
        } else {
            collectionView.reloadItems(at: [indexPath])
        }
        DispatchQueue.main.async { self.syncBannerToCurrentScrollPosition() }
    }
}

// MARK: - HomeSectionsDelegate

extension HomeViewController: HomeSectionsDelegate {
    func homeSectionsDidReset(_ sections: HomeSections) {
        guard isViewLoaded else { return }
        collectionView.reloadData()
    }

    func homeSections(_ sections: HomeSections, didUpdateRow row: Int, from previous: HomeSectionData, to next: HomeSectionData) {
        let collectionSection = row + 1
        guard isViewLoaded, collectionView.numberOfSections > collectionSection else { return }
        // A row may be another height now: a card is 323pt, a skeleton 322pt and a message 320pt.
        collectionView.collectionViewLayout.invalidateLayout()
        if QueryCard.canFlip(from: previous, to: next) {
            let previousFrames = QueryCard.visibleFrames(in: collectionView, section: collectionSection, items: previous.items)
            UIView.performWithoutAnimation {
                collectionView.reloadSections(IndexSet(integer: collectionSection))
                collectionView.layoutIfNeeded()
            }
            QueryCard.animateFlip(in: collectionView, section: collectionSection, items: next.items, from: previousFrames)
        } else {
            collectionView.reloadSections(IndexSet(integer: collectionSection))
        }
        DispatchQueue.main.async { self.syncBannerToCurrentScrollPosition() }
    }
}

// MARK: - HomePage+Banner

//  Mirrors: `handleScroll` of interface routes/app/home/+page.svelte
//
//      function handleScroll (e: Event) {
//        const target = e.target as HTMLDivElement
//        hideBanner.value = target.scrollTop > 100
//      }
//      hideBanner.value = false
//
//  `hideBanner` is what banner-image.svelte reads to fade the picture to 5%. The picture here is
//  drawn behind the route, and a cover of the page's background hides it while the page is scrolled
//  past: a card row's gaps would otherwise show the faint picture through them.

extension HomeViewController {
    /// Applies the banner scroll effects based on the current contentOffset.
    /// Must be called any time the scroll position or the banner cell could be stale:
    ///   • from scrollViewDidScroll (every scroll event)
    ///   • from viewWillAppear (returning from a child VC — scrollViewDidScroll won't re-fire)
    ///   • after reloadData() (prepareForReuse resets the cell; the scroll event won't re-fire)
    func syncBannerToCurrentScrollPosition() {
        let offsetY = collectionView.contentOffset.y
        let bannerCell = collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? FullBannerCell

        if offsetY < 0 {
            // A real pull-down is an intentional reveal. Apply it immediately.
            cancelPendingBannerReveal()
            applyBannerVisibility(hidden: false, bannerCell: bannerCell)
            return
        }

        if offsetY > BannerImage.hideThreshold {
            // Hide immediately. The cover is a bleed-prevention mask, so it must
            // not spend frames half-transparent while rows are already over it.
            cancelPendingBannerReveal()
            applyBannerVisibility(hidden: true, bannerCell: bannerCell)
        } else if shouldRevealBannerImmediately(offsetY: offsetY) {
            cancelPendingBannerReveal()
            applyBannerVisibility(hidden: false, bannerCell: bannerCell)
        } else {
            // UIKit can chatter around 100 during rebound/deceleration. Do not
            // start a visible fade-in unless the scroll position stays on the
            // visible side of the threshold for a short moment.
            scheduleBannerRevealIfNeeded()
        }
    }

    /// A banner that is not on screen starts over the next time it is configured.
    func remountFeaturedBanner() {
        selectedFeaturedID = nil
        (collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? FullBannerCell)?.remount()
    }

    private func shouldRevealBannerImmediately(offsetY: CGFloat) -> Bool {
        guard offsetY > 0 else { return true }
        if collectionView.isDragging {
            return collectionView.panGestureRecognizer.velocity(in: collectionView).y > 0
        }
        return !collectionView.isDecelerating && !collectionView.isTracking
    }

    private func applyBannerVisibility(hidden: Bool, bannerCell: FullBannerCell?) {
        bannerCell?.setBannerHidden(hidden)
        transitionBackdropCover(hidden: hidden)
    }

    private func scheduleBannerRevealIfNeeded() {
        guard pendingBannerRevealWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingBannerRevealWorkItem = nil
            guard self.collectionView.contentOffset.y <= BannerImage.hideThreshold else { return }
            let bannerCell = self.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? FullBannerCell
            self.applyBannerVisibility(hidden: false, bannerCell: bannerCell)
        }
        pendingBannerRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + bannerRevealDelay, execute: workItem)
    }

    private func cancelPendingBannerReveal() {
        pendingBannerRevealWorkItem?.cancel()
        pendingBannerRevealWorkItem = nil
    }

    /// `transition-opacity duration-500` of the banner image, as the fade of the cover.
    private func transitionBackdropCover(hidden: Bool) {
        let targetCoverAlpha: CGFloat = hidden ? 1 : 0
        guard hidden != isBackdropCovered || abs(backdropCoverView.alpha - targetCoverAlpha) > 0.001 else { return }

        backdropCoverTransitionID += 1
        let transitionID = backdropCoverTransitionID
        isBackdropCovered = hidden

        if hidden {
            // Fade the mask itself instead of fading the gradient under a
            // semi-transparent mask. Once fully covered, park the backdrop at
            // its hidden alpha behind the mask so card gaps stay protected.
            backdropView.setFaded(false, animated: false)
            BannerImage.fade([backdropCoverView], to: 1) { [weak self] in
                guard let self, self.backdropCoverTransitionID == transitionID else { return }
                self.backdropView.setFaded(true, animated: false)
            }
        } else {
            // Prepare the full banner while it is still hidden by the mask, then
            // fade only the mask away. This avoids exposing an animating radial
            // gradient/cropped image during upward threshold crossings.
            backdropView.setFaded(false, animated: false)
            BannerImage.fade([backdropCoverView], to: 0)
        }
    }
}

// MARK: - HomePage+DataSource

//  Mirrors: the `{#each $sectionQueries}` of interface routes/app/home/+page.svelte, and the
//  `goto('/#/app/search', { state: { search: variables } })` that its titles and buttons lead to.

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

// MARK: - SectionHeader

//  Mirrors: the header of each section of interface routes/app/home/+page.svelte
//
//      <div class='flex px-4 pt-5 items-end cursor-pointer text-muted-foreground relative z-[1]'>
//        <div class='font-semibold text-lg leading-none select:text-foreground' use:click={() => search(variables)}>{title}</div>
//        <div class='ml-auto text-xs select:text-foreground' use:click={() => search(variables)}>View More</div>
//
//  Both texts lead to the same search, and both turn `text-foreground` while hovered, focused or
//  pressed. `items-end` lines up the bottoms of their line boxes, not their baselines.

final class HomeSectionHeaderView: UICollectionReusableView {
    static let reuseID = "HomeSectionHeader"
    /// `pt-5` and the 18pt line of the title
    static let height: CGFloat = 38

    /// Either text was clicked.
    var onViewMore: (() -> Void)?

    // text-lg leading-none: 18pt on a line of 18pt
    private let titleControl = HeaderTextControl(font: .nunito(ofSize: 18, weight: .semibold), lineHeight: 18)
    // text-xs: 12pt on a line of 16pt
    private let viewMoreControl = HeaderTextControl(font: .nunito(ofSize: 12), lineHeight: 16)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        viewMoreControl.setText("View More")
        [titleControl, viewMoreControl].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.addTarget(self, action: #selector(tapped), for: .touchUpInside)
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            // px-4, and the row ends at the bottom of the tallest box: `items-end`
            titleControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleControl.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleControl.heightAnchor.constraint(equalToConstant: 18),
            viewMoreControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            viewMoreControl.bottomAnchor.constraint(equalTo: bottomAnchor),
            viewMoreControl.heightAnchor.constraint(equalToConstant: 16),
            viewMoreControl.leadingAnchor.constraint(greaterThanOrEqualTo: titleControl.trailingAnchor),
        ])
    }

    @objc private func tapped() { onViewMore?() }

    func configure(title: String) {
        titleControl.setText(title)
        accessibilityLabel = title
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onViewMore = nil
    }
}

// MARK: - HeaderTextControl

/// A text with `select:text-foreground`: muted until it is hovered or pressed. Like every element
/// that can be focused, it also shrinks to 98% while it is pressed.
private final class HeaderTextControl: UIControl, NoActiveScale {
    private let label = UILabel()
    private let font: UIFont
    private let lineHeight: CGFloat
    private var text = ""
    private var isHovered = false
    private var pressAnimator: UIViewPropertyAnimator?

    init(font: UIFont, lineHeight: CGFloat) {
        self.font = font
        self.lineHeight = lineHeight
        super.init(frame: .zero)
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        accessibilityTraits = .button
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setText(_ text: String) {
        self.text = text
        applyText()
    }

    private func applyText() {
        let selected = isHighlighted || isHovered
        label.attributedText = CSSText.string(text, font: font,
                                              color: selected ? UIColor.HayaseTheme.foreground : UIColor.HayaseTheme.mutedForeground,
                                              lineHeight: lineHeight)
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isHovered = recognizer.state == .began || recognizer.state == .changed
        applyText()
    }

    override var isHighlighted: Bool {
        didSet {
            applyText()
            pressAnimator?.stopAnimation(true)
            pressAnimator = nil
            guard isHighlighted else {
                transform = .identity
                return
            }
            let animator = UIViewPropertyAnimator(duration: 0.1,
                                                  controlPoint1: CGPoint(x: 0.42, y: 0),
                                                  controlPoint2: CGPoint(x: 0.58, y: 1)) {
                self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            }
            pressAnimator = animator
            animator.startAnimation()
        }
    }
}

// MARK: - Sections

//  Mirrors: the script of interface routes/app/home/+page.svelte
//
//  The sections of Home and their queries: "Continue Watching", "Your List" and "Sequels You Missed"
//  for whoever is signed in, then the seven that everyone gets. A section's query waits (paused)
//  until its row is on screen, except for "Continue Watching" and the banner, which do not.

protocol HomeSectionsDelegate: AnyObject {
    /// The rows were replaced, as a whole.
    func homeSectionsDidReset(_ sections: HomeSections)
    /// One row has another state or other media. The model has the new one already; `previous` is
    /// what the screen still shows.
    func homeSections(_ sections: HomeSections, didUpdateRow row: Int, from previous: HomeSectionData, to next: HomeSectionData)
}

enum HomeSectionLoadKind {
    case generic(AniListHomeSectionDefinition)
    case ids(ids: [Int], status: [String]?, onList: Bool?, sort: [String]?, preserveOrder: Bool)
}

/// A section: its title, how it is loaded and the `search` its "View More" goes to.
struct HomeSectionDescriptor {
    let id: String
    let title: String
    let startsPaused: Bool
    let kind: HomeSectionLoadKind
    let filterGenre: String?
    let filterSort: String?
    let filterIDs: [Int]?
    let filterStatus: [String]?
    let filterOnList: Bool?
    let filterSeason: String?
    let filterYear: String?
    let filterFormats: [String]
}

final class HomeSections {
    weak var delegate: HomeSectionsDelegate?

    private(set) var rows: [HomeSectionData] = []

    private var descriptors: [String: HomeSectionDescriptor] = [:]
    private var queries: [String: PageQuery<HomeSectionData>] = [:]
    private var observerIDs: [String: UUID] = [:]
    /// The rows that have been on screen: their queries are no longer paused.
    private var visibleIDs = Set<String>()
    private var personalLoadID = 0
    private var lastLocalContinueIDs: [Int] = []
    private var lastLocalPlanningIDs: [Int] = []
    private var refreshTimer: Timer?
    private var trackingObserver: NSObjectProtocol?

    init() {
        trackingObserver = NotificationCenter.default.addObserver(forName: LocalTracking.didChange,
                                                                  object: nil,
                                                                  queue: .main) { [weak self] notification in
            self?.trackingDidChange(notification)
        }
    }

    deinit {
        if let trackingObserver { NotificationCenter.default.removeObserver(trackingObserver) }
        refreshTimer?.invalidate()
        removeQueries(where: { _ in true })
    }

    // MARK: Loading

    /// Loads Home's sections again from the start.
    func reload() {
        personalLoadID += 1
        lastLocalContinueIDs = []
        lastLocalPlanningIDs = []
        visibleIDs.removeAll()
        removeQueries(where: { _ in true })

        install(genericDescriptors(), resetPersonalQueries: true)
        refreshPersonal(fetchRemoteLists: true)
    }

    private func genericDescriptors() -> [HomeSectionDescriptor] {
        AniListClient.shared.homeSectionDefinitions().map { definition in
            HomeSectionDescriptor(
                id: definition.id,
                title: definition.title,
                startsPaused: definition.startsPaused,
                kind: .generic(definition),
                filterGenre: (definition.variables["genre"] as? [String])?.first,
                filterSort: (definition.variables["sort"] as? [String])?.first,
                filterIDs: nil,
                filterStatus: nil,
                filterOnList: nil,
                filterSeason: definition.variables["season"] as? String,
                filterYear: (definition.variables["seasonYear"] as? Int).map(String.init),
                filterFormats: definition.variables["format"] as? [String] ?? [])
        }
    }

    private func personalDescriptors(userListIDs: AniListTracking.UserListIDs?) -> [HomeSectionDescriptor] {
        // `authAggregator`: AniList's lists, or those of the first other tracker that is signed in
        let otherLists = TrackerAggregator.listIDs()
        let localContinueIDs = otherLists.continueIDs
        let localPlanningIDs = otherLists.planningIDs
        lastLocalContinueIDs = localContinueIDs
        lastLocalPlanningIDs = localPlanningIDs
        let hasAniList = TrackerAccountManager.shared.isLoggedIn(.anilist)
        let continueIDs = userListIDs?.continueIDs ?? (hasAniList ? [] : localContinueIDs)
        let planningIDs = userListIDs?.planningIDs ?? (hasAniList ? [] : localPlanningIDs)
        let sequelIDs = userListIDs?.sequelIDs ?? []

        var descriptors: [HomeSectionDescriptor] = []
        if !continueIDs.isEmpty {
            let ids = Array(continueIDs.prefix(50))
            descriptors.append(HomeSectionDescriptor(
                id: "personal.continue",
                title: "Continue Watching",
                startsPaused: false,
                kind: .ids(ids: ids, status: nil, onList: nil, sort: ["UPDATED_AT_DESC"], preserveOrder: true),
                filterGenre: nil,
                filterSort: "UPDATED_AT_DESC",
                filterIDs: continueIDs,
                filterStatus: nil,
                filterOnList: nil,
                filterSeason: nil,
                filterYear: nil,
                filterFormats: []))
        }
        if !planningIDs.isEmpty {
            descriptors.append(HomeSectionDescriptor(
                id: "personal.planning",
                title: "Your List",
                startsPaused: true,
                kind: .ids(ids: planningIDs, status: ["FINISHED", "RELEASING"], onList: nil, sort: ["START_DATE_DESC"], preserveOrder: false),
                filterGenre: nil,
                filterSort: "START_DATE_DESC",
                filterIDs: planningIDs,
                filterStatus: ["FINISHED", "RELEASING"],
                filterOnList: nil,
                filterSeason: nil,
                filterYear: nil,
                filterFormats: []))
        }
        if !sequelIDs.isEmpty {
            descriptors.append(HomeSectionDescriptor(
                id: "personal.sequels",
                title: "Sequels You Missed",
                startsPaused: true,
                kind: .ids(ids: sequelIDs, status: ["FINISHED", "RELEASING"], onList: false, sort: nil, preserveOrder: false),
                filterGenre: nil,
                filterSort: nil,
                filterIDs: sequelIDs,
                filterStatus: ["FINISHED", "RELEASING"],
                filterOnList: false,
                filterSeason: nil,
                filterYear: nil,
                filterFormats: []))
        }
        return descriptors
    }

    private func refreshPersonal(fetchRemoteLists: Bool) {
        personalLoadID += 1
        let loadID = personalLoadID
        let applyLists: (AniListTracking.UserListIDs?) -> Void = { [weak self] userListIDs in
            guard let self else { return }
            guard loadID == self.personalLoadID else { return }
            let personal = self.personalDescriptors(userListIDs: userListIDs)
            self.install(personal + self.genericDescriptors(), resetPersonalQueries: true)
        }

        if fetchRemoteLists {
            AniListTracking.shared.fetchUserLists(completion: applyLists)
        } else {
            applyLists(AniListTracking.shared.cachedUserLists())
        }
    }

    private func install(_ newDescriptors: [HomeSectionDescriptor], resetPersonalQueries: Bool) {
        if resetPersonalQueries {
            removeQueries(where: { $0.hasPrefix("personal.") })
        }

        let newIDs = Set(newDescriptors.map(\.id))
        removeQueries(where: { !newIDs.contains($0) })
        descriptors = Dictionary(newDescriptors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let existing = Dictionary(rows.compactMap { section -> (String, HomeSectionData)? in
            guard let id = section.queryID else { return nil }
            return (id, section)
        }, uniquingKeysWith: { first, _ in first })
        rows = newDescriptors.map { descriptor in
            existing[descriptor.id] ?? placeholderSection(for: descriptor)
        }
        delegate?.homeSectionsDidReset(self)

        for descriptor in newDescriptors where queries[descriptor.id] == nil {
            configureQuery(for: descriptor)
        }
        resumeVisible()
    }

    private func configureQuery(for descriptor: HomeSectionDescriptor) {
        let query = PageQuery<HomeSectionData>()
        queries[descriptor.id] = query
        observerIDs[descriptor.id] = query.observe { [weak self] state in
            self?.apply(state, for: descriptor)
        }

        switch descriptor.kind {
        case .generic(let definition):
            let policy: AniListRequestPolicy = descriptor.startsPaused ? .pausedUntilVisible : .cacheAndNetwork
            AniListClient.shared.fetchHomeSectionResult(definition: definition, policy: policy, query: query) { _ in }
        case .ids:
            if descriptor.startsPaused {
                query.preparePaused { [weak self, weak query] in
                    self?.startPersonalFetch(descriptor, query: query)
                    return nil
                }
            } else {
                startPersonalFetch(descriptor, query: query)
            }
        }
    }

    @discardableResult
    private func startPersonalFetch(_ descriptor: HomeSectionDescriptor,
                                    query: PageQuery<HomeSectionData>?) -> AniListRequestToken? {
        guard case .ids(let ids, let status, let onList, let sort, let preserveOrder) = descriptor.kind else { return nil }
        query?.setFetching(previous: row(for: descriptor.id))
        return AniListClient.shared.searchAnimeItemsPage(
            title: nil,
            genres: [],
            tags: [],
            formats: [],
            statuses: status ?? [],
            sort: sort?.first,
            onList: onList,
            ids: ids,
            policy: .cacheAndNetwork
        ) { [weak self, weak query] result in
            guard let self else { return }
            switch result {
            case .success(let page):
                let items: [AnimeItem]
                if preserveOrder {
                    var byID: [Int: AnimeItem] = [:]
                    page.items.forEach { byID[$0.id] = $0 }
                    items = ids.compactMap { byID[$0] }
                } else {
                    items = page.items
                }
                var section = self.sectionData(for: descriptor, items: items)
                section.contentState = items.isEmpty ? .empty : .loaded
                query?.setSuccess(section, isEmpty: items.isEmpty)
            case .failure(let error):
                query?.setFailure(error, previous: self.row(for: descriptor.id))
            }
        }
    }

    private func apply(_ state: PageQuery<HomeSectionData>.State, for descriptor: HomeSectionDescriptor) {
        var section: HomeSectionData
        switch state {
        case .idle:
            section = placeholderSection(for: descriptor, state: .idle)
        case .paused:
            section = placeholderSection(for: descriptor, state: .paused)
        case .fetching(let previous):
            section = previous ?? row(for: descriptor.id) ?? placeholderSection(for: descriptor)
            section.contentState = .fetching
        case .success(let value):
            section = value
            section.contentState = section.items.isEmpty ? .empty : .loaded
        case .empty:
            section = row(for: descriptor.id) ?? placeholderSection(for: descriptor)
            section.items = []
            section.contentState = .empty
        case .failure(let error, let previous):
            section = previous ?? row(for: descriptor.id) ?? placeholderSection(for: descriptor)
            section.contentState = .failed((error as? AniListRequestError)?.description ?? error.localizedDescription)
        }
        update(section, id: descriptor.id)
    }

    private func placeholderSection(for descriptor: HomeSectionDescriptor,
                                    state: HomeSectionContentState? = nil) -> HomeSectionData {
        var section = sectionData(for: descriptor, items: [])
        section.contentState = state ?? (descriptor.startsPaused ? .paused : .fetching)
        return section
    }

    private func sectionData(for descriptor: HomeSectionDescriptor, items: [AnimeItem]) -> HomeSectionData {
        var section = HomeSectionData(title: descriptor.title, items: items)
        section.queryID = descriptor.id
        section.filterGenre = descriptor.filterGenre
        section.filterSort = descriptor.filterSort
        section.filterIDs = descriptor.filterIDs
        section.filterStatus = descriptor.filterStatus
        section.filterOnList = descriptor.filterOnList
        section.filterSeason = descriptor.filterSeason
        section.filterYear = descriptor.filterYear
        section.filterFormats = descriptor.filterFormats
        return section
    }

    private func row(for id: String) -> HomeSectionData? {
        rows.first { $0.queryID == id }
    }

    private func update(_ section: HomeSectionData, id: String) {
        guard let index = rows.firstIndex(where: { $0.queryID == id }) else { return }
        let previous = rows[index]
        rows[index] = section
        delegate?.homeSections(self, didUpdateRow: index, from: previous, to: section)
    }

    // MARK: Visibility

    /// `QueryCard`'s `deferredLoad`: the query starts once its row is on screen.
    func resume(row: Int) {
        guard row >= 0, row < rows.count, let id = rows[row].queryID else { return }
        visibleIDs.insert(id)
        _ = queries[id]?.resume()
    }

    private func resumeVisible() {
        for id in visibleIDs {
            _ = queries[id]?.resume()
        }
    }

    private func removeQueries(where shouldRemove: (String) -> Bool) {
        for id in Array(queries.keys) where shouldRemove(id) {
            if let observerID = observerIDs[id] {
                queries[id]?.removeObserver(observerID)
            }
            queries[id]?.pause()
            queries[id] = nil
            observerIDs[id] = nil
            descriptors[id] = nil
            visibleIDs.remove(id)
        }
    }

    // MARK: Lists changing

    private func trackingDidChange(_ notification: Notification) {
        let hasAniList = TrackerAccountManager.shared.isLoggedIn(.anilist)
        let currentOtherLists = TrackerAggregator.listIDs()
        let currentLocalContinueIDs = currentOtherLists.continueIDs
        let currentLocalPlanningIDs = currentOtherLists.planningIDs
        let remoteListChanged = notification.object is AniListTracking
        guard remoteListChanged ||
              (!hasAniList &&
               (currentLocalContinueIDs != lastLocalContinueIDs ||
                currentLocalPlanningIDs != lastLocalPlanningIDs)) else { return }
        if !hasAniList, currentLocalContinueIDs != lastLocalContinueIDs {
            applyLocalContinueWatchingOrder(currentLocalContinueIDs)
        }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.refreshPersonal(fetchRemoteLists: remoteListChanged)
        }
    }

    /// The lists of another tracker can change while Home is not on screen.
    func refreshIfLocalListsChanged() {
        guard !TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
        let currentOtherLists = TrackerAggregator.listIDs()
        guard currentOtherLists.continueIDs != lastLocalContinueIDs ||
              currentOtherLists.planningIDs != lastLocalPlanningIDs else { return }
        refreshPersonal(fetchRemoteLists: false)
    }

    private func applyLocalContinueWatchingOrder(_ ids: [Int]) {
        guard !ids.isEmpty,
              let index = rows.firstIndex(where: { $0.queryID == "personal.continue" }),
              case .loaded = rows[index].contentState,
              !rows[index].items.isEmpty else { return }

        var byID: [Int: AnimeItem] = [:]
        rows[index].items.forEach { byID[$0.id] = $0 }
        var reordered = ids.compactMap { byID[$0] }
        let visibleItemIDs = Set(reordered.map(\.id))
        reordered.append(contentsOf: rows[index].items.filter { !visibleItemIDs.contains($0.id) })
        guard reordered.map(\.id) != rows[index].items.map(\.id) else { return }

        var section = rows[index]
        section.items = reordered
        section.filterIDs = ids
        update(section, id: "personal.continue")
    }
}
