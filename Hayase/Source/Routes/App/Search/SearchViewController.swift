//
//  SearchViewController.swift
//  NyaiS
//
//  Hayase-style AniList anime search tab.
//  Ported from src/routes/app/search/+page.svelte + values.ts
//  Source: https://github.com/scigward/interface
//
//  Mobile layout:
//  Title label + input + [camera] [bolt]  - always visible
//  Labeled filter panels (horizontal scroll) - when bolt tapped
//  Wrapping active chips row
//  2-column grid (minmax(184px))

import UIKit
import PhotosUI

// MARK: - trace.moe response (private to this file)

private struct TraceMoeResponse: Decodable {
    let result: [TraceMoeHit]
    let error: String?
}

private struct TraceMoeHit: Decodable {
    /// AniList anime ID returned by trace.moe
    let anilist: Int
}

private enum SearchHeaderItem {
    case title
    case filter(SearchFilterType)
    case actions
}

// MARK: - SearchViewController

class SearchViewController: UIViewController {

    // MARK: - Hayase color constants
    private static let bgBlack      = UIColor.black
    private static let bgBackground = UIColor.HayaseTheme.background
    private static let mutedFg      = UIColor.HayaseTheme.mutedForeground
    private static let activeBlue   = UIColor(red: 0.369, green: 0.647, blue: 0.953, alpha: 1)

    // MARK: - Filter state
    // Hayase: genres/tags, formats and status multi-select; year/season/sort/onList single-select.
    private var selectedGenres:   [String] = []
    private var selectedTags:     [String] = []
    private var selectedYear:     String?  = nil
    private var selectedSeason:   String?  = nil
    private var selectedFormats:  [String] = []
    private var selectedStatuses: [String] = []
    private var selectedSort:     String?  = "TRENDING_DESC"
    private var selectedOnList:   Bool?    = nil

    // Active chip entries mirror interface list(search), including sort and trace IDs.
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
    private var currentTitle = ""
    private var debounceTimer: Timer?
    private var trackingRefreshTimer: Timer?
    /// Set when a trace.moe image search is active; causes grid to show trace results.
    private var traceIds: [Int]?
    /// True while the trace.moe network request is in-flight.
    private var isTracing = false
    private var lastFilterLayoutSignature = ""
    private let searchFlipDuration: TimeInterval = 0.4

    // MARK: - Views
    private var headerView: UIView!

    // Title row: [leftStack | rightButtons]
    private var titleRowStack: UIStackView!
    private var leftStack:     UIStackView!  // vertical: title label + search input
    private var titleLabel:    UILabel!
    private var searchInputRow: UIView!
    private var searchField:   Input!
    private var rightButtons:  UIStackView!  // horizontal: camera + bolt
    private var cameraButton:  UIButton!
    private var boltButton:    Toggle!

    // Filter row: compact = horizontal/toggled; regular = wrapped/always visible.
    private var filterRowVisible = false
    private var filterCollectionView: UICollectionView!
    private var filterRowHeightConstraint: NSLayoutConstraint!
    private var titleRowSpacerHeightConstraint: NSLayoutConstraint!

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
    private var loadingIndicator:  UIActivityIndicatorView!
    private var emptyLabel:        UILabel!

    // min-w-44 = 176pt; panel height = label(20)+gap(4)+picker(36)+padding(24) = 84pt
    private static let filterItemMinWidth: CGFloat = 176
    private static let filterPanelHeight: CGFloat = 80
    private static let regularHorizontalInset: CGFloat = 40
    private static let regularActionWidth: CGFloat = 104

    // Pending route state from Router.navigate(.search(...)) before the view is loaded.
    private var pendingRouteState: Route.SearchState?

    // Pending prefill from older call sites. Kept as a compatibility shim.
    private var pendingPrefill: (genre: String?, sort: String?)?

