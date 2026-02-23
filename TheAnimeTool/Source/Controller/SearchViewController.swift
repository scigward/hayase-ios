//
//  SearchViewController.swift
//  NyaiS
//
//  Hayase-style AniList anime search tab.
//  Ported from src/routes/app/search/+page.svelte + values.ts
//
//  Mobile layout (matches !$breakpoints.md branch):
//  ┌─────────────────────────────────────────────┐
//  │ [🔍 Any                          ] [📷] [⚡] │  ← always visible
//  │ [Genre][Year][Season][Format][Status][Sort]  │  ← shown when ⚡ tapped
//  │ [Action ×] [2024 ×] [Score ×]               │  ← active filter chips
//  └─────────────────────────────────────────────┘
//  2-column AnimeCollectionViewCell grid (minmax(184px))
//

import UIKit

// MARK: - FilterOption

private struct FilterOption {
    let displayName: String
    let apiValue: String
}

// MARK: - FilterType

private enum FilterType: Int, CaseIterable {
    case genre, year, season, format, status, sort

    var label: String {
        switch self {
        case .genre:  return "Genres"
        case .year:   return "Year"
        case .season: return "Season"
        case .format: return "Formats"
        case .status: return "Status"
        case .sort:   return "Sort"
        }
    }

    // Options exactly from values.ts
    var options: [FilterOption] {
        switch self {
        case .genre:
            // 18 genres from values.ts (exact order)
            return [
                .init(displayName: "Action",        apiValue: "Action"),
                .init(displayName: "Adventure",     apiValue: "Adventure"),
                .init(displayName: "Comedy",        apiValue: "Comedy"),
                .init(displayName: "Drama",         apiValue: "Drama"),
                .init(displayName: "Ecchi",         apiValue: "Ecchi"),
                .init(displayName: "Fantasy",       apiValue: "Fantasy"),
                .init(displayName: "Horror",        apiValue: "Horror"),
                .init(displayName: "Mahou Shoujo",  apiValue: "Mahou Shoujo"),
                .init(displayName: "Mecha",         apiValue: "Mecha"),
                .init(displayName: "Music",         apiValue: "Music"),
                .init(displayName: "Mystery",       apiValue: "Mystery"),
                .init(displayName: "Psychological", apiValue: "Psychological"),
                .init(displayName: "Romance",       apiValue: "Romance"),
                .init(displayName: "Sci-Fi",        apiValue: "Sci-Fi"),
                .init(displayName: "Slice of Life", apiValue: "Slice of Life"),
                .init(displayName: "Sports",        apiValue: "Sports"),
                .init(displayName: "Supernatural",  apiValue: "Supernatural"),
                .init(displayName: "Thriller",      apiValue: "Thriller"),
            ]
        case .year:
            // Array.from({ length: currentYear - 1940 + 2 }, (_, i) => '' + (currentYear + 2 - i))
            let current = Calendar.current.component(.year, from: Date())
            return (0...(current - 1940 + 1)).map { i in
                let y = current + 2 - i
                return FilterOption(displayName: "\(y)", apiValue: "\(y)")
            }
        case .season:
            return [
                .init(displayName: "Spring", apiValue: "SPRING"),
                .init(displayName: "Summer", apiValue: "SUMMER"),
                .init(displayName: "Fall",   apiValue: "FALL"),
                .init(displayName: "Winter", apiValue: "WINTER"),
            ]
        case .format:
            // From values.ts formats array
            return [
                .init(displayName: "TV Show",  apiValue: "TV"),
                .init(displayName: "Movie",    apiValue: "MOVIE"),
                .init(displayName: "TV Short", apiValue: "TV_SHORT"),
                .init(displayName: "OVA",      apiValue: "OVA"),
                .init(displayName: "ONA",      apiValue: "ONA"),
            ]
        case .status:
            // From values.ts status array (includes Cancelled)
            return [
                .init(displayName: "Airing",       apiValue: "RELEASING"),
                .init(displayName: "Finished",     apiValue: "FINISHED"),
                .init(displayName: "Not Yet Aired", apiValue: "NOT_YET_RELEASED"),
                .init(displayName: "Cancelled",    apiValue: "CANCELLED"),
            ]
        case .sort:
            // All 12 options from values.ts sort array
            return [
                .init(displayName: "Trending",          apiValue: "TRENDING_DESC"),
                .init(displayName: "Popularity",        apiValue: "POPULARITY_DESC"),
                .init(displayName: "Score",             apiValue: "SCORE_DESC"),
                .init(displayName: "Release Date",      apiValue: "START_DATE_DESC"),
                .init(displayName: "Name",              apiValue: "TITLE_ROMAJI_DESC"),
                .init(displayName: "Updated Date",      apiValue: "UPDATED_AT_DESC"),
                .init(displayName: "Trending Asc",      apiValue: "TRENDING"),
                .init(displayName: "Popularity Asc",    apiValue: "POPULARITY"),
                .init(displayName: "Score Asc",         apiValue: "SCORE"),
                .init(displayName: "Release Date Asc",  apiValue: "START_DATE"),
                .init(displayName: "Name Asc",          apiValue: "TITLE_ROMAJI"),
                .init(displayName: "Updated Date Asc",  apiValue: "UPDATED_AT"),
            ]
        }
    }
}

