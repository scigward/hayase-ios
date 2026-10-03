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
//  components/ui/banner and components/ui/cards; the sections and their queries are in Sections.swift,
//  the header of a section in SectionHeader.swift, and in the extensions of this file the data source
//  and what scrolling does to the banner.
//

import UIKit
import CoreData

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