    // MARK: - Init

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Search",
            image: UIImage.hayaseIcon("search"),
            selectedImage: UIImage.hayaseIcon("search"))
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
        // Hayase: goto('/app/search', { state: { search: variables } }) creates a fresh page with the
        // state pre-applied. Mirror this: if a prefill is pending (View More tapped before this tab was
        // ever opened), skip the default fetch here — viewWillAppear will call applyPrefill which runs
        // the correct fetch with the prefilled filters.
        if pendingPrefill == nil && pendingRouteState == nil {
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
        if let state = pendingRouteState {
            pendingRouteState = nil
            applySearchRouteState(state)
        } else if let pending = pendingPrefill {
            pendingPrefill = nil
            let ext = pendingExtended
            pendingExtended = nil
            applyPrefillExtended(genre: pending.genre,
                                 format: ext?.format,
                                 status: ext?.status,
                                 season: ext?.season,
                                 seasonYear: ext?.seasonYear,
                                 sort: pending.sort)
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
            self.collectionView.setCollectionViewLayout(self.makeLayout(), animated: false)
            self.updateResponsiveHeaderLayout(animated: false, targetWidth: size.width)
        })
    }

    // MARK: - Prefill from Home

    func applyRouteState(_ state: Route.SearchState?) {
        guard let state else { return }
        if isViewLoaded {
            applySearchRouteState(state)
        } else {
            pendingRouteState = state
        }
    }

    private func applySearchRouteState(_ state: Route.SearchState) {
        currentTitle = state.title ?? ""
        searchField?.text = currentTitle
        selectedGenres = state.genres
        selectedTags = state.tags
        selectedYear = state.year
        selectedSeason = state.season
        selectedFormats = state.formats
        selectedStatuses = state.statuses
        selectedSort = state.sort
        selectedOnList = state.onList
        traceIds = state.ids
        rebuildActiveChipEntries()
        refreshFilterPickers()
        rebuildActiveChips()
        updateBoltTint()
        fetchResults(reset: true)
    }

    func prefillSearch(genre: String?, sort: String?) {
        if isViewLoaded { applyPrefill(genre: genre, sort: sort) }
        else { pendingPrefill = (genre: genre, sort: sort) }
    }

    /// Extended prefill matching web `goto('/app/search', { state: { search: { ... } } })`.
    /// Accepts optional genre, format, status, season + year, sort filters.
    func prefillSearchExtended(genre: String? = nil,
                               format: String? = nil,
                               status: String? = nil,
                               season: String? = nil,
                               seasonYear: Int? = nil,
                               sort: String? = nil) {
        if isViewLoaded {
            applyPrefillExtended(genre: genre, format: format, status: status,
                                 season: season, seasonYear: seasonYear, sort: sort)
        } else {
            // Store for later
            pendingPrefill = (genre: genre, sort: sort)
            pendingExtended = (format: format, status: status,
                               season: season, seasonYear: seasonYear)
        }
    }

    private var pendingExtended: (format: String?, status: String?,
                                  season: String?, seasonYear: Int?)?

    private func applyPrefill(genre: String?, sort: String?) {
        applyPrefillExtended(genre: genre, sort: sort)
    }

    private func applyPrefillExtended(genre: String? = nil,
                                      format: String? = nil,
                                      status: String? = nil,
                                      season: String? = nil,
                                      seasonYear: Int? = nil,
                                      sort: String? = nil) {
        selectedGenres = []
        selectedTags = []
        selectedYear = nil
        selectedSeason = nil
        selectedFormats = []
        selectedStatuses = []
        selectedSort = nil
        selectedOnList = nil
        traceIds = nil
        if let genre = genre {
            if SearchValues.genreSet.contains(genre) {
                selectedGenres = [genre]
            } else {
                selectedTags = [genre]
            }
        }
        if let format = format {
            selectedFormats = [format]
        }
        if let status = status {
            selectedStatuses = [status]
        }
        if let season = season {
            selectedSeason = season
        }
        if let seasonYear = seasonYear {
            let yearStr = String(seasonYear)
            selectedYear = yearStr
        }
        if let sort = sort { selectedSort = sort }
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
    // Hayase mobile: [Title label + input (flex-1)] | [camera btn, bolt btn (items-end)]
    private func setupTitleRow() {
        titleLabel = UILabel()
        titleLabel.text = "Title"
        titleLabel.font = .nunito(ofSize: 20, weight: .bold) // text-xl font-bold
        titleLabel.textColor = .white

        searchInputRow = UIView()
        searchInputRow.translatesAutoresizingMaskIntoConstraints = false

        searchField = Input(placeholder: "Any", iconName: "search")
        searchField.addTarget(self, action: #selector(searchFieldChanged(_:)), for: .editingChanged)
        searchInputRow.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: searchInputRow.topAnchor),
            searchField.leadingAnchor.constraint(equalTo: searchInputRow.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: searchInputRow.trailingAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchInputRow.bottomAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 36),
        ])

        // Left stack: "Title" (mb-1=4pt) + input
        leftStack = UIStackView(arrangedSubviews: [titleLabel, searchInputRow])
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        leftStack.axis = .vertical; leftStack.spacing = 4; leftStack.alignment = .fill

        // Camera button (FileImage) — interface Button variant=outline size=icon border-0.
        cameraButton = Button(iconName: "file-image", pointSize: 16)
        cameraButton.addTarget(self, action: #selector(cameraTapped), for: .touchUpInside)

        // Bolt toggle — md:hidden in interface (only on compact screens).
        boltButton = Toggle(iconName: "bolt", pointSize: 18)
        boltButton.addTarget(self, action: #selector(boltTapped), for: .touchUpInside)

        // Right buttons: gap-4, items-end
        rightButtons = UIStackView(arrangedSubviews: [cameraButton, boltButton])
        rightButtons.translatesAutoresizingMaskIntoConstraints = false
        rightButtons.axis = .horizontal; rightButtons.spacing = 16; rightButtons.alignment = .bottom

        // Title row: leftStack (flex-1) | rightButtons (w-auto)
        titleRowStack = UIStackView(arrangedSubviews: [leftStack, rightButtons])
        titleRowStack.translatesAutoresizingMaskIntoConstraints = false
        titleRowStack.axis = .horizontal; titleRowStack.spacing = 8; titleRowStack.alignment = .fill
        titleRowStack.layoutMargins = UIEdgeInsets(top: 20, left: 8, bottom: 8, right: 8) // pt-5, px-2
        titleRowStack.isLayoutMarginsRelativeArrangement = true
        headerView.addSubview(titleRowStack)
        // Anchor to safeAreaLayoutGuide so content starts below the status bar.
        // The layoutMargins.top = 20 provides the pt-5 breathing room inside.
        NSLayoutConstraint.activate([
            titleRowStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            titleRowStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            titleRowStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
        ])
        titleRowSpacerHeightConstraint = titleRowStack.heightAnchor.constraint(equalToConstant: 20)
        titleRowSpacerHeightConstraint.isActive = false
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
        chipsHeightConstraint = chipsContainer.heightAnchor.constraint(equalToConstant: 36)
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
        if #available(iOS 14, *) {
            var config = PHPickerConfiguration()
            config.filter = .images; config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self; present(picker, animated: true)
        } else {
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary; picker.delegate = self
            present(picker, animated: true)
        }
    }

    @objc private func boltTapped() {
        filterRowVisible.toggle()
        updateResponsiveHeaderLayout(animated: true)
        updateBoltTint()
    }

    @objc private func searchFieldChanged(_ field: UITextField) {
        handleSearchTextChanged(field.text ?? "")
    }

    @objc private func clearTapped() {
        clearSearchState()
    }

    private func handleSearchTextChanged(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if searchField.text != text { searchField.text = text }
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self = self, query != self.currentTitle else { return }
            self.currentTitle = query
            self.rebuildActiveChipEntries()
            self.rebuildActiveChips()
            self.fetchResults(reset: true)
        }
    }

    private func clearSearchState() {
        selectedGenres = []
        selectedTags = []
        selectedYear = nil
        selectedSeason = nil
        selectedFormats = []
        selectedStatuses = []
        selectedSort = nil
        selectedOnList = nil
        traceIds = nil
        currentTitle = ""
        searchField.text = ""
        debounceTimer?.invalidate()
        rebuildActiveChipEntries()
        refreshFilterPickers()
        rebuildActiveChips()
        updateBoltTint()
        fetchResults(reset: true)
    }

    private var hasAnySearchState: Bool {
        !currentTitle.isEmpty || !selectedGenres.isEmpty || !selectedTags.isEmpty
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

    private func isRegularSearchLayout(width: CGFloat? = nil) -> Bool {
        let value = width ?? view.bounds.width
        return value >= 768 || traitCollection.horizontalSizeClass == .regular
    }

    private func updateResponsiveHeaderLayout(animated: Bool, targetWidth: CGFloat? = nil) {
        guard isViewLoaded, filterCollectionView != nil else { return }
        let width = max(targetWidth ?? view.bounds.width, 320)
        let regular = isRegularSearchLayout(width: width)
        let visible = regular || filterRowVisible

        leftStack.isHidden = regular
        rightButtons.isHidden = regular
        titleRowSpacerHeightConstraint.isActive = regular
        titleRowStack.layoutMargins = regular
            ? UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
            : UIEdgeInsets(top: 20, left: 8, bottom: 8, right: 8)
        let chipInset = (regular ? Self.regularHorizontalInset : 8) + 4
        chipsLeadingConstraint.constant = chipInset
        chipsTrailingConstraint.constant = -chipInset

        if let layout = filterCollectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.scrollDirection = regular ? .vertical : .horizontal
            layout.minimumInteritemSpacing = 0
            layout.minimumLineSpacing = 0
            layout.sectionInset = UIEdgeInsets(top: 0,
                                               left: regular ? Self.regularHorizontalInset : 8,
                                               bottom: 0,
                                               right: regular ? Self.regularHorizontalInset : 8)
            layout.invalidateLayout()
        }

        let signature = filterLayoutSignature(isRegular: regular, isVisible: visible)
        let shouldReloadFilters = signature != lastFilterLayoutSignature
        lastFilterLayoutSignature = signature

        let rows: CGFloat
        if !visible {
            rows = 0
        } else if regular {
            rows = visibleHeaderItems.count > 4 ? 2 : 1
        } else {
            rows = 1
        }
        filterCollectionView.isScrollEnabled = !regular
        filterRowHeightConstraint.constant = rows * Self.filterPanelHeight
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

    private func filterLayoutSignature(isRegular: Bool, isVisible: Bool) -> String {
        let itemSignature = visibleHeaderItems.map { item -> String in
            switch item {
            case .title: return "title"
            case .actions: return "actions"
            case .filter(let type): return "filter-\(type.rawValue)"
            }
        }.joined(separator: ",")
        return "regular=\(isRegular);visible=\(isVisible);items=\(itemSignature)"
    }

    private func filterItemSize(for indexPath: IndexPath, in collectionView: UICollectionView) -> CGSize {
        guard isRegularSearchLayout() else {
            return CGSize(width: Self.filterItemMinWidth, height: Self.filterPanelHeight)
        }

        let usableWidth = max(collectionView.bounds.width - Self.regularHorizontalInset * 2,
                              Self.filterItemMinWidth * 2)
        let item = visibleHeaderItems[safe: indexPath.item]
        if case .actions? = item {
            return CGSize(width: Self.regularActionWidth, height: Self.filterPanelHeight)
        }

        let width: CGFloat
        if indexPath.item < 4 {
            width = floor(usableWidth / 4)
        } else {
            let secondRowFilterCount = visibleHeaderItems
                .dropFirst(4)
                .filter {
                    if case .actions = $0 { return false }
                    return true
                }
                .count
            let divisor = CGFloat(max(1, secondRowFilterCount))
            width = floor((usableWidth - Self.regularActionWidth) / divisor)
        }
        return CGSize(width: max(Self.filterItemMinWidth, width), height: Self.filterPanelHeight)
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
        case .genres: return Set(selectedGenres + selectedTags)
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

    private func applySelection(_ values: Set<String>, for type: SearchFilterType) {
        let ordered = orderedValues(Array(values), for: type)
        switch type {
        case .genres:
            selectedGenres = ordered.filter { SearchValues.genreSet.contains($0) }
            selectedTags = ordered.filter { !SearchValues.genreSet.contains($0) }
        case .year:
            selectedYear = ordered.first
        case .season:
            selectedSeason = ordered.first
        case .format:
            selectedFormats = ordered
        case .status:
            selectedStatuses = ordered
        case .sort:
            selectedSort = ordered.first
        case .onList:
            selectedOnList = ordered.first.map { $0 == "true" }
        case .trace:
            if ordered.isEmpty { clearTrace(); return }
        case .title:
            currentTitle = ordered.first ?? ""
            searchField.text = currentTitle
        }
        rebuildActiveChipEntries()
        refreshFilterPickers()
        rebuildActiveChips()
        updateBoltTint()
        fetchResults(reset: true)
    }

    private func orderedValues(_ values: [String], for type: SearchFilterType) -> [String] {
        let selected = Set(values)
        let ordered = SearchValues.options(for: type)
            .map(\.value)
            .filter { selected.contains($0) }
        let extras = values.filter { !ordered.contains($0) }
        return ordered + extras
    }

    private func clearFilter(type: SearchFilterType) {
        if type == .trace {
            clearTrace()
            return
        }
        applySelection([], for: type)
    }

    private func updateBoltTint() {
        boltButton.pressed = filterRowVisible
    }

    private func selectedTitle(for type: SearchFilterType) -> String {
        let values = orderedValues(Array(selectedValues(for: type)), for: type)
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

    private func rebuildActiveChipEntries() {
        var entries: [(label: String, type: SearchFilterType, apiValue: String)] = []
        if !currentTitle.isEmpty {
            entries.append((currentTitle, .title, currentTitle))
        }
        for value in selectedGenres {
            entries.append((SearchValues.label(for: value, in: .genres), .genres, value))
        }
        for value in selectedTags {
            entries.append((SearchValues.label(for: value, in: .genres), .genres, value))
        }
        if let selectedYear = selectedYear {
            entries.append((selectedYear, .year, selectedYear))
        }
        if let selectedSeason = selectedSeason {
            entries.append((SearchValues.label(for: selectedSeason, in: .season), .season, selectedSeason))
        }
        for value in selectedFormats {
            entries.append((SearchValues.label(for: value, in: .format), .format, value))
        }
        for value in selectedStatuses {
            entries.append((SearchValues.label(for: value, in: .status), .status, value))
        }
        if let selectedSort = selectedSort {
            entries.append((SearchValues.label(for: selectedSort, in: .sort), .sort, selectedSort))
        }
        if let selectedOnList = selectedOnList {
            let value = selectedOnList ? "true" : "false"
            entries.append((SearchValues.label(for: value, in: .onList), .onList, value))
        }
        if traceIds != nil {
            entries.append(("IDs", .trace, "trace"))
        }
        activeChipEntries = entries
    }

    // MARK: - Active chips (wrapping frame layout)
    // Hayase: flex flex-row flex-wrap mt-2 min-h-9 pb-1 px-1, chips: mx-1.5 my-1

    private func rebuildActiveChips() {
        chipsContainer.subviews.forEach { $0.removeFromSuperview() }
        guard !activeChipEntries.isEmpty else {
            UIView.animate(withDuration: 0.2) {
                self.chipsHeightConstraint.constant = 36
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

        let newH = max(36, y + rowH + 4)
        UIView.animate(withDuration: 0.2) {
            self.chipsHeightConstraint.constant = newH
            self.headerView.layoutIfNeeded(); self.view.layoutIfNeeded()
        }
    }

    private func makeActiveChip(label: String, type: SearchFilterType, apiValue: String) -> UIView {
        let chip = Badge()
        chip.text = label
        chip.accessibilityLabel = label
        chip.accessibilityIdentifier = "\(type.rawValue):\(apiValue)"
        chip.addTarget(self, action: #selector(removeChipTapped(_:)), for: .touchUpInside)
        return chip
    }

    @objc private func removeChipTapped(_ sender: UIControl) {
        guard let id = sender.accessibilityIdentifier, let colon = id.range(of: ":") else { return }
        let typeRaw  = Int(id[id.startIndex..<colon.lowerBound]) ?? -1
        let apiValue = String(id[colon.upperBound...])
        guard let type = SearchFilterType(rawValue: typeRaw) else { return }
        switch type {
        case .title:
            currentTitle = ""
            searchField.text = ""
            debounceTimer?.invalidate()
            filterCollectionView?.reloadData()
        case .genres:
            selectedGenres.removeAll { $0 == apiValue }
            selectedTags.removeAll { $0 == apiValue }
            activeChipEntries.removeAll { $0.type == .genres && $0.apiValue == apiValue }
        case .year:    selectedYear = nil;   activeChipEntries.removeAll { $0.type == .year }
        case .season:  selectedSeason = nil; activeChipEntries.removeAll { $0.type == .season }
        case .format:  selectedFormats.removeAll { $0 == apiValue };  activeChipEntries.removeAll { $0.type == .format && $0.apiValue == apiValue }
        case .status:  selectedStatuses.removeAll { $0 == apiValue }; activeChipEntries.removeAll { $0.type == .status && $0.apiValue == apiValue }
        case .sort:    selectedSort = nil; activeChipEntries.removeAll { $0.type == .sort }
        case .onList:  selectedOnList = nil; activeChipEntries.removeAll { $0.type == .onList }
        case .trace:   clearTrace(); return  // clearTrace() handles its own fetch
        }
        refreshFilterPickers(); rebuildActiveChips(); updateBoltTint(); fetchResults(reset: true)
    }

    // MARK: - Collection view

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = Self.bgBackground
        collectionView.delegate = self; collectionView.dataSource = self
        collectionView.register(AnimeCollectionViewCell.self,
                                forCellWithReuseIdentifier: AnimeCollectionViewCell.reuseID)
        collectionView.register(SkeletonCardCell.self,
                                forCellWithReuseIdentifier: SkeletonCardCell.reuseID)
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

    private func resultSectionInsets(for width: CGFloat) -> UIEdgeInsets {
        let horizontalPadding: CGFloat = isRegularSearchLayout(width: width) ? 28 : 0
        let available = max(width - horizontalPadding * 2, AnimeCollectionViewCell.outerWidth)
        let columns = max(1, floor(available / AnimeCollectionViewCell.outerWidth))
        let used = columns * AnimeCollectionViewCell.outerWidth
        let centeredInset = floor((width - used) / 2)
        let inset = max(horizontalPadding, centeredInset)
        return UIEdgeInsets(top: 12, left: inset, bottom: 16, right: inset)
    }

    // MARK: - Overlays

    private func setupOverlays() {
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true; loadingIndicator.color = .white
        view.addSubview(loadingIndicator)

        emptyLabel = UILabel()
        emptyLabel.textColor = Self.mutedFg; emptyLabel.font = .nunito(ofSize: 16)
        emptyLabel.textAlignment = .center; emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true; emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 60),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 60),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
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
        }
        guard !isFetching, hasNextPage else { return }
        isFetching = true
        if reset {
            // Show skeleton placeholders instead of spinner (matches web fetching → SkeletonCard)
            isShowingSkeleton = true
            collectionView.reloadData()
            emptyLabel.isHidden = true
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
                self.loadingIndicator.stopAnimating()
                let updatedResults: [AnimeItem]
                if reset {
                    if page.isCacheResult || self.currentPage <= requestedPage + 1 {
                        updatedResults = page.items
                    } else {
                        let tailStart = min(page.items.count, self.animeResults.count)
                        updatedResults = page.items + Array(self.animeResults.dropFirst(tailStart))
                    }
                } else if page.isCacheResult {
                    updatedResults = self.animeResults + page.items
                } else if self.animeResults.count > previousResults.count {
                    let prefix = Array(self.animeResults.prefix(previousResults.count))
                    let tailStart = min(previousResults.count + page.items.count, self.animeResults.count)
                    let tail = Array(self.animeResults.dropFirst(tailStart))
                    updatedResults = prefix + page.items + tail
                } else {
                    updatedResults = self.animeResults + page.items
                }
                self.hasNextPage = page.hasNextPage
                self.currentPage = max(self.currentPage, requestedPage + 1)
                self.emptyLabel.isHidden = !updatedResults.isEmpty
                if updatedResults.isEmpty {
                    self.emptyLabel.text = self.currentTitle.isEmpty
                        ? "No results found" : "No results for \"\(self.currentTitle)\""
                }
                self.applySearchResults(updatedResults)
            case .failure(let error):
                self.isFetching = false
                self.searchTask = nil
                self.isShowingSkeleton = false
                self.loadingIndicator.stopAnimating()
                if reset { self.applySearchResults([], animated: false) }
                self.hasNextPage = false
                self.emptyLabel.isHidden = false
                self.emptyLabel.text = "AniList request failed. Pull to retry.\n\(error.description)"
            }
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleTrackingDidChange(_:)),
                                               name: LocalTracking.didChange,
                                               object: nil)
    }

    @objc private func handleTrackingDidChange(_ notification: Notification) {
        guard selectedOnList != nil else { return }
        trackingRefreshTimer?.invalidate()
        trackingRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.fetchResults(reset: true)
        }
    }

    private func applySearchResults(_ results: [AnimeItem], animated: Bool = true) {
        let previousFrames = animated ? visibleSearchItemFrames() : [:]
        let shouldFlip = !previousFrames.isEmpty &&
            !animeResults.isEmpty &&
            !results.isEmpty &&
            animeResults.map(\.id) != results.map(\.id)

        animeResults = results
        guard isViewLoaded, collectionView != nil else { return }

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
    // Hayase: traceAnime(file) from $lib/utils → POST multipart to api.trace.moe/search
    // On success: clear() all filters, set search.ids = unique anilist IDs, show results.
    //

    /// Upload an image to trace.moe and show matching anime.
    /// Mirrors Hayase's traceReq() behaviour exactly.
    private func performTraceSearch(imageData: Data) {
        guard !isTracing else { return }
        isTracing = true
        cameraButton.tintColor = Self.activeBlue   // blue tint while loading
        isShowingSkeleton = true
        collectionView.reloadData()
        emptyLabel.isHidden = true

        let boundary = "Boundary-\(UUID().uuidString)"
        guard let url = URL(string: "https://api.trace.moe/search") else {
            finishTrace(success: false); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { if let d = s.data(using: .utf8) { body.append(d) } }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isTracing = false
                self.cameraButton.tintColor = Self.mutedFg
                self.isShowingSkeleton = false

                guard let data = data,
                      let resp = try? JSONDecoder().decode(TraceMoeResponse.self, from: data),
                      (resp.error ?? "").isEmpty,
                      !resp.result.isEmpty else {
                    self.finishTrace(success: false)
                    return
                }
                // Deduplicate IDs, preserving result order
                var seen = Set<Int>()
                let ids = resp.result.map { $0.anilist }.filter { seen.insert($0).inserted }
                self.applyTraceResults(ids: ids)
            }
        }.resume()
    }

    /// Called after trace.moe returns IDs — clears filters and shows trace results.
    /// Mirrors Hayase's clear() + search.ids = [...] sequence.
    private func applyTraceResults(ids: [Int]) {
        // Clear all regular filters (mirrors Hayase's clear())
        selectedGenres = []; selectedTags = []; selectedYear = nil; selectedSeason = nil
        selectedFormats = []; selectedStatuses = []; selectedSort = nil; selectedOnList = nil
        currentTitle = ""; searchField.text = ""
        traceIds = ids
        rebuildActiveChipEntries()
        refreshFilterPickers()
        rebuildActiveChips()
        updateBoltTint()
        fetchResults(reset: true)
    }

    /// Clears trace state and returns to a normal search.
    /// Mirrors removing the "IDs" chip in Hayase (remove("IDs") → search.ids = undefined).
    private func clearTrace() {
        traceIds = nil
        rebuildActiveChipEntries()
        rebuildActiveChips()
        updateBoltTint()
        fetchResults(reset: true)
    }

    /// Shows an error alert when trace.moe found nothing.
    private func finishTrace(success: Bool) {
        isTracing = false
        cameraButton.tintColor = Self.mutedFg
        isShowingSkeleton = false
        loadingIndicator.stopAnimating()
        collectionView.reloadData()
        guard !success else { return }
        emptyLabel.isHidden = !animeResults.isEmpty
        let alert = UIAlertController(
            title: "Image Search",
            message: "Couldn't find anime for the specified image.\nTry removing black bars or using a more detailed image.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Fetch by IDs (trace.moe results)

    private func fetchResultsByIds(_ ids: [Int]) {
        guard !isFetching else { return }
        isFetching = true
        isShowingSkeleton = true
        collectionView.reloadData()
        emptyLabel.isHidden = true

        AniListClient.shared.fetchAnimeByIdsResult(ids) { [weak self] result in
            guard let self = self else { return }
            self.hasNextPage = false
            self.currentPage = 2
            self.isFetching = false
            self.isShowingSkeleton = false
            self.loadingIndicator.stopAnimating()

            switch result {
            case .success(let items):
                self.applySearchResults(items)
                self.emptyLabel.isHidden = !items.isEmpty
                if items.isEmpty { self.emptyLabel.text = "No matching anime found" }
            case .failure(let error):
                self.applySearchResults([], animated: false)
                self.emptyLabel.isHidden = false
                self.emptyLabel.text = "AniList request failed. Pull to retry.\n\(error.description)"
            }
        }
    }
}

// MARK: - UICollectionViewDataSource

extension SearchViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        if collectionView === filterCollectionView {
            return visibleHeaderItems.count
        }
        // Web: shows 50 SkeletonCard while fetching; we show enough to fill the visible area
        if isShowingSkeleton { return 50 }
        return animeResults.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView === filterCollectionView {
            guard let item = visibleHeaderItems[safe: indexPath.item] else {
                return UICollectionViewCell()
            }
            switch item {
            case .title:
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SearchTitleItemCell.reuseID,
                    for: indexPath) as? SearchTitleItemCell else { return UICollectionViewCell() }
                cell.configure(text: currentTitle)
                cell.onTextChanged = { [weak self] text in
                    self?.handleSearchTextChanged(text)
                }
                return cell
            case .filter(let type):
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SearchFilterItemCell.reuseID,
                    for: indexPath) as? SearchFilterItemCell else { return UICollectionViewCell() }
                let title = selectedTitle(for: type)
                cell.configure(type: type,
                               title: title,
                               placeholder: isPlaceholderTitle(title, for: type))
                return cell
            case .actions:
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SearchActionItemCell.reuseID,
                    for: indexPath) as? SearchActionItemCell else { return UICollectionViewCell() }
                cell.configure(clearEnabled: hasAnySearchState)
                cell.onImageTapped = { [weak self] in self?.cameraTapped() }
                cell.onClearTapped = { [weak self] in self?.clearSearchState() }
                return cell
            }
        }
        if isShowingSkeleton {
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: SkeletonCardCell.reuseID, for: indexPath)
        }
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: AnimeCollectionViewCell.reuseID,
            for: indexPath) as? AnimeCollectionViewCell else { return UICollectionViewCell() }
        guard let item = animeResults[safe: indexPath.item] else { return cell }
        cell.configure(with: item)
        Hover.shared.bind(to: cell,
                          host: self,
                          mediaProvider: { item },
                          actions: hayasePreviewCardActions())
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
                                             actions: hayasePreviewCardActions()) {
            return
        }
        Router.shared.navigateToAnime(item, hostTabIndex: tabBarController?.selectedIndex)
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
            return filterItemSize(for: indexPath, in: collectionView)
        }
        return CGSize(width: AnimeCollectionViewCell.outerWidth,
                      height: AnimeCollectionViewCell.outerHeight)
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

