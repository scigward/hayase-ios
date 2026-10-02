//
//  SearchViewController.swift
//  NyaiS
//
//  Mirrors: src/routes/app/search/+page.svelte and src/lib/components/ui/cards/query.svelte,
//  trace.svelte and episode.svelte
//
//  Hayase-style AniList anime search tab.
//
//  Compact layout:
//  Title label + input + [image] [bolt]  - always visible
//  Labeled filter panels (horizontal scroll) - when bolt tapped
//  Wrapping active chips row
//  Grid of cards, each a 184pt column (`minmax(184px, max-content)`)
//
//  From `md` (768) the title and the filters wrap over rows of their own, and the buttons
//  follow the last of them.

import UIKit
import PhotosUI

private enum SearchHeaderItem {
    case title
    case filter(SearchFilterType)
    case actions
}

// MARK: - SearchViewController

class SearchViewController: UIViewController {
    private var renderedDisplayPreferences: Settings.DisplayPreferences?

    // MARK: - Hayase color constants
    private static let bgBlack      = UIColor.black
    private static let bgBackground = UIColor.HayaseTheme.background
    private static let foreground   = UIColor.HayaseTheme.foreground

    // MARK: - Search state (`search` in +page.svelte)
    // genres/tags, formats and status multi-select; year/season/sort/onList single-select.

    /// `search.genres`: genres and tags together, in the order they were picked.
    private var selectedGenreTags: [String] = []
    private var selectedGenres: [String] { selectedGenreTags.filter { SearchValues.genreSet.contains($0) } }
    private var selectedTags: [String] { selectedGenreTags.filter { !SearchValues.genreSet.contains($0) } }
    private var selectedYear:     String?  = nil
    private var selectedSeason:   String?  = nil
    private var selectedFormats:  [String] = []
    private var selectedStatuses: [String] = []
    private var selectedSort:     String?  = "TRENDING_DESC"
    private var selectedOnList:   Bool?    = nil
    /// `search.name`
    private var currentTitle = ""
    /// `inputText`: what the input holds. `search.name` only follows it once typing settles.
    private var inputText = ""
    /// Whether the cards on screen are episode cards: a flip only moves cards of the same kind.
    private var renderedEpisodeCards = false
    /// Where each page of results begins: query.svelte's `i === 0` is the first card of every page.
    private var pageStartIndexes: Set<Int> = [0]
    /// `search.ids`
    private var traceIds: [Int]?
    /// `trace`: the frames trace.moe matched. Set by a lookup, and kept when only the IDs chip goes.
    private var traceMatches: [TraceAnime]?

    /// The order `list(search)` goes through the values in: the object a page starts with has
    /// them in one order, the one `variablesToSearch` builds from a remembered state in another.
    private var chipsFollowRestoredState = false
    private var activeChipEntries: [(label: String, type: SearchFilterType, apiValue: String)] = []

    // MARK: - Results state
    private var animeResults: [AnimeItem] = []
    private var currentPage  = 1
    private var hasNextPage  = true
    private var isFetching   = false
    /// When true, show skeleton placeholder cells instead of real results (matches web fetching state)
    private var isShowingSkeleton = true
    /// Incremented on every reset fetch. Allows in-flight callbacks from a prior fetch to be
    /// discarded when a newer reset (e.g. from a View More prefill) has already started.
    private var fetchRequestID = 0
    private var searchTask: AniListRequestToken?
    private let searchQuery = PageQuery<AniListSearchPage>()
    private var debounceTimer: Timer?
    private var trackingRefreshTimer: Timer?
    private var lastFilterLayoutSignature = ""
    private let searchFlipDuration: TimeInterval = 0.4
    /// Frames of the currently displayed result cells, captured immediately before a reset
    /// fetch swaps them for skeleton placeholders. `applySearchResults` consumes this so the
    /// flip animation still has something to interpolate from once results land — by then the
    /// on-screen cells are skeletons, not the `AnimeCollectionViewCell`s it needs to measure.
    private var pendingFlipFrames: [Int: CGRect]?

    // MARK: - Views
    private var headerView: UIView!

    // Title row: [leftStack | rightButtons]
    private var titleRowStack: UIStackView!
    private var leftStack:     UIStackView!  // vertical: title label + search input
    private var titleLabel:    UILabel!
    private var searchInputRow: UIView!
    private var searchField:   Input!
    private var rightButtons:  UIStackView!  // horizontal: image + bolt
    private var cameraButton:  Button!
    private var boltButton:    Toggle!

    // Filter row: compact = horizontal/toggled; regular = wrapped/always visible.
    private var filterRowVisible = false
    private var filterCollectionView: UICollectionView!
    private var filterRowHeightConstraint: NSLayoutConstraint!
    private var titleRowSpacerHeightConstraint: NSLayoutConstraint!
    /// The width of each item of the header row at the current size.
    private var headerItemWidths: [CGFloat] = []