// MARK: - SearchViewController

class SearchViewController: UIViewController {

    // MARK: - Hayase color constants
    // app.css: --background: 240 10% 3.9% = #0a0a0f, bg-black = #000000
    private static let bgBlack      = UIColor.black
    private static let bgBackground = UIColor(red: 0.039, green: 0.039, blue: 0.059, alpha: 1)
    private static let mutedFg      = UIColor(red: 0.631, green: 0.631, blue: 0.667, alpha: 1) // #a1a1aa
    // text-blue-400 = UIColor used on Hayase's active filter icon
    private static let activeBlue   = UIColor(red: 0.369, green: 0.647, blue: 0.953, alpha: 1)
    // badgeVariants default dark: bg-primary (#fafafa), text-primary-foreground (#0f0f14)
    private static let chipBg       = UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
    private static let chipFg       = UIColor(red: 0.059, green: 0.059, blue: 0.078, alpha: 1)

    // MARK: - Filter state (one value per filter type)
    private var selectedGenre:  String?
    private var selectedYear:   Int?
    private var selectedSeason: String?
    private var selectedFormat: String?
    private var selectedStatus: String?
    private var selectedSort = "TRENDING_DESC"

    // Display names for active chips
    private var activeFilterLabels: [String: (type: FilterType, apiValue: String)] = [:]

    // MARK: - Results state
    private var animeResults: [AnimeItem] = []
    private var currentPage = 1
    private var hasNextPage = true
    private var isFetching = false
    private var currentTitle = ""
    private var debounceTimer: Timer?

    // MARK: - Views
    private var headerView: UIView!
    private var searchField: UITextField!
    private var boltButton: UIButton!
    private var filterRowVisible = false
    private var filterRow: UIScrollView!
    private var filterStack: UIStackView!
    private var activeChipsRow: UIScrollView!
    private var activeChipsStack: UIStackView!
    private var collectionView: UICollectionView!
    private var loadingIndicator: UIActivityIndicatorView!
    private var emptyLabel: UILabel!

    // Dynamic height constraints for header
    private var filterRowHeightConstraint: NSLayoutConstraint!
    private var activeChipsRowHeightConstraint: NSLayoutConstraint!

    private static let filterRowHeight: CGFloat  = 44
    private static let activeChipsRowHeight: CGFloat = 36

    // Pending prefill from Home "View More" — applied in viewWillAppear if view not yet loaded
    private var pendingPrefill: (genre: String?, sort: String?)?