// MARK: - PHPickerViewControllerDelegate (iOS 14+)

@available(iOS 14, *)
extension SearchViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.hasItemConformingToTypeIdentifier("public.image") else { return }
        provider.loadDataRepresentation(forTypeIdentifier: "public.image") { [weak self] data, _ in
            guard let data = data else { return }
            // Convert to JPEG at a moderate quality to reduce payload size for trace.moe
            let jpegData = UIImage(data: data)?.jpegData(compressionQuality: 0.8) ?? data
            DispatchQueue.main.async { self?.performTraceSearch(imageData: jpegData) }
        }
    }
}

// MARK: - UIImagePickerControllerDelegate (iOS 13)

extension SearchViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
        guard let jpegData = image?.jpegData(compressionQuality: 0.8) else { return }
        performTraceSearch(imageData: jpegData)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - SearchTitleItemCell

private final class SearchTitleItemCell: UICollectionViewCell, UITextFieldDelegate {
    static let reuseID = "SearchTitleItemCell"

    var onTextChanged: ((String) -> Void)?

    private let titleLabel = UILabel()
    private let searchField = Input(placeholder: "Any", iconName: "search")

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
        onTextChanged?(textField.text ?? "")
        return true
    }
}

// MARK: - SearchActionItemCell

private final class SearchActionItemCell: UICollectionViewCell {
    static let reuseID = "SearchActionItemCell"

    var onImageTapped: (() -> Void)?
    var onClearTapped: (() -> Void)?

    private let imageButton = Button(iconName: "file-image", pointSize: 16)
    private let clearButton = Button(iconName: "trash", pointSize: 16)

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
            imageButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            clearButton.bottomAnchor.constraint(equalTo: imageButton.bottomAnchor),
        ])
    }

    func configure(clearEnabled: Bool) {
        clearButton.tintColor = clearEnabled
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