    deinit {
        debounceTimer?.invalidate()
        trackingRefreshTimer?.invalidate()
        searchTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // Active chips (wrapping frame layout, min-h-9)
    private var chipsContainer:     UIView!
    private var chipsHeightConstraint: NSLayoutConstraint!
    private var chipsLeadingConstraint: NSLayoutConstraint!
    private var chipsTrailingConstraint: NSLayoutConstraint!
    private var lastChipLayoutWidth: CGFloat = 0

    private var collectionView:    UICollectionView!
    private let messageView = SearchMessageView()

    // min-w-44 = 176pt; a panel is p-2 around a 28pt label, mb-1 and a 36pt control
    private static let filterItemMinWidth: CGFloat = 176
    private static let onListItemMinWidth: CGFloat = 144   // min-w-36
    private static let filterPanelHeight: CGFloat = 84
    private static let labelHeight: CGFloat = 28           // text-xl
    /// p-2 around the two 36pt buttons and their gap-4
    private static let actionsWidth: CGFloat = 104
    private static let defaultSort = "TRENDING_DESC"

    // Pending route state from Router.navigate(.search(...)) before the view is loaded.
    private var pendingRouteState: Route.SearchState?
    /// `$page.state.image` for a page that is not on screen yet.
    private var pendingTrace: TraceMoe.Source?

    // MARK: - Init

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Search",
            image: UIImage.hayaseIcon("search"),
            selectedImage: UIImage.hayaseIcon("search"))
    }

    // MARK: - Breakpoints

    /// `$breakpoints.md`
    private func isRegularSearchLayout(width: CGFloat? = nil) -> Bool {
        (width ?? view.bounds.width) >= 768
    }

    /// `px-2 sm:px-10` of the sticky header
    private func horizontalPadding(width: CGFloat? = nil) -> CGFloat {
        (width ?? view.bounds.width) >= 640 ? 40 : 8
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.bgBackground
        setupNavigationBar()
        setupHeaderView()
        setupCollectionView()
        setupOverlays()
        setupNotifications()
        rebuildActiveChipEntries()
        refreshFilterPickers()
        rebuildActiveChips()
        updateBoltTint()
        // goto('/app/search', { state: { search: variables } }) creates a fresh page with the
        // state pre-applied. Mirror this: if a route state is pending (it was set before this tab
        // was ever opened), skip the default fetch here — viewWillAppear applies it and fetches.
        if pendingRouteState == nil {
            fetchResults(reset: true)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hayase has no navigation bar on the search page
        navigationController?.setNavigationBarHidden(true, animated: animated)
        collectionView.indexPathsForSelectedItems?.forEach {
            collectionView.deselectItem(at: $0, animated: animated)
        }
        let preferences = Settings.DisplayPreferences()
        let previousPreferences = renderedDisplayPreferences
        renderedDisplayPreferences = preferences
        if let previous = previousPreferences, previous != preferences {
            collectionView.reloadData()
            if pendingRouteState == nil,
               previous.showAdultContent != preferences.showAdultContent ||
                previous.accountLanguage != preferences.accountLanguage {
                fetchResults(reset: true)
            }
        }
        if let state = pendingRouteState {
            pendingRouteState = nil
            applySearchRouteState(state)
        }
        if let source = pendingTrace {
            pendingTrace = nil
            traceReq(source)
        }
    }

    /// `$: if ($page.state.image) traceReq($page.state.image)`: a picture, or the address of one,
    /// that was dropped or pasted into the app.
    func trace(_ source: TraceMoe.Source) {
        if isViewLoaded, view.window != nil {
            traceReq(source)
        } else {
            pendingTrace = source
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Hover.shared.unhoverLastElement()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveHeaderLayout(animated: false)
        let chipWidth = chipsContainer?.bounds.width ?? 0
        if abs(chipWidth - lastChipLayoutWidth) > 1 {
            lastChipLayoutWidth = chipWidth
            rebuildActiveChips()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard isViewLoaded else { return }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self = self else { return }
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.updateResponsiveHeaderLayout(animated: false, targetWidth: size.width)
        })
    }

    // MARK: - Route state

    /// `variablesToSearch($page.state.search) ?? defaults`. A visit that remembers a search comes
    /// back to it; one that does not starts afresh, unless it is a click on this same page.
    func applyRouteState(_ state: Route.SearchState?) {
        guard isViewLoaded else {
            pendingRouteState = state   // nil: the page is still the fresh one
            return
        }
        applySearchRouteState(state)
    }

    private static let defaultState = Route.SearchState(sort: defaultSort)

    private func currentRouteState() -> Route.SearchState {
        Route.SearchState(title: currentTitle.isEmpty ? nil : currentTitle,
                          genres: selectedGenres,
                          tags: selectedTags,
                          year: selectedYear,
                          season: selectedSeason,
                          formats: selectedFormats,
                          statuses: selectedStatuses,
                          sort: selectedSort,
                          onList: selectedOnList,
                          ids: traceIds)
    }

    /// `replaceState(location.href, { search })`
    private func rememberRouteState() {
        let state = currentRouteState()
        Router.shared.remember(.search(state == Self.defaultState ? nil : state))
    }

    private func applySearchRouteState(_ state: Route.SearchState?) {
        guard let state else {
            if case .search? = Router.shared.previousRoute { return }
            guard currentRouteState() != Self.defaultState || !inputText.isEmpty else { return }
            resetSearch(sort: Self.defaultSort)
            return
        }
        guard state != currentRouteState() else { return }
        // `inputText` starts empty on a page, whatever name the remembered search has: the chip shows
        // it and the input does not
        currentTitle = state.title ?? ""
        inputText = ""
        searchField?.text = ""
        // `genres.filter(…)` then `tags.filter(…)`: the order of the lists, not of the variables
        let genres = SearchValues.genres.map(\.value).filter { state.genres.contains($0) }
        let tags = SearchValues.tags.map(\.value).filter { state.tags.contains($0) }
        selectedGenreTags = genres + tags
        selectedYear = state.year
        selectedSeason = state.season
        selectedFormats = SearchValues.formats.map(\.value).filter { state.formats.contains($0) }
        selectedStatuses = SearchValues.statuses.map(\.value).filter { state.statuses.contains($0) }
        selectedSort = state.sort.flatMap { value in SearchValues.sorts.contains { $0.value == value } ? value : nil }
        selectedOnList = state.onList
        traceIds = state.ids
        traceMatches = nil
        chipsFollowRestoredState = true
        commitSearchChange()
    }

    /// The page's initial `search` (Trending) or what `clear()` leaves (nothing, not even a sort).
    private func resetSearch(sort: String?) {
        resetState(sort: sort)
        commitSearchChange()
    }

    private func resetState(sort: String?) {
        selectedGenreTags = []
        selectedYear = nil
        selectedSeason = nil
        selectedFormats = []
        selectedStatuses = []
        selectedSort = sort
        selectedOnList = nil
        traceIds = nil
        traceMatches = nil
        currentTitle = ""
        inputText = ""
        searchField?.text = ""
        chipsFollowRestoredState = false
    }

    /// `$: searchChanged(search)`, for a change of anything but the name.
    private func commitSearchChange() {
        rebuildActiveChipEntries()
        refreshFilterPickers()
        rebuildActiveChips()
        updateBoltTint()
        fetchResults(reset: true)
    }

    // MARK: - Navigation bar

    private func setupNavigationBar() {
        title = nil
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance   = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance    = appearance
    }

    // MARK: - Header

    private func setupHeaderView() {
        headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = Self.bgBlack  // web: sticky header is bg-black
        view.addSubview(headerView)
        // Pin to view.topAnchor (not safeArea) so bg fills behind the status bar,
        // matching the collection view background color for a seamless appearance.
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        setupTitleRow()
        setupFilterRow()
        setupChipsRow()
    }

    // MARK: - Title Row
    // Compact: [Title label + input (flex-1 p-2)] | [image btn, bolt btn (w-auto p-2 gap-4 items-end)]
    private func setupTitleRow() {
        titleLabel = UILabel()
        titleLabel.text = "Title"
        titleLabel.font = .nunito(ofSize: 20, weight: .bold) // text-xl font-bold
        titleLabel.textColor = Self.foreground
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // `mb-1 ml-1`: the label sits 4pt in from the input and 28pt tall
        let labelRow = UIView()
        labelRow.translatesAutoresizingMaskIntoConstraints = false
        labelRow.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: labelRow.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: labelRow.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: labelRow.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: labelRow.trailingAnchor),
            labelRow.heightAnchor.constraint(equalToConstant: Self.labelHeight),
        ])

        searchInputRow = UIView()
        searchInputRow.translatesAutoresizingMaskIntoConstraints = false

        searchField = Input(placeholder: "Any", iconName: "search")
        configureSearchInput(searchField)
        searchField.addTarget(self, action: #selector(searchFieldChanged(_:)), for: .editingChanged)
        searchField.addTarget(self, action: #selector(searchFieldEnded), for: .editingDidEnd)
        searchInputRow.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: searchInputRow.topAnchor),
            searchField.leadingAnchor.constraint(equalTo: searchInputRow.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: searchInputRow.trailingAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchInputRow.bottomAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 36),
        ])

        // Left stack: "Title" (mb-1=4pt) + input
        leftStack = UIStackView(arrangedSubviews: [labelRow, searchInputRow])
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        leftStack.axis = .vertical; leftStack.spacing = 4; leftStack.alignment = .fill

        // Image button (FileImage) — interface Button variant=outline size=icon border-0.
        cameraButton = Button(iconName: "file-image", pointSize: 16)
        cameraButton.iconAnimation = .wobble   // animated-icon
        cameraButton.addTarget(self, action: #selector(cameraTapped), for: .touchUpInside)

        // Bolt toggle — md:hidden in interface (only on compact screens).
        boltButton = Toggle(iconName: "bolt", pointSize: 18)
        boltButton.iconAnimation = .boltSpin   // animated-icon
        boltButton.addTarget(self, action: #selector(boltTapped), for: .touchUpInside)

        // Right buttons: gap-4, items-end
        rightButtons = UIStackView(arrangedSubviews: [cameraButton, boltButton])
        rightButtons.translatesAutoresizingMaskIntoConstraints = false
        rightButtons.axis = .horizontal; rightButtons.spacing = 16; rightButtons.alignment = .bottom

        // Title row: leftStack (flex-1 p-2) | rightButtons (w-auto p-2): 16 between the two
        titleRowStack = UIStackView(arrangedSubviews: [leftStack, rightButtons])
        titleRowStack.translatesAutoresizingMaskIntoConstraints = false
        titleRowStack.axis = .horizontal; titleRowStack.spacing = 16; titleRowStack.alignment = .fill
        titleRowStack.isLayoutMarginsRelativeArrangement = true
        titleRowStack.layoutMargins = Self.compactTitleMargins(horizontal: horizontalPadding(width: UIScreen.main.bounds.width))
        headerView.addSubview(titleRowStack)
        // Anchor to safeAreaLayoutGuide so content starts below the status bar.
        // The layoutMargins.top provides the pt-5 and p-2 breathing room inside.
        NSLayoutConstraint.activate([
            titleRowStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            titleRowStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            titleRowStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
        ])
        titleRowSpacerHeightConstraint = titleRowStack.heightAnchor.constraint(equalToConstant: 20)
        titleRowSpacerHeightConstraint.isActive = false
    }

    /// pt-5 and p-2 above the row, p-2 below it, and the header's own `px-2 sm:px-10` plus p-2 aside
    private static func compactTitleMargins(horizontal: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(top: 28, left: horizontal + 8, bottom: 8, right: horizontal + 8)
    }

    /// `pl-9 … capitalize placeholder:opacity-50` with `svelte-radix` MagnifyingGlass `left-3`
    private func configureSearchInput(_ field: Input) {
        field.autocapitalizationType = .words   // capitalize
        field.usesRadixMagnifier = true
        field.searchIconSize = 16
        field.iconLeadingInset = 12
    }

    // MARK: - Filter Row
    // Hayase: flex overflow-y-auto w-full (horizontal scroll on mobile), use:dragScroll
    // Each item: min-w-44 flex-1 p-2 with text-xl font-bold label + combobox picker
    private func setupFilterRow() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        filterCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        filterCollectionView.translatesAutoresizingMaskIntoConstraints = false
        filterCollectionView.backgroundColor = .clear
        filterCollectionView.showsHorizontalScrollIndicator = false
        filterCollectionView.showsVerticalScrollIndicator = false
        filterCollectionView.alwaysBounceVertical = false
        filterCollectionView.dataSource = self
        filterCollectionView.delegate = self
        filterCollectionView.register(SearchFilterItemCell.self,
                                      forCellWithReuseIdentifier: SearchFilterItemCell.reuseID)
        filterCollectionView.register(SearchTitleItemCell.self,
                                      forCellWithReuseIdentifier: SearchTitleItemCell.reuseID)
        filterCollectionView.register(SearchActionItemCell.self,
                                      forCellWithReuseIdentifier: SearchActionItemCell.reuseID)
        headerView.addSubview(filterCollectionView)

        filterRowHeightConstraint = filterCollectionView.heightAnchor.constraint(equalToConstant: 0)
        filterRowHeightConstraint.isActive = true
        NSLayoutConstraint.activate([
            filterCollectionView.topAnchor.constraint(equalTo: titleRowStack.bottomAnchor),
            filterCollectionView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            filterCollectionView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
        ])
    }

    // MARK: - Chips Row
    // Hayase: flex flex-row flex-wrap mt-2 min-h-9 pb-1 px-1
    private func setupChipsRow() {
        chipsContainer = UIView()
        chipsContainer.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(chipsContainer)
        // min-h-9 (36) around the 4pt pb-1 leaves the chips 32
        chipsHeightConstraint = chipsContainer.heightAnchor.constraint(equalToConstant: 32)
        chipsHeightConstraint.isActive = true
        chipsLeadingConstraint = chipsContainer.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12)
        chipsTrailingConstraint = chipsContainer.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12)
        NSLayoutConstraint.activate([
            chipsContainer.topAnchor.constraint(equalTo: filterCollectionView.bottomAnchor, constant: 8),
            chipsLeadingConstraint,
            chipsTrailingConstraint,
            chipsContainer.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -4),
        ])
    }

    // MARK: - Actions

    @objc private func cameraTapped() {
        var config = PHPickerConfiguration()
        config.filter = .images; config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self; present(picker, animated: true)
    }

    @objc private func boltTapped() {
        filterRowVisible.toggle()
        updateResponsiveHeaderLayout(animated: true)
        updateBoltTint()
    }

    @objc private func searchFieldChanged(_ field: UITextField) {
        handleSearchTextChanged(field.text ?? "")
    }

    @objc private func searchFieldEnded() {
        updateName()   // on:blur={updateName}
    }

    /// `handleInput`: a trailing space settles the name at once, anything else after 500ms.
    private func handleSearchTextChanged(_ text: String) {
        inputText = text
        if text.hasSuffix(" ") {
            updateName()
        } else {
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.updateName()
            }
        }
        updateClearButton()
    }

    /// `search.name = inputText.trim()`. Assigning invalidates `search` whether the name changed or
    /// not, so leaving the field asks for the results again even when it is as it was.
    private func updateName() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        let name = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentTitle = name
        // the inputs stay as they are: reloading the row would take the focus from the one typed in
        rebuildActiveChipEntries()
        rebuildActiveChips()
        updateClearButton()
        fetchResults(reset: true)
    }

    /// `clear()`
    private func clearSearchState() {
        resetSearch(sort: nil)
    }

    private var hasAnySearchState: Bool {
        !currentTitle.isEmpty || !selectedGenreTags.isEmpty
            || selectedYear != nil || selectedSeason != nil
            || !selectedFormats.isEmpty || !selectedStatuses.isEmpty
            || selectedSort != nil || selectedOnList != nil || traceIds != nil
    }

    // MARK: - Responsive Filters

    private var shouldShowOnListFilter: Bool {
        TrackerAccountManager.shared.viewer(for: .anilist)?.id != nil
            && TrackerAccountManager.shared.token(for: .anilist) != nil
    }

    private var visibleFilterTypes: [SearchFilterType] {
        var types: [SearchFilterType] = [.genres, .year, .season, .format, .status, .sort]
        if shouldShowOnListFilter { types.append(.onList) }
        return types
    }

    private var visibleHeaderItems: [SearchHeaderItem] {
        let filters = visibleFilterTypes.map(SearchHeaderItem.filter)
        guard isRegularSearchLayout() else { return filters }
        return [.title] + filters + [.actions]
    }

    private func updateResponsiveHeaderLayout(animated: Bool, targetWidth: CGFloat? = nil) {
        guard isViewLoaded, filterCollectionView != nil else { return }
        let width = max(targetWidth ?? view.bounds.width, 320)
        let regular = isRegularSearchLayout(width: width)
        let hpad = horizontalPadding(width: width)
        let visible = regular || filterRowVisible

        leftStack.isHidden = regular
        rightButtons.isHidden = regular
        titleRowSpacerHeightConstraint.isActive = regular
        titleRowStack.layoutMargins = regular
            ? UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)   // pt-5
            : Self.compactTitleMargins(horizontal: hpad)
        chipsLeadingConstraint.constant = hpad + 4    // px-1
        chipsTrailingConstraint.constant = -(hpad + 4)

        if let layout = filterCollectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.scrollDirection = regular ? .vertical : .horizontal
            layout.minimumInteritemSpacing = 0
            layout.minimumLineSpacing = 0
            layout.sectionInset = UIEdgeInsets(top: 0, left: hpad, bottom: 0, right: hpad)
            layout.invalidateLayout()
        }

        let layoutResult = headerItemLayout(width: width, regular: regular, hpad: hpad)
        let signature = filterLayoutSignature(isRegular: regular, isVisible: visible, widths: layoutResult.widths)
        let shouldReloadFilters = signature != lastFilterLayoutSignature
        lastFilterLayoutSignature = signature
        headerItemWidths = layoutResult.widths

        filterCollectionView.isScrollEnabled = !regular
        filterRowHeightConstraint.constant = visible ? CGFloat(layoutResult.rows) * Self.filterPanelHeight : 0
        boltButton.isHidden = regular
        if shouldReloadFilters {
            filterCollectionView.reloadData()
        }

        let updates = {
            self.headerView.layoutIfNeeded()
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: updates)
        } else {
            updates()
        }
    }

    private func filterLayoutSignature(isRegular: Bool, isVisible: Bool, widths: [CGFloat]) -> String {
        let itemSignature = visibleHeaderItems.map { item -> String in
            switch item {
            case .title: return "title"
            case .actions: return "actions"
            case .filter(let type): return "filter-\(type.rawValue)"
            }
        }.joined(separator: ",")
        return "regular=\(isRegular);visible=\(isVisible);items=\(itemSignature);widths=\(widths)"
    }

    /// How wide each item of the header row is and over how many rows they go. Compact, the row
    /// scrolls and each item is as wide as its `min-w`. Regular, it is a wrapping flex row: the
    /// first four items are `md:w-1/4`, the rest `flex-1`, and the buttons `w-auto`.
    private func headerItemLayout(width: CGFloat, regular: Bool, hpad: CGFloat) -> (widths: [CGFloat], rows: Int) {
        let items = visibleHeaderItems
        func minimum(_ item: SearchHeaderItem) -> CGFloat {
            if case .filter(.onList) = item { return Self.onListItemMinWidth }
            if case .actions = item { return Self.actionsWidth }
            return Self.filterItemMinWidth
        }
        guard regular else {
            return (items.map(minimum), 1)
        }

        let usable = width - 2 * hpad
        // flex-basis, min-width and flex-grow of each item
        let specs: [(base: CGFloat, min: CGFloat, grow: CGFloat)] = items.enumerated().map { index, item in
            if case .actions = item { return (Self.actionsWidth, Self.actionsWidth, 0) }
            if index < 4 { return (usable / 4, minimum(item), 1) }
            return (0, minimum(item), 1)
        }

        // flex-wrap: an item goes on the next line when it no longer fits at its hypothetical size
        var lines: [[Int]] = [[]]
        var used: CGFloat = 0
        for (index, spec) in specs.enumerated() {
            let hypothetical = max(spec.base, spec.min)
            if used + hypothetical > usable, !lines[lines.count - 1].isEmpty {
                lines.append([])
                used = 0
            }
            lines[lines.count - 1].append(index)
            used += hypothetical
        }

        // resolving flexible lengths, growing: free space goes to the items by flex-grow, and an item
        // that would end up under its min-width stays at it while the others share what is left
        var widths = [CGFloat](repeating: 0, count: items.count)
        for line in lines {
            var frozen = Set(line.filter { specs[$0].grow == 0 })
            var sizes: [Int: CGFloat] = [:]
            for index in frozen { sizes[index] = max(specs[index].base, specs[index].min) }
            while frozen.count < line.count {
                let flexible = line.filter { !frozen.contains($0) }
                let taken = line.reduce(CGFloat(0)) { $0 + (frozen.contains($1) ? (sizes[$1] ?? specs[$1].min) : specs[$1].base) }
                let free = usable - taken
                let totalGrow = flexible.reduce(CGFloat(0)) { $0 + specs[$1].grow }
                var targets: [Int: CGFloat] = [:]
                for index in flexible {
                    targets[index] = specs[index].base + free * specs[index].grow / totalGrow
                }
                let violators = flexible.filter { (targets[$0] ?? 0) < specs[$0].min }
                if violators.isEmpty {
                    for index in flexible { sizes[index] = targets[index] }
                    break
                }
                for index in violators {
                    sizes[index] = specs[index].min
                    frozen.insert(index)
                }
            }
            for index in line { widths[index] = floor(sizes[index] ?? specs[index].min) }
        }
        return (widths, lines.count)
    }

    private func filterItemSize(for indexPath: IndexPath) -> CGSize {
        let width = headerItemWidths[safe: indexPath.item] ?? Self.filterItemMinWidth
        return CGSize(width: width, height: Self.filterPanelHeight)
    }

    private func showFilterPicker(for type: SearchFilterType, sourceView: UIView?) {
        let picker = SearchComboBoxViewController(filterType: type,
                                                  options: SearchValues.options(for: type),
                                                  selectedValues: selectedValues(for: type),
                                                  sourceView: sourceView)
        picker.onSelectionChanged = { [weak self] values in
            self?.applySelection(values, for: type)
        }
        present(picker, animated: true)
    }

    private func selectedValues(for type: SearchFilterType) -> Set<String> {
        switch type {
        case .genres: return Set(selectedGenreTags)
        case .year:
            guard let selectedYear else { return [] }
            return [selectedYear]
        case .season:
            guard let selectedSeason else { return [] }
            return [selectedSeason]
        case .format: return Set(selectedFormats)
        case .status: return Set(selectedStatuses)
        case .sort:
            guard let selectedSort else { return [] }
            return [selectedSort]
        case .onList:
            guard let selectedOnList else { return [] }
            return [selectedOnList ? "true" : "false"]
        case .trace: return traceIds == nil ? [] : ["trace"]
        case .title: return currentTitle.isEmpty ? [] : [currentTitle]
        }
    }

    /// What a combobox's `handleSelect` does: a single one takes the item, a multiple one adds it
    /// to the end of its values or takes it out of them.
    private func picked(_ values: Set<String>, from current: [String]) -> [String] {
        current.filter { values.contains($0) } + values.subtracting(current).sorted()
    }

    private func applySelection(_ values: Set<String>, for type: SearchFilterType) {
        switch type {
        case .genres:
            selectedGenreTags = picked(values, from: selectedGenreTags)
        case .year:
            selectedYear = values.first
        case .season:
            selectedSeason = values.first
        case .format:
            selectedFormats = picked(values, from: selectedFormats)
        case .status:
            selectedStatuses = picked(values, from: selectedStatuses)
        case .sort:
            selectedSort = values.first
        case .onList:
            selectedOnList = values.first.map { $0 == "true" }
        case .trace:
            if values.isEmpty { traceIds = nil }
        case .title:
            currentTitle = values.first ?? ""
        }
        commitSearchChange()
    }

    private func updateBoltTint() {
        boltButton.pressed = filterRowVisible
    }

    /// `selectedValue`: the labels of the values joined by ", ", or the placeholder.
    private func selectedTitle(for type: SearchFilterType) -> String {
        let values: [String]
        switch type {
        case .genres: values = selectedGenreTags
        case .format: values = selectedFormats
        case .status: values = selectedStatuses
        default: values = Array(selectedValues(for: type))
        }
        guard !values.isEmpty else { return type.placeholder }
        if type == .trace { return "IDs" }
        return values.map { SearchValues.label(for: $0, in: type) }.joined(separator: ", ")
    }

    private func isPlaceholderTitle(_ title: String, for type: SearchFilterType) -> Bool {
        title == type.placeholder
    }

    private func refreshFilterPickers() {
        lastFilterLayoutSignature = ""
        filterCollectionView?.reloadData()
        updateResponsiveHeaderLayout(animated: false)
    }

    /// The trash is blue while there is something to clear, `text-muted-foreground opacity-50` else.
    private func updateClearButton() {
        guard let items = filterCollectionView?.indexPathsForVisibleItems else { return }
        for indexPath in items {
            if let cell = filterCollectionView.cellForItem(at: indexPath) as? SearchActionItemCell {
                cell.configure(clearEnabled: hasAnySearchState)
            }
        }
    }

    /// `list(search)`: the label of every value there is, in the order of the object's keys.
    private func rebuildActiveChipEntries() {
        typealias Entry = (label: String, type: SearchFilterType, apiValue: String)
        func entry(_ label: String, _ type: SearchFilterType, _ value: String) -> Entry {
            (label, type, value)
        }
        let name: [Entry] = currentTitle.isEmpty ? [] : [entry(currentTitle, .title, currentTitle)]
        let genres: [Entry] = selectedGenreTags.map { entry(SearchValues.label(for: $0, in: .genres), .genres, $0) }
        var years: [Entry] = []
        if let selectedYear { years = [entry(selectedYear, .year, selectedYear)] }
        var seasons: [Entry] = []
        if let selectedSeason { seasons = [entry(SearchValues.label(for: selectedSeason, in: .season), .season, selectedSeason)] }
        let formats: [Entry] = selectedFormats.map { entry(SearchValues.label(for: $0, in: .format), .format, $0) }
        let statuses: [Entry] = selectedStatuses.map { entry(SearchValues.label(for: $0, in: .status), .status, $0) }
        var sorts: [Entry] = []
        if let selectedSort { sorts = [entry(SearchValues.label(for: selectedSort, in: .sort), .sort, selectedSort)] }
        let ids: [Entry] = traceIds == nil ? [] : [entry("IDs", .trace, "trace")]
        var onList: [Entry] = []
        if let selectedOnList {
            let raw = selectedOnList ? "true" : "false"
            onList = [entry(SearchValues.label(for: raw, in: .onList), .onList, raw)]
        }
        let groups: [[Entry]] = chipsFollowRestoredState
            ? [ids, name, onList, genres, years, seasons, formats, statuses, sorts]
            : [name, genres, years, seasons, formats, statuses, sorts, ids, onList]
        activeChipEntries = groups.flatMap { $0 }
    }

    // MARK: - Active chips (wrapping frame layout)
    // Hayase: flex flex-row flex-wrap mt-2 min-h-9 pb-1 px-1, chips: mx-1.5 my-1

    private func rebuildActiveChips() {
        chipsContainer.subviews.forEach { $0.removeFromSuperview() }
        guard !activeChipEntries.isEmpty else {
            UIView.animate(withDuration: 0.2) {
                self.chipsHeightConstraint.constant = 32
                self.headerView.layoutIfNeeded(); self.view.layoutIfNeeded()
            }
            return
        }

        let chips = activeChipEntries.map { makeActiveChip(label: $0.label, type: $0.type, apiValue: $0.apiValue) }
        let measuredWidth = chipsContainer.bounds.width > 0 ? chipsContainer.bounds.width : UIScreen.main.bounds.width - 24
        let availableW = max(measuredWidth - 6, 100)
        let hSpacing: CGFloat = 12
        let vSpacing: CGFloat = 8
        let rowStartX: CGFloat = 6
        var x = rowStartX
        var y: CGFloat = 4
        var rowH: CGFloat = 0

        for chip in chips {
            chip.setNeedsLayout(); chip.layoutIfNeeded()
            let sz = chip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let cw = ceil(sz.width); let ch = ceil(sz.height)
            if x + cw > availableW && x > rowStartX { y += rowH + vSpacing; x = rowStartX; rowH = 0 }
            chip.frame = CGRect(x: x, y: y, width: cw, height: ch)
            chip.translatesAutoresizingMaskIntoConstraints = true
            chipsContainer.addSubview(chip)
            x += cw + hSpacing; rowH = max(rowH, ch)
        }

        let newH = max(32, y + rowH + 4)
        UIView.animate(withDuration: 0.2) {
            self.chipsHeightConstraint.constant = newH
            self.headerView.layoutIfNeeded(); self.view.layoutIfNeeded()
        }
    }

    private func makeActiveChip(label: String, type: SearchFilterType, apiValue: String) -> UIView {
        let chip = Badge()
        chip.text = label.split(separator: " ", omittingEmptySubsequences: false)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")   // capitalize
        chip.accessibilityLabel = label
        chip.accessibilityIdentifier = "\(type.rawValue):\(apiValue)"
        chip.addTarget(self, action: #selector(removeChipTapped(_:)), for: .touchUpInside)
        return chip
    }

    /// `remove(label)`
    @objc private func removeChipTapped(_ sender: UIControl) {
        guard let id = sender.accessibilityIdentifier, let colon = id.range(of: ":") else { return }
        let typeRaw  = Int(id[id.startIndex..<colon.lowerBound]) ?? -1
        let apiValue = String(id[colon.upperBound...])
        guard let type = SearchFilterType(rawValue: typeRaw) else { return }
        switch type {
        case .title:
            // only `search.name` is emptied; the input keeps what was typed in it
            currentTitle = ""
            rebuildActiveChipEntries()
            rebuildActiveChips()
            updateClearButton()
            fetchResults(reset: true)
            return
        case .genres:  selectedGenreTags.removeAll { $0 == apiValue }
        case .year:    selectedYear = nil
        case .season:  selectedSeason = nil
        case .format:  selectedFormats.removeAll { $0 == apiValue }
        case .status:  selectedStatuses.removeAll { $0 == apiValue }
        case .sort:    selectedSort = nil
        case .onList:  selectedOnList = nil
        case .trace:   traceIds = nil   // `search.ids = undefined`; `trace` is left as it is
        }
        commitSearchChange()
    }

    // MARK: - Collection view

    private func setupCollectionView() {
        collectionView = AnimeCardCollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = Self.bgBackground
        collectionView.delegate = self; collectionView.dataSource = self
        collectionView.register(AnimeCollectionViewCell.self,
                                forCellWithReuseIdentifier: AnimeCollectionViewCell.reuseID)
        collectionView.register(SkeletonCardCell.self,
                                forCellWithReuseIdentifier: SkeletonCardCell.reuseID)
        collectionView.register(SkeletonTraceCardCell.self,
                                forCellWithReuseIdentifier: SkeletonTraceCardCell.reuseID)
        collectionView.keyboardDismissMode = .onDrag
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.itemSize = CGSize(width: AnimeCollectionViewCell.outerWidth,
                                 height: AnimeCollectionViewCell.outerHeight)
        return layout
    }

    /// Trace results are the wide `episode.svelte` cards, and a `trace` that stays after its IDs
    /// chip is removed keeps the page drawing them.
    private var showsEpisodeCards: Bool { traceMatches != nil }

    private var cardWidth: CGFloat {
        showsEpisodeCards ? AnimeCollectionViewCell.traceOuterWidth : AnimeCollectionViewCell.outerWidth
    }

    /// `grid-cols-[repeat(auto-fill,minmax(184px,max-content))]`; the trace grid has its columns
    /// from `md` only, and below it everything sits in one.
    private func gridColumns(for width: CGFloat) -> Int {
        if showsEpisodeCards && !isRegularSearchLayout(width: width) { return 1 }
        let available = max(width - gridHorizontalPadding(for: width) * 2, cardWidth)
        return max(1, Int(floor(available / cardWidth)))
    }

    private func gridHorizontalPadding(for width: CGFloat) -> CGFloat {
        isRegularSearchLayout(width: width) ? 28 : 0   // md:px-7
    }

    /// `justify-center`: the columns sit in the middle, never closer to the sides than `px-7`.
    private func resultSectionInsets(for width: CGFloat) -> UIEdgeInsets {
        let padding = gridHorizontalPadding(for: width)
        let used = CGFloat(gridColumns(for: width)) * cardWidth
        let inset = max(padding, floor((width - used) / 2))
        return UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
    }

    // MARK: - Episode cards

    private func traceMatch(for item: AnimeItem) -> TraceAnime? {
        traceMatches?.first { $0.anilist == item.id }
    }

    /// The height of an `episode.svelte` card: `p-4` around a 9rem picture, `pt-3` and the title
    /// (at most two lines, beside the episode and the match), `pt-2` and the year and format line.
    private func episodeCardHeight(for item: AnimeItem) -> CGFloat {
        let font = UIFont.nunito(ofSize: 13, weight: .black)
        var titleWidth = AnimeCollectionViewCell.traceOuterWidth - 2 * AnimeCollectionViewCell.contentPadding
        if (item.mediaListEntry ?? TrackerAggregator.externalEntry(for: item.id)) != nil { titleWidth -= 12.8 }
        var infoHeight: CGFloat = 0
        if let trace = traceMatch(for: item) {
            let small = UIFont.nunito(ofSize: 12, weight: .medium)
            let info = max(("Episode \(trace.episode)" as NSString).size(withAttributes: [.font: small]).width,
                           ("100%" as NSString).size(withAttributes: [.font: small]).width)
            titleWidth -= ceil(info) + 8   // gap-2
            infoHeight = 35                // pt-[1px], two 16pt lines and mt-0.5
        }
        let text = AniListUtil.title(for: item) as NSString
        let lines = min(2, max(1, Int(ceil(text.size(withAttributes: [.font: font]).width / max(titleWidth, 1)))))
        let titleHeight = max(CGFloat(lines) * 19.2, infoHeight)
        return AnimeCollectionViewCell.contentPadding * 2 + AnimeCollectionViewCell.traceCoverHeight
            + 12 + titleHeight + 8 + 16
    }

    /// Every card of a grid row is as tall as the tallest of the row, with the year and format at
    /// the bottom.
    private func episodeCardSize(at index: Int, width: CGFloat) -> CGSize {
        let columns = gridColumns(for: width)
        let start = index / columns * columns
        let end = min(start + columns, animeResults.count)
        let heights: [CGFloat] = (start..<max(start + 1, end)).map { row in
            guard let item = self.animeResults[safe: row] else { return 216 }
            return self.episodeCardHeight(for: item)
        }
        let height = heights.max() ?? 216
        return CGSize(width: AnimeCollectionViewCell.traceOuterWidth, height: height)
    }

    /// `<SmallCard first={i === 0}>`; episode cards have no such flag.
    private func startsAPage(_ index: Int) -> Bool {
        !showsEpisodeCards && pageStartIndexes.contains(index)
    }

    // MARK: - Overlays

    private func setupOverlays() {
        messageView.translatesAutoresizingMaskIntoConstraints = false
        messageView.isHidden = true
        view.addSubview(messageView)
        NSLayoutConstraint.activate([
            messageView.topAnchor.constraint(equalTo: collectionView.topAnchor),
            messageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageView.heightAnchor.constraint(equalToConstant: 320),   // h-80
        ])
    }

    // MARK: - Fetch

    private func fetchResults(reset: Bool) {
        if reset {
            currentPage = 1; hasNextPage = true
            // Start a fresh search generation and cancel stale network work.
            fetchRequestID += 1
            searchTask?.cancel()
            searchTask = nil
            isFetching = false
            pageStartIndexes = [0]
            rememberRouteState()
        }
        guard !isFetching, hasNextPage else { return }
        isFetching = true
        if reset {
            // Snapshot current cell positions before we swap to skeletons below; once
            // isShowingSkeleton flips, visibleSearchItemFrames() can no longer see them.
            let frames = showsEpisodeCards == renderedEpisodeCards ? visibleSearchItemFrames() : [:]
            pendingFlipFrames = frames.isEmpty ? nil : frames
            // Skeleton placeholders while the query is fetching
            isShowingSkeleton = true
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.reloadData()
            messageView.isHidden = true
        }
        let myRequestID = fetchRequestID

        let previousResults = animeResults
        let requestedPage = currentPage
        searchTask = AniListClient.shared.searchAnimeItemsPage(
            title: currentTitle.isEmpty ? nil : currentTitle,
            genres: selectedGenres,
            tags: selectedTags,
            formats: selectedFormats,
            statuses: selectedStatuses,
            // Hayase: filter.sort?.[0]?.value ?? 'SEARCH_MATCH' — SEARCH_MATCH = search relevance
            sort: selectedSort ?? "SEARCH_MATCH",
            seasonYear: selectedYear.flatMap { Int($0) },
            season: selectedSeason,
            onList: selectedOnList,
            ids: traceIds,
            page: currentPage,
            policy: .cacheAndNetwork,
            query: searchQuery
        ) { [weak self] result in
            guard let self = self, self.fetchRequestID == myRequestID else { return }
            switch result {
            case .success(let page):
                self.isFetching = false
                if !page.isCacheResult { self.searchTask = nil }
                self.isShowingSkeleton = false
                let updatedResults: [AnimeItem]
                if reset {
                    if page.isCacheResult || self.currentPage <= requestedPage + 1 {
                        updatedResults = page.items
                    } else {
                        let tailStart = min(page.items.count, self.animeResults.count)
                        updatedResults = page.items + Array(self.animeResults.dropFirst(tailStart))
                    }
                } else if page.isCacheResult {
                    self.pageStartIndexes.insert(self.animeResults.count)
                    updatedResults = self.animeResults + page.items
                } else if self.animeResults.count > previousResults.count {
                    let prefix = Array(self.animeResults.prefix(previousResults.count))
                    let tailStart = min(previousResults.count + page.items.count, self.animeResults.count)
                    let tail = Array(self.animeResults.dropFirst(tailStart))
                    updatedResults = prefix + page.items + tail
                } else {
                    self.pageStartIndexes.insert(self.animeResults.count)
                    updatedResults = self.animeResults + page.items
                }
                self.hasNextPage = page.hasNextPage
                self.currentPage = max(self.currentPage, requestedPage + 1)
                if updatedResults.isEmpty {
                    self.messageView.show(["Looks like there's nothing here."])
                } else {
                    self.messageView.isHidden = true
                }
                self.applySearchResults(self.orderedForTrace(updatedResults))
            case .failure(let error):
                self.isFetching = false
                self.searchTask = nil
                self.isShowingSkeleton = false
                if reset { self.applySearchResults([], animated: false) }
                self.hasNextPage = false
                if self.animeResults.isEmpty {
                    self.messageView.show(["Looks like something went wrong!", error.description])
                }
            }
        }
    }

    /// trace.svelte: the cards go in the order the lookup gave their anime.
    private func orderedForTrace(_ items: [AnimeItem]) -> [AnimeItem] {
        guard let matches = traceMatches else { return items }
        let order = matches.map(\.anilist)
        return items.enumerated().sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.element.id) ?? -1
            let right = order.firstIndex(of: rhs.element.id) ?? -1
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map { $0.element }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleTrackingDidChange(_:)),
                                               name: LocalTracking.didChange,
                                               object: nil)
        // `{#if $viewer?.viewer?.id}`: My List comes and goes with the account
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(accountsChanged),
                                               name: TrackerAccountManager.didChange,
                                               object: nil)
    }

    @objc private func accountsChanged() {
        DispatchQueue.main.async { [weak self] in self?.refreshFilterPickers() }
    }

    @objc private func handleTrackingDidChange(_ notification: Notification) {
        guard selectedOnList != nil else { return }
        trackingRefreshTimer?.invalidate()
        trackingRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.fetchResults(reset: true)
        }
    }

    private func applySearchResults(_ results: [AnimeItem], animated: Bool = true) {
        // A reset fetch snapshots frames before switching to skeletons (see fetchResults);
        // consume that snapshot here since the live collection view is showing skeletons by
        // now. Once consumed it's cleared, so a later call within the same fetch (e.g. the
        // network leg after a cache-hit already redrew real cells) reads live frames instead.
        let previousFrames: [Int: CGRect]
        if let pendingFlipFrames {
            previousFrames = animated ? pendingFlipFrames : [:]
            self.pendingFlipFrames = nil
        } else {
            previousFrames = animated ? visibleSearchItemFrames() : [:]
        }
        let shouldFlip = !previousFrames.isEmpty &&
            !animeResults.isEmpty &&
            !results.isEmpty &&
            animeResults.map(\.id) != results.map(\.id)

        animeResults = results
        renderedEpisodeCards = showsEpisodeCards
        guard isViewLoaded, collectionView != nil else { return }
        collectionView.collectionViewLayout.invalidateLayout()

        if shouldFlip {
            UIView.performWithoutAnimation {
                collectionView.reloadData()
                collectionView.layoutIfNeeded()
            }
            animateSearchFlip(from: previousFrames)
        } else {
            collectionView.reloadData()
        }
    }

    private func visibleSearchItemFrames() -> [Int: CGRect] {
        guard collectionView != nil, !isShowingSkeleton else { return [:] }
        var frames: [Int: CGRect] = [:]
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard indexPath.item < animeResults.count,
                  collectionView.cellForItem(at: indexPath) is AnimeCollectionViewCell else { continue }
            let mediaID = animeResults[indexPath.item].id
            let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame
                ?? collectionView.cellForItem(at: indexPath)?.frame
            if let frame {
                frames[mediaID] = frame
            }
        }
        return frames
    }

    private func animateSearchFlip(from previousFrames: [Int: CGRect]) {
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.77, y: 0.0),
                                             controlPoint2: CGPoint(x: 0.175, y: 1.0))
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard indexPath.item < animeResults.count,
                  let cell = collectionView.cellForItem(at: indexPath),
                  let oldFrame = previousFrames[animeResults[indexPath.item].id] else { continue }
            let newFrame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? cell.frame
            cell.transform = CGAffineTransform(translationX: oldFrame.midX - newFrame.midX,
                                               y: oldFrame.midY - newFrame.midY)
            let animator = UIViewPropertyAnimator(duration: searchFlipDuration, timingParameters: timing)
            animator.addAnimations {
                cell.transform = .identity
            }
            animator.startAnimation()
        }
    }

    // MARK: - trace.moe image search
    //
    // Hayase: traceAnime(file) from $lib/utils posts the image to api.trace.moe/search, behind a
    // toast.promise. On success: clear() all filters, set search.ids = unique anilist IDs, show results.

    /// `traceReq`
    private func traceReq(_ source: TraceMoe.Source) {
        let toast = AppErrorToast.startPromise(title: "Looking up anime for image...",
                                               description: "You can also paste an URL to an image.")
        TraceMoe.lookup(source) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let matches):
                    AppErrorToast.resolvePromise(toast, title: "Found anime for image!")
                    self?.applyTraceResults(matches)
                case .failure:
                    AppErrorToast.resolvePromise(
                        toast,
                        title: "Couldn't find anime for specified image! Try to remove black bars, or use a more detailed image.",
                        failed: true)
                }
            }
        }
    }

    /// `clear()` and `search.ids = [...new Set(res.map(r => r.anilist))]`, which the page answers once.
    private func applyTraceResults(_ matches: [TraceAnime]) {
        resetState(sort: nil)
        var seen = Set<Int>()
        traceIds = matches.map(\.anilist).filter { seen.insert($0).inserted }
        traceMatches = matches
        commitSearchChange()
    }
}