    // MARK: - Init (set tabBarItem before viewDidLoad per iOS tab bar rules)

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Search",
            image: UIImage(systemName: "magnifyingglass"),
            selectedImage: UIImage(systemName: "magnifyingglass.circle.fill"))
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.bgBackground
        setupNavigationBar()
        setupHeaderView()
        setupCollectionView()
        setupOverlays()
        fetchResults(reset: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        collectionView.indexPathsForSelectedItems?.forEach {
            collectionView.deselectItem(at: $0, animated: animated)
        }
        // Apply any prefill stored while the view wasn't loaded yet
        if let pending = pendingPrefill {
            pendingPrefill = nil
            applyPrefill(genre: pending.genre, sort: pending.sort)
        }
    }

    // MARK: - Prefill from home "View More"
    // Matches Hayase: goto('/app/search', { state: { search: variables } })
    // Called by BrowseAnimeViewController before switching to the Search tab.
    func prefillSearch(genre: String?, sort: String?) {
        if isViewLoaded {
            applyPrefill(genre: genre, sort: sort)
        } else {
            // View not loaded yet (Search tab not visited); store and apply in viewWillAppear
            pendingPrefill = (genre: genre, sort: sort)
        }
    }

    private func applyPrefill(genre: String?, sort: String?) {
        // Clear existing filters first
        selectedGenre  = nil
        selectedYear   = nil
        selectedSeason = nil
        selectedFormat = nil
        selectedStatus = nil
        selectedSort   = "TRENDING_DESC"
        activeFilterLabels.removeAll()

        if let genre = genre {
            selectedGenre = genre
            activeFilterLabels[FilterType.genre.label] = (type: .genre, apiValue: genre)
        }
        if let sort = sort, sort != "TRENDING_DESC" {
            selectedSort = sort
        }
        rebuildActiveChips()
        updateBoltTint()
        fetchResults(reset: true)
    }

    // MARK: - Navigation bar
    // Compact title "Search" (no large title, no UISearchController)
    // Nav bar hidden behind header which starts at safeArea top
    private func setupNavigationBar() {
        title = nil // no nav title — header provides context
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        // Make nav bar transparent so the black header shows through behind status bar
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
    }

    // MARK: - Header setup
    // Matches Hayase sticky top div: bg-black, pt-5
    private func setupHeaderView() {
        headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = Self.bgBlack
        view.addSubview(headerView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        setupTitleRow()
        setupFilterRow()
        setupActiveChipsRow()
    }

    // Title row: [🔍 Any field] [📷] [⚡]
    // Matches: <Input pl-9 border-0 bg-background> + FileImage button + Bolt toggle
    private func setupTitleRow() {
        // Container row
        let titleRow = UIStackView()
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center
        titleRow.layoutMargins = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        titleRow.isLayoutMarginsRelativeArrangement = true
        headerView.addSubview(titleRow)

        // Search field — bg-background, border-0, rounded, pl-9 (icon inside)
        searchField = UITextField()
        searchField.backgroundColor = Self.bgBackground
        searchField.layer.cornerRadius = 8
        searchField.layer.masksToBounds = true
        searchField.borderStyle = .none
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Any",
            attributes: [.foregroundColor: Self.mutedFg.withAlphaComponent(0.5)])
        searchField.textColor = .white
        searchField.font = .systemFont(ofSize: 15)
        // pl-9: left view with magnifying glass icon + 8pt padding
        let iconContainer = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        let iconImageView = UIImageView(
            image: UIImage(systemName: "magnifyingglass")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)))
        iconImageView.tintColor = Self.mutedFg.withAlphaComponent(0.5)
        iconImageView.contentMode = .center
        iconImageView.frame = iconContainer.bounds
        iconContainer.addSubview(iconImageView)
        searchField.leftView = iconContainer
        searchField.leftViewMode = .always
        searchField.addTarget(self, action: #selector(searchFieldChanged(_:)), for: .editingChanged)
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none

        // Filter toggle — slider.horizontal.3 = filter icon
        // Matches Hayase <Bolt> icon toggle (bolt = filter/settings icon)
        boltButton = UIButton(type: .system)
        let boltImage = UIImage(systemName: "slider.horizontal.3")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        boltButton.setImage(boltImage, for: .normal)
        boltButton.tintColor = Self.mutedFg
        boltButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        boltButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        boltButton.addTarget(self, action: #selector(boltTapped), for: .touchUpInside)

        titleRow.addArrangedSubview(searchField)
        titleRow.addArrangedSubview(boltButton)

        NSLayoutConstraint.activate([
            titleRow.topAnchor.constraint(equalTo: headerView.topAnchor),
            titleRow.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            titleRow.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            titleRow.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    // Filter row (hidden by default): [Genre][Year][Season][Format][Status][Sort]
    // Shown when bolt toggle is tapped. Each chip opens an action sheet picker.
    private func setupFilterRow() {
        filterRow = UIScrollView()
        filterRow.translatesAutoresizingMaskIntoConstraints = false
        filterRow.showsHorizontalScrollIndicator = false
        filterRow.alwaysBounceHorizontal = true
        filterRow.contentInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        headerView.addSubview(filterRow)

        filterStack = UIStackView()
        filterStack.translatesAutoresizingMaskIntoConstraints = false
        filterStack.axis = .horizontal
        filterStack.spacing = 8
        filterStack.alignment = .center
        filterRow.addSubview(filterStack)

        NSLayoutConstraint.activate([
            filterStack.topAnchor.constraint(equalTo: filterRow.topAnchor, constant: 4),
            filterStack.bottomAnchor.constraint(equalTo: filterRow.bottomAnchor, constant: -4),
            filterStack.leadingAnchor.constraint(equalTo: filterRow.leadingAnchor),
            filterStack.trailingAnchor.constraint(equalTo: filterRow.trailingAnchor),
            filterStack.heightAnchor.constraint(equalToConstant: Self.filterRowHeight - 8),
        ])

        filterRowHeightConstraint = filterRow.heightAnchor.constraint(equalToConstant: 0)
        filterRowHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            filterRow.topAnchor.constraint(equalTo: headerView.subviews.first!.bottomAnchor),
            filterRow.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            filterRow.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
        ])

        // Build filter chips
        for type in FilterType.allCases {
            let chip = makeFilterChip(for: type)
            filterStack.addArrangedSubview(chip)
        }
    }

    private func makeFilterChip(for type: FilterType) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(type.label, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(red: 0.094, green: 0.094, blue: 0.106, alpha: 1) // #18181b = muted
        btn.layer.cornerRadius = 8
        btn.layer.masksToBounds = true
        btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        btn.tag = type.rawValue
        btn.addTarget(self, action: #selector(filterChipTapped(_:)), for: .touchUpInside)
        return btn
    }

    // Active chips row: removable white pill badges
    // Matches Hayase: {#each list(search) as item} → <badge class='mx-1.5 my-1 ...'>
    private func setupActiveChipsRow() {
        activeChipsRow = UIScrollView()
        activeChipsRow.translatesAutoresizingMaskIntoConstraints = false
        activeChipsRow.showsHorizontalScrollIndicator = false
        activeChipsRow.alwaysBounceHorizontal = false
        activeChipsRow.contentInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        headerView.addSubview(activeChipsRow)

        activeChipsStack = UIStackView()
        activeChipsStack.translatesAutoresizingMaskIntoConstraints = false
        activeChipsStack.axis = .horizontal
        activeChipsStack.spacing = 6
        activeChipsStack.alignment = .center
        activeChipsRow.addSubview(activeChipsStack)

        NSLayoutConstraint.activate([
            activeChipsStack.topAnchor.constraint(equalTo: activeChipsRow.topAnchor, constant: 4),
            activeChipsStack.bottomAnchor.constraint(equalTo: activeChipsRow.bottomAnchor, constant: -4),
            activeChipsStack.leadingAnchor.constraint(equalTo: activeChipsRow.leadingAnchor),
            activeChipsStack.trailingAnchor.constraint(equalTo: activeChipsRow.trailingAnchor),
            activeChipsStack.heightAnchor.constraint(equalToConstant: Self.activeChipsRowHeight - 8),
        ])

        activeChipsRowHeightConstraint = activeChipsRow.heightAnchor.constraint(equalToConstant: 0)
        activeChipsRowHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            activeChipsRow.topAnchor.constraint(equalTo: filterRow.bottomAnchor),
            activeChipsRow.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            activeChipsRow.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            activeChipsRow.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func boltTapped() {
        filterRowVisible.toggle()
        UIView.animate(withDuration: 0.25) {
            self.filterRowHeightConstraint.constant = self.filterRowVisible ? Self.filterRowHeight : 0
            self.boltButton.tintColor = self.filterRowVisible ? Self.activeBlue : Self.mutedFg
            self.headerView.layoutIfNeeded()
            self.view.layoutIfNeeded()
        }
    }

    @objc private func searchFieldChanged(_ field: UITextField) {
        let query = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self = self, query != self.currentTitle else { return }
            self.currentTitle = query
            self.fetchResults(reset: true)
        }
    }

    @objc private func filterChipTapped(_ sender: UIButton) {
        guard let type = FilterType(rawValue: sender.tag) else { return }
        showFilterPicker(for: type, sourceButton: sender)
    }

    private func showFilterPicker(for type: FilterType, sourceButton: UIButton) {
        let alert = UIAlertController(title: type.label, message: nil, preferredStyle: .actionSheet)

        // "Any" clears the filter
        alert.addAction(UIAlertAction(title: "Any", style: .default) { [weak self] _ in
            self?.clearFilter(type: type)
            self?.fetchResults(reset: true)
        })

        let currentAPIValue: String? = {
            switch type {
            case .genre:  return selectedGenre
            case .year:   return selectedYear.map { "\($0)" }
            case .season: return selectedSeason
            case .format: return selectedFormat
            case .status: return selectedStatus
            case .sort:   return selectedSort == "TRENDING_DESC" ? nil : selectedSort
            }
        }()

        for option in type.options {
            let isSelected = option.apiValue == currentAPIValue
            let title = isSelected ? "✓ \(option.displayName)" : option.displayName
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.setFilter(type: type, option: option)
                self.updateBoltTint()
                self.fetchResults(reset: true)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = sourceButton
            popover.sourceRect = sourceButton.bounds
        }
        present(alert, animated: true)
    }

    private func setFilter(type: FilterType, option: FilterOption) {
        switch type {
        case .genre:  selectedGenre  = option.apiValue
        case .year:   selectedYear   = Int(option.apiValue)
        case .season: selectedSeason = option.apiValue
        case .format: selectedFormat = option.apiValue
        case .status: selectedStatus = option.apiValue
        case .sort:   selectedSort   = option.apiValue
        }
        // Register in activeFilterLabels
        let key = type.label
        activeFilterLabels[key] = (type: type, apiValue: option.apiValue)
        // Remove sort from active chips (Hayase only shows clear-able filters,
        // sort is always active)
        if type == .sort {
            activeFilterLabels.removeValue(forKey: key)
        }
        rebuildActiveChips()
    }

    private func clearFilter(type: FilterType) {
        switch type {
        case .genre:  selectedGenre  = nil
        case .year:   selectedYear   = nil
        case .season: selectedSeason = nil
        case .format: selectedFormat = nil
        case .status: selectedStatus = nil
        case .sort:   selectedSort   = "TRENDING_DESC"
        }
        activeFilterLabels.removeValue(forKey: type.label)
        rebuildActiveChips()
        updateBoltTint()
    }

    private func updateBoltTint() {
        let hasActiveFilter = selectedGenre != nil || selectedYear != nil ||
            selectedSeason != nil || selectedFormat != nil || selectedStatus != nil ||
            (selectedSort != "TRENDING_DESC")
        boltButton.tintColor = (filterRowVisible || hasActiveFilter) ? Self.activeBlue : Self.mutedFg
    }

    private func rebuildActiveChips() {
        // Clear existing chips
        activeChipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (label, info) in activeFilterLabels {
            let chip = makeActiveChip(label: label, type: info.type)
            activeChipsStack.addArrangedSubview(chip)
        }

        let hasChips = !activeFilterLabels.isEmpty
        UIView.animate(withDuration: 0.2) {
            self.activeChipsRowHeightConstraint.constant = hasChips ? Self.activeChipsRowHeight : 0
            self.headerView.layoutIfNeeded()
            self.view.layoutIfNeeded()
        }
    }

    private func makeActiveChip(label: String, type: FilterType) -> UIView {
        // Matches Hayase badgeVariants() default: bg-primary text-primary-foreground rounded-full
        let container = UIView()
        container.backgroundColor = Self.chipBg
        container.layer.cornerRadius = 12
        container.layer.masksToBounds = true

        let titleLabel = UILabel()
        titleLabel.text = label
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = Self.chipFg

        let xButton = UIButton(type: .system)
        xButton.setImage(
            UIImage(systemName: "xmark")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)),
            for: .normal)
        xButton.tintColor = Self.chipFg.withAlphaComponent(0.7)
        xButton.tag = type.rawValue
        xButton.addTarget(self, action: #selector(removeChip(_:)), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, xButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
        ])

        return container
    }

    @objc private func removeChip(_ sender: UIButton) {
        guard let type = FilterType(rawValue: sender.tag) else { return }
        clearFilter(type: type)
        fetchResults(reset: true)
    }

    // MARK: - Collection view
    // 2-col grid matching grid-cols-[repeat(auto-fill,minmax(184px,max-content))]
    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = Self.bgBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(AnimeCollectionViewCell.self,
                                forCellWithReuseIdentifier: AnimeCollectionViewCell.reuseID)
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
        // 2 columns; each item 152pt wide (w-[9.5rem]) + 16pt padding = 184pt cell width
        // Matches minmax(184px, max-content) auto-fill which gives 2 cols on 375-430pt iPhones
        let cols: CGFloat = 2
        let hPad: CGFloat = 16   // section leading
        let gap:  CGFloat = 16   // spacing between columns
        let screenW = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let itemWidth  = floor((screenW - hPad * 2 - gap * (cols - 1)) / cols)
        let itemHeight = floor(itemWidth * 290.0 / 152.0)

        let item = NSCollectionLayoutItem(
            layoutSize: .init(widthDimension: .absolute(itemWidth),
                              heightDimension: .absolute(itemHeight)))

        // iOS 14-compatible: pass subitems array instead of count: (count: requires iOS 16)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1),
                              heightDimension: .absolute(itemHeight + 8)),
            subitems: Array(repeating: item, count: Int(cols)))
        group.interItemSpacing = .fixed(gap)

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 12, leading: hPad, bottom: 16, trailing: hPad)
        section.interGroupSpacing = 0
        return UICollectionViewCompositionalLayout(section: section)
    }

    // MARK: - Overlays (loading + empty state)

    private func setupOverlays() {
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = .white
        view.addSubview(loadingIndicator)

        emptyLabel = UILabel()
        emptyLabel.textColor = Self.mutedFg
        emptyLabel.font = .systemFont(ofSize: 16)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
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
        if reset { currentPage = 1; hasNextPage = true }
        guard !isFetching, hasNextPage else { return }
        isFetching = true
        if reset { loadingIndicator.startAnimating(); emptyLabel.isHidden = true }

        AnimeService.sharedAnimeService.searchAnimeItems(
            title: currentTitle.isEmpty ? nil : currentTitle,
            genre: selectedGenre,
            format: selectedFormat,
            status: selectedStatus,
            sort: selectedSort,
            seasonYear: selectedYear,
            season: selectedSeason,
            page: currentPage
        ) { [weak self] items, hasNext in
            guard let self = self else { return }
            if reset { self.animeResults = items } else { self.animeResults.append(contentsOf: items) }
            self.hasNextPage = hasNext
            self.currentPage += 1
            self.isFetching = false
            self.loadingIndicator.stopAnimating()
            self.collectionView.reloadData()
            self.emptyLabel.isHidden = !self.animeResults.isEmpty
            if self.animeResults.isEmpty {
                self.emptyLabel.text = self.currentTitle.isEmpty ? "No results found"
                    : "No results for \"\(self.currentTitle)\""
            }
        }
    }
}

// MARK: - UICollectionViewDataSource

extension SearchViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int { animeResults.count }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: AnimeCollectionViewCell.reuseID,
            for: indexPath) as? AnimeCollectionViewCell else { return UICollectionViewCell() }
        cell.configure(with: animeResults[indexPath.item])
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension SearchViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        let item = animeResults[indexPath.item]
        guard let vc = storyboard?.instantiateViewController(withIdentifier: "AnimeDetailVC")
                as? AnimeDetailViewController else { return }
        vc.animeItem = item
        navigationController?.pushViewController(vc, animated: true)
    }

    // Infinite scroll: matches use:infiniteScroll in Hayase (+page.svelte)
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY  = scrollView.contentOffset.y
        let total    = scrollView.contentSize.height
        let frame    = scrollView.frame.height
        guard total > frame, offsetY > total - frame - 400 else { return }
        fetchResults(reset: false)
    }
}