// MARK: - UICollectionViewDataSource

extension SearchViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        if collectionView === filterCollectionView {
            return visibleHeaderItems.count
        }
        // query.svelte shows 20 SkeletonCards while it fetches, trace.svelte 50 SkeletonTraceCards
        if isShowingSkeleton { return showsEpisodeCards ? 50 : 20 }
        return animeResults.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView === filterCollectionView {
            guard let item = visibleHeaderItems[safe: indexPath.item] else {
                return collectionView.dequeueReusableCell(withReuseIdentifier: SearchTitleItemCell.reuseID, for: indexPath)
            }
            switch item {
            case .title:
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SearchTitleItemCell.reuseID,
                    for: indexPath) as? SearchTitleItemCell else {
                    return collectionView.dequeueReusableCell(withReuseIdentifier: SearchTitleItemCell.reuseID, for: indexPath)
                }
                cell.configure(text: inputText)
                cell.onTextChanged = { [weak self] text in
                    self?.handleSearchTextChanged(text)
                }
                cell.onEndEditing = { [weak self] in
                    self?.updateName()
                }
                return cell
            case .filter(let type):
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SearchFilterItemCell.reuseID,
                    for: indexPath) as? SearchFilterItemCell else {
                    return collectionView.dequeueReusableCell(withReuseIdentifier: SearchTitleItemCell.reuseID, for: indexPath)
                }
                let title = selectedTitle(for: type)
                cell.configure(type: type,
                               title: title,
                               placeholder: isPlaceholderTitle(title, for: type))
                return cell
            case .actions:
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SearchActionItemCell.reuseID,
                    for: indexPath) as? SearchActionItemCell else {
                    return collectionView.dequeueReusableCell(withReuseIdentifier: SearchTitleItemCell.reuseID, for: indexPath)
                }
                cell.configure(clearEnabled: hasAnySearchState)
                cell.onImageTapped = { [weak self] in self?.cameraTapped() }
                cell.onClearTapped = { [weak self] in self?.clearSearchState() }
                return cell
            }
        }
        if isShowingSkeleton {
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: showsEpisodeCards ? SkeletonTraceCardCell.reuseID : SkeletonCardCell.reuseID,
                for: indexPath)
        }
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: AnimeCollectionViewCell.reuseID,
            for: indexPath) as? AnimeCollectionViewCell else {
            return collectionView.dequeueReusableCell(withReuseIdentifier: SkeletonCardCell.reuseID, for: indexPath)
        }
        guard let item = animeResults[safe: indexPath.item] else { return cell }
        let trace = traceMatch(for: item)
        cell.configure(with: item, trace: trace, episodeStyle: showsEpisodeCards)
        Hover.shared.bind(to: cell,
                          host: self,
                          mediaProvider: { item },
                          actions: hayasePreviewCardActions(),
                          trace: trace,
                          alignsToCardStart: startsAPage(indexPath.item))
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension SearchViewController: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        if collectionView === filterCollectionView {
            guard case .filter(let type)? = visibleHeaderItems[safe: indexPath.item] else { return }
            showFilterPicker(for: type, sourceView: collectionView.cellForItem(at: indexPath))
            return
        }
        guard !isShowingSkeleton,
              let item = animeResults[safe: indexPath.item] else { return }
        if let cell = collectionView.cellForItem(at: indexPath) as? AnimeCollectionViewCell,
           Hover.shared.handleTouchSelection(source: cell,
                                             host: self,
                                             media: item,
                                             actions: hayasePreviewCardActions(),
                                             trace: traceMatch(for: item),
                                             alignsToCardStart: startsAPage(indexPath.item)) {
            return
        }
        Router.shared.navigateToAnime(item, hostTabIndex: hayaseTabIndex)
    }

    // Infinite scroll — matches use:infiniteScroll in Hayase
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        Hover.shared.scrollDidOccur()
        let offsetY = scrollView.contentOffset.y
        let total = scrollView.contentSize.height; let frame = scrollView.frame.height
        guard total > frame, offsetY > total - frame - 800 else { return }
        fetchResults(reset: false)
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView === filterCollectionView {
            return filterItemSize(for: indexPath)
        }
        guard showsEpisodeCards else {
            return CGSize(width: AnimeCollectionViewCell.outerWidth,
                          height: AnimeCollectionViewCell.outerHeight)
        }
        if isShowingSkeleton {
            // skeletontrace.svelte: p-4 around a 9rem picture and two bars
            return CGSize(width: AnimeCollectionViewCell.traceOuterWidth, height: 216)
        }
        return episodeCardSize(at: indexPath.item, width: collectionView.bounds.width)
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        guard collectionView !== filterCollectionView else {
            return (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.sectionInset ?? .zero
        }
        return resultSectionInsets(for: collectionView.bounds.width)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension SearchViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.hasItemConformingToTypeIdentifier("public.image") else { return }
        provider.loadDataRepresentation(forTypeIdentifier: "public.image") { [weak self] data, _ in
            guard let data = data else { return }
            // Photos are often HEIC, which trace.moe does not read: send a JPEG
            let jpegData = UIImage(data: data)?.jpegData(compressionQuality: 0.8) ?? data
            DispatchQueue.main.async { self?.traceReq(.image(jpegData, mimeType: "image/jpeg")) }
        }
    }
}

// MARK: - SearchMessageView

/// The `Ooops!` block of query.svelte: a centred `h-80` area at the top of the results.
private final class SearchMessageView: UIView {
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),   // p-5
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// `lines` are the muted `text-lg` lines under the heading.
    func show(_ lines: [String]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let heading = UILabel()
        heading.text = "Ooops!"
        heading.font = .nunito(ofSize: 36, weight: .bold)   // text-4xl font-bold
        heading.textColor = UIColor.HayaseTheme.foreground
        heading.textAlignment = .center
        stack.addArrangedSubview(heading)
        stack.setCustomSpacing(4, after: heading)   // mb-1
        for line in lines {
            let label = UILabel()
            label.text = line
            label.font = .nunito(ofSize: 18, weight: .regular)   // text-lg
            label.textColor = UIColor.HayaseTheme.mutedForeground
            label.textAlignment = .center
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }
        isHidden = false
    }
}

// MARK: - SearchTitleItemCell

private final class SearchTitleItemCell: UICollectionViewCell, UITextFieldDelegate {
    static let reuseID = "SearchTitleItemCell"

    var onTextChanged: ((String) -> Void)?
    var onEndEditing: (() -> Void)?

    private let titleLabel = UILabel()
    private let searchField: Input = {
        let field = Input(placeholder: "Any", iconName: "search")
        field.autocapitalizationType = .words   // capitalize
        field.usesRadixMagnifier = true
        field.searchIconSize = 16
        field.iconLeadingInset = 12
        return field
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
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        titleLabel.text = "Title"
        titleLabel.font = .nunito(ofSize: 20, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        searchField.delegate = self
        searchField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)

        contentView.addSubview(titleLabel)
        contentView.addSubview(searchField)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.heightAnchor.constraint(equalToConstant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8),

            searchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            searchField.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    func configure(text: String) {
        if searchField.text != text { searchField.text = text }
    }

    @objc private func textDidChange() {
        onTextChanged?(searchField.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        onEndEditing?()
    }
}

// MARK: - SearchActionItemCell

private final class SearchActionItemCell: UICollectionViewCell {
    static let reuseID = "SearchActionItemCell"

    var onImageTapped: (() -> Void)?
    var onClearTapped: (() -> Void)?

    private let imageButton: Button = {
        let button = Button(iconName: "file-image", pointSize: 16)
        button.iconAnimation = .wobble   // animated-icon
        return button
    }()
    private let clearButton: Button = {
        let button = Button(iconName: "trash", pointSize: 16)
        button.setImage(nil, for: .normal)
        button.setLayeredIcon(.trash)   // the lid and the bin move apart on hover
        return button
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
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        [imageButton, clearButton].forEach { button in
            contentView.addSubview(button)
        }

        imageButton.addTarget(self, action: #selector(imageTapped), for: .touchUpInside)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            imageButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            clearButton.leadingAnchor.constraint(equalTo: imageButton.trailingAnchor, constant: 16),
            clearButton.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8),
            // items-end inside p-2
            imageButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            clearButton.bottomAnchor.constraint(equalTo: imageButton.bottomAnchor),
        ])
    }

    func configure(clearEnabled: Bool) {
        // text-blue-400, or text-muted-foreground opacity-50 with nothing to clear
        clearButton.contentTint = clearEnabled
            ? UIColor(red: 0.376, green: 0.647, blue: 0.980, alpha: 1)
            : UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5)
    }

    @objc private func imageTapped() {
        onImageTapped?()
    }

    @objc private func clearTapped() {
        onClearTapped?()
    }
}

// MARK: - SearchFilterItemCell

private final class SearchFilterItemCell: UICollectionViewCell {
    static let reuseID = "SearchFilterItemCell"

    private let titleLabel = UILabel()
    private let comboBox = ComboBox()

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
        contentView.backgroundColor = .clear

        titleLabel.font = .nunito(ofSize: 20, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        comboBox.isUserInteractionEnabled = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(comboBox)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.heightAnchor.constraint(equalToConstant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8),

            comboBox.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            comboBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            comboBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
        ])
    }

    func configure(type: SearchFilterType, title: String, placeholder: Bool) {
        titleLabel.text = type.label
        comboBox.configure(text: title, placeholder: placeholder)
    }
}
