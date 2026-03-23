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

    /// Hayase: genres, formats and status ComboBoxes have multiple={true}
    var isMultiSelect: Bool {
        switch self {
        case .genre, .format, .status: return true
        default: return false
        }
    }

    /// Options exactly from values.ts
    var options: [FilterOption] {
        switch self {
        case .genre:
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
            return [
                .init(displayName: "TV Show",  apiValue: "TV"),
                .init(displayName: "Movie",    apiValue: "MOVIE"),
                .init(displayName: "TV Short", apiValue: "TV_SHORT"),
                .init(displayName: "OVA",      apiValue: "OVA"),
                .init(displayName: "ONA",      apiValue: "ONA"),
            ]
        case .status:
            return [
                .init(displayName: "Airing",        apiValue: "RELEASING"),
                .init(displayName: "Finished",      apiValue: "FINISHED"),
                .init(displayName: "Not Yet Aired", apiValue: "NOT_YET_RELEASED"),
                .init(displayName: "Cancelled",     apiValue: "CANCELLED"),
            ]
        case .sort:
            // Exact order from values.ts
            return [
                .init(displayName: "Name",             apiValue: "TITLE_ROMAJI_DESC"),
                .init(displayName: "Release Date",     apiValue: "START_DATE_DESC"),
                .init(displayName: "Score",            apiValue: "SCORE_DESC"),
                .init(displayName: "Popularity",       apiValue: "POPULARITY_DESC"),
                .init(displayName: "Trending",         apiValue: "TRENDING_DESC"),
                .init(displayName: "Updated Date",     apiValue: "UPDATED_AT_DESC"),
                .init(displayName: "Name Asc",         apiValue: "TITLE_ROMAJI"),
                .init(displayName: "Release Date Asc", apiValue: "START_DATE"),
                .init(displayName: "Score Asc",        apiValue: "SCORE"),
                .init(displayName: "Popularity Asc",   apiValue: "POPULARITY"),
                .init(displayName: "Trending Asc",     apiValue: "TRENDING"),
                .init(displayName: "Updated Date Asc", apiValue: "UPDATED_AT"),
            ]
        }
    }
}

// MARK: - SearchViewController

class SearchViewController: UIViewController {

    // MARK: - Hayase color constants
    private static let bgBlack      = UIColor.black
    private static let bgBackground = UIColor(red: 0.039, green: 0.039, blue: 0.059, alpha: 1)
    private static let mutedFg      = UIColor(red: 0.631, green: 0.631, blue: 0.667, alpha: 1)
    private static let activeBlue   = UIColor(red: 0.369, green: 0.647, blue: 0.953, alpha: 1)
    private static let chipBg       = UIColor(red: 0.98,  green: 0.98,  blue: 0.98,  alpha: 1)
    private static let chipFg       = UIColor(red: 0.059, green: 0.059, blue: 0.078, alpha: 1)

    // MARK: - Filter state
    // Hayase: genres / formats / status multi-select; year / season / sort single-select
    private var selectedGenres:   [String] = []
    private var selectedYear:     String?  = nil
    private var selectedSeason:   String?  = nil
    private var selectedFormats:  [String] = []
    private var selectedStatuses: [String] = []
    private var selectedSort:     String?  = "TRENDING_DESC"

    // Active chip entries (sort is never shown as a chip)
    private var activeChipEntries: [(label: String, type: FilterType, apiValue: String)] = []

    // MARK: - Results state
    private var animeResults: [AnimeItem] = []
    private var currentPage  = 1
    private var hasNextPage  = true
    private var isFetching   = false
    private var currentTitle = ""
    private var debounceTimer: Timer?

    // MARK: - Views
    private var headerView: UIView!

    // Title row: [leftStack | rightButtons]
    private var titleRowStack: UIStackView!
    private var leftStack:     UIStackView!  // vertical: title label + search input
    private var titleLabel:    UILabel!
    private var searchInputRow: UIView!
    private var searchField:   UITextField!
    private var rightButtons:  UIStackView!  // horizontal: camera + bolt
    private var cameraButton:  UIButton!
    private var boltButton:    UIButton!

    // Filter row (horizontal scroll, hidden by default)
    private var filterRowVisible = false
    private var filterRow:   UIScrollView!
    private var filterStack: UIStackView!
    private var filterRowHeightConstraint: NSLayoutConstraint!
    private var filterPickerButtons: [UIButton] = []

    // Active chips (wrapping frame layout, min-h-9)
    private var chipsContainer:     UIView!
    private var chipsHeightConstraint: NSLayoutConstraint!

    private var collectionView:    UICollectionView!
    private var loadingIndicator:  UIActivityIndicatorView!
    private var emptyLabel:        UILabel!

    // min-w-44 = 176pt; panel height = label(20)+gap(4)+picker(36)+padding(24) = 84pt
    private static let filterItemWidth:   CGFloat = 176
    private static let filterPanelHeight: CGFloat = 84

    // Pending prefill from Home page
    private var pendingPrefill: (genre: String?, sort: String?)?

    // MARK: - Init

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
        if let pending = pendingPrefill {
            pendingPrefill = nil
            applyPrefill(genre: pending.genre, sort: pending.sort)
        }
    }

    // MARK: - Prefill from Home

    func prefillSearch(genre: String?, sort: String?) {
        if isViewLoaded { applyPrefill(genre: genre, sort: sort) }
        else { pendingPrefill = (genre: genre, sort: sort) }
    }

    private func applyPrefill(genre: String?, sort: String?) {
        selectedGenres = []; selectedYear = nil; selectedSeason = nil
        selectedFormats = []; selectedStatuses = []
        selectedSort = "TRENDING_DESC"; activeChipEntries = []
        if let genre = genre {
            selectedGenres = [genre]
            let name = FilterType.genre.options.first { $0.apiValue == genre }?.displayName ?? genre
            activeChipEntries.append((label: name, type: .genre, apiValue: genre))
        }
        if let sort = sort, sort != "TRENDING_DESC" { selectedSort = sort }
        refreshFilterPickers(); rebuildActiveChips(); updateBoltTint()
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
        headerView.backgroundColor = Self.bgBlack
        view.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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
        titleLabel.font = .boldSystemFont(ofSize: 20) // text-xl font-bold
        titleLabel.textColor = .white

        searchInputRow = UIView()
        searchInputRow.translatesAutoresizingMaskIntoConstraints = false

        searchField = UITextField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.backgroundColor = Self.bgBackground
        searchField.layer.cornerRadius = 8
        searchField.layer.masksToBounds = true
        searchField.borderStyle = .none
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Any",
            attributes: [.foregroundColor: Self.mutedFg.withAlphaComponent(0.5)])
        searchField.textColor = .white
        searchField.font = .systemFont(ofSize: 15)
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

        // Camera button (FileImage) — border-0 outline icon button
        cameraButton = UIButton(type: .system)
        cameraButton.setImage(
            UIImage(systemName: "photo.on.rectangle.angled")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)),
            for: .normal)
        cameraButton.tintColor = Self.mutedFg
        cameraButton.translatesAutoresizingMaskIntoConstraints = false
        cameraButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        cameraButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        cameraButton.addTarget(self, action: #selector(cameraTapped), for: .touchUpInside)

        // Bolt toggle — md:hidden in Hayase (only on mobile)
        boltButton = UIButton(type: .system)
        boltButton.setImage(
            UIImage(systemName: "slider.horizontal.3")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)),
            for: .normal)
        boltButton.tintColor = Self.mutedFg
        boltButton.translatesAutoresizingMaskIntoConstraints = false
        boltButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        boltButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
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
        NSLayoutConstraint.activate([
            titleRowStack.topAnchor.constraint(equalTo: headerView.topAnchor),
            titleRowStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            titleRowStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
        ])
    }

    // MARK: - Filter Row
    // Hayase: flex overflow-y-auto w-full (horizontal scroll on mobile), use:dragScroll
    // Each item: min-w-44 flex-1 p-2 with text-xl font-bold label + combobox picker
    private func setupFilterRow() {
        filterRow = UIScrollView()
        filterRow.translatesAutoresizingMaskIntoConstraints = false
        filterRow.showsHorizontalScrollIndicator = false
        filterRow.alwaysBounceHorizontal = true
        filterRow.contentInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        headerView.addSubview(filterRow)

        filterStack = UIStackView()
        filterStack.translatesAutoresizingMaskIntoConstraints = false
        filterStack.axis = .horizontal; filterStack.spacing = 0; filterStack.alignment = .top
        filterRow.addSubview(filterStack)
        NSLayoutConstraint.activate([
            filterStack.topAnchor.constraint(equalTo: filterRow.topAnchor),
            filterStack.bottomAnchor.constraint(equalTo: filterRow.bottomAnchor),
            filterStack.leadingAnchor.constraint(equalTo: filterRow.leadingAnchor),
            filterStack.trailingAnchor.constraint(equalTo: filterRow.trailingAnchor),
        ])

        filterRowHeightConstraint = filterRow.heightAnchor.constraint(equalToConstant: 0)
        filterRowHeightConstraint.isActive = true
        NSLayoutConstraint.activate([
            filterRow.topAnchor.constraint(equalTo: titleRowStack.bottomAnchor),
            filterRow.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            filterRow.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
        ])

        filterPickerButtons = []
        for type in FilterType.allCases {
            let (item, picker) = makeFilterItem(for: type)
            filterStack.addArrangedSubview(item)
            filterPickerButtons.append(picker)
        }
    }

    /// One filter item: bold label (text-xl) + combobox-style picker button, min-w-44
    private func makeFilterItem(for type: FilterType) -> (UIView, UIButton) {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: Self.filterItemWidth).isActive = true

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = type.label
        label.font = .boldSystemFont(ofSize: 20) // text-xl font-bold mb-1 ml-1
        label.textColor = .white
        container.addSubview(label)

        let picker = UIButton(type: .system)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.backgroundColor = Self.bgBackground
        picker.layer.cornerRadius = 8; picker.layer.masksToBounds = true
        picker.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        picker.setTitleColor(.white, for: .normal)
        picker.titleLabel?.font = .systemFont(ofSize: 14)
        picker.titleLabel?.lineBreakMode = .byTruncatingTail
        picker.contentHorizontalAlignment = .left
        picker.setTitle(pickerTitle(for: type), for: .normal)
        picker.tag = type.rawValue
        picker.addTarget(self, action: #selector(filterPickerTapped(_:)), for: .touchUpInside)
        container.addSubview(picker)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            picker.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            picker.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            picker.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            picker.heightAnchor.constraint(equalToConstant: 36),
            picker.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        return (container, picker)
    }

    // MARK: - Chips Row
    // Hayase: flex flex-row flex-wrap mt-2 min-h-9 pb-1 px-1
    private func setupChipsRow() {
        chipsContainer = UIView()
        chipsContainer.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(chipsContainer)
        chipsHeightConstraint = chipsContainer.heightAnchor.constraint(equalToConstant: 36)
        chipsHeightConstraint.isActive = true
        NSLayoutConstraint.activate([
            chipsContainer.topAnchor.constraint(equalTo: filterRow.bottomAnchor, constant: 8),
            chipsContainer.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 4),
            chipsContainer.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -4),
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
        UIView.animate(withDuration: 0.25) {
            self.filterRowHeightConstraint.constant = self.filterRowVisible ? Self.filterPanelHeight : 0
            self.boltButton.tintColor = self.filterRowVisible ? Self.activeBlue : Self.mutedFg
            self.headerView.layoutIfNeeded(); self.view.layoutIfNeeded()
        }
    }

    @objc private func searchFieldChanged(_ field: UITextField) {
        let query = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self = self, query != self.currentTitle else { return }
            self.currentTitle = query; self.fetchResults(reset: true)
        }
    }

    @objc private func filterPickerTapped(_ sender: UIButton) {
        guard let type = FilterType(rawValue: sender.tag) else { return }
        showFilterPicker(for: type, sourceButton: sender)
    }

    // MARK: - Filter picker (action sheet)

    private func showFilterPicker(for type: FilterType, sourceButton: UIButton) {
        let alert = UIAlertController(title: type.label, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Any", style: .default) { [weak self] _ in
            self?.clearFilter(type: type); self?.fetchResults(reset: true)
        })
        for option in type.options {
            let selected = isOptionSelected(option: option, for: type)
            let title = selected ? "✓ \(option.displayName)" : option.displayName
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.toggleOption(option: option, for: type)
                self.updateBoltTint(); self.fetchResults(reset: true)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = sourceButton; pop.sourceRect = sourceButton.bounds
        }
        present(alert, animated: true)
    }

    private func isOptionSelected(option: FilterOption, for type: FilterType) -> Bool {
        switch type {
        case .genre:  return selectedGenres.contains(option.apiValue)
        case .year:   return selectedYear == option.apiValue
        case .season: return selectedSeason == option.apiValue
        case .format: return selectedFormats.contains(option.apiValue)
        case .status: return selectedStatuses.contains(option.apiValue)
        case .sort:   return selectedSort == option.apiValue
        }
    }

    private func toggleOption(option: FilterOption, for type: FilterType) {
        switch type {
        case .genre:
            if selectedGenres.contains(option.apiValue) {
                selectedGenres.removeAll { $0 == option.apiValue }
                activeChipEntries.removeAll { $0.type == .genre && $0.apiValue == option.apiValue }
            } else {
                selectedGenres.append(option.apiValue)
                activeChipEntries.append((label: option.displayName, type: .genre, apiValue: option.apiValue))
            }
        case .year:
            let same = selectedYear == option.apiValue
            activeChipEntries.removeAll { $0.type == .year }
            selectedYear = same ? nil : option.apiValue
            if !same { activeChipEntries.append((label: option.displayName, type: .year, apiValue: option.apiValue)) }
        case .season:
            let same = selectedSeason == option.apiValue
            activeChipEntries.removeAll { $0.type == .season }
            selectedSeason = same ? nil : option.apiValue
            if !same { activeChipEntries.append((label: option.displayName, type: .season, apiValue: option.apiValue)) }
        case .format:
            if selectedFormats.contains(option.apiValue) {
                selectedFormats.removeAll { $0 == option.apiValue }
                activeChipEntries.removeAll { $0.type == .format && $0.apiValue == option.apiValue }
            } else {
                selectedFormats.append(option.apiValue)
                activeChipEntries.append((label: option.displayName, type: .format, apiValue: option.apiValue))
            }
        case .status:
            if selectedStatuses.contains(option.apiValue) {
                selectedStatuses.removeAll { $0 == option.apiValue }
                activeChipEntries.removeAll { $0.type == .status && $0.apiValue == option.apiValue }
            } else {
                selectedStatuses.append(option.apiValue)
                activeChipEntries.append((label: option.displayName, type: .status, apiValue: option.apiValue))
            }
        case .sort:
            selectedSort = (selectedSort == option.apiValue) ? "TRENDING_DESC" : option.apiValue
        }
        refreshFilterPickers(); rebuildActiveChips()
    }

    private func clearFilter(type: FilterType) {
        switch type {
        case .genre:   selectedGenres = [];   activeChipEntries.removeAll { $0.type == .genre }
        case .year:    selectedYear = nil;    activeChipEntries.removeAll { $0.type == .year }
        case .season:  selectedSeason = nil;  activeChipEntries.removeAll { $0.type == .season }
        case .format:  selectedFormats = [];  activeChipEntries.removeAll { $0.type == .format }
        case .status:  selectedStatuses = []; activeChipEntries.removeAll { $0.type == .status }
        case .sort:    selectedSort = "TRENDING_DESC"
        }
        refreshFilterPickers(); rebuildActiveChips(); updateBoltTint()
    }

    private func updateBoltTint() {
        let hasFilter = !selectedGenres.isEmpty || selectedYear != nil || selectedSeason != nil
            || !selectedFormats.isEmpty || !selectedStatuses.isEmpty
            || (selectedSort != "TRENDING_DESC" && selectedSort != nil)
        boltButton.tintColor = (filterRowVisible || hasFilter) ? Self.activeBlue : Self.mutedFg
    }

    // MARK: - Filter picker titles

    private func pickerTitle(for type: FilterType) -> String {
        switch type {
        case .genre:
            return selectedGenres.isEmpty ? "Any" : selectedGenres.map { displayLabel($0, in: .genre) }.joined(separator: ", ")
        case .year:
            return selectedYear ?? "Any"
        case .season:
            return selectedSeason.map { displayLabel($0, in: .season) } ?? "Any"
        case .format:
            return selectedFormats.isEmpty ? "Any" : selectedFormats.map { displayLabel($0, in: .format) }.joined(separator: ", ")
        case .status:
            return selectedStatuses.isEmpty ? "Any" : selectedStatuses.map { displayLabel($0, in: .status) }.joined(separator: ", ")
        case .sort:
            return selectedSort.map { displayLabel($0, in: .sort) } ?? "Accuracy"
        }
    }

    private func displayLabel(_ api: String, in type: FilterType) -> String {
        type.options.first { $0.apiValue == api }?.displayName ?? api
    }

    private func refreshFilterPickers() {
        for (i, type) in FilterType.allCases.enumerated() {
            guard i < filterPickerButtons.count else { continue }
            filterPickerButtons[i].setTitle(pickerTitle(for: type), for: .normal)
        }
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
        let availableW = max(UIScreen.main.bounds.width - 8, 100)
        let hSpacing: CGFloat = 12; let vSpacing: CGFloat = 8
        var x: CGFloat = 0; var y: CGFloat = 4; var rowH: CGFloat = 0

        for chip in chips {
            chip.setNeedsLayout(); chip.layoutIfNeeded()
            let sz = chip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let cw = ceil(sz.width); let ch = ceil(sz.height)
            if x + cw > availableW && x > 0 { y += rowH + vSpacing; x = 0; rowH = 0 }
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

    private func makeActiveChip(label: String, type: FilterType, apiValue: String) -> UIView {
        let container = UIView()
        container.backgroundColor = Self.chipBg
        container.layer.cornerRadius = 12; container.layer.masksToBounds = true

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
        xButton.accessibilityIdentifier = "\(type.rawValue):\(apiValue)"
        xButton.addTarget(self, action: #selector(removeChipTapped(_:)), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, xButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal; stack.spacing = 4; stack.alignment = .center
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
        ])
        return container
    }

    @objc private func removeChipTapped(_ sender: UIButton) {
        guard let id = sender.accessibilityIdentifier, let colon = id.range(of: ":") else { return }
        let typeRaw  = Int(id[id.startIndex..<colon.lowerBound]) ?? -1
        let apiValue = String(id[colon.upperBound...])
        guard let type = FilterType(rawValue: typeRaw) else { return }
        switch type {
        case .genre:   selectedGenres.removeAll { $0 == apiValue };   activeChipEntries.removeAll { $0.type == .genre  && $0.apiValue == apiValue }
        case .year:    selectedYear = nil;   activeChipEntries.removeAll { $0.type == .year }
        case .season:  selectedSeason = nil; activeChipEntries.removeAll { $0.type == .season }
        case .format:  selectedFormats.removeAll { $0 == apiValue };  activeChipEntries.removeAll { $0.type == .format && $0.apiValue == apiValue }
        case .status:  selectedStatuses.removeAll { $0 == apiValue }; activeChipEntries.removeAll { $0.type == .status && $0.apiValue == apiValue }
        case .sort:    selectedSort = "TRENDING_DESC"
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
        let cols: CGFloat = 2; let hPad: CGFloat = 16; let gap: CGFloat = 16
        let screenW    = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let itemWidth  = floor((screenW - hPad * 2 - gap * (cols - 1)) / cols)
        let itemHeight = floor(itemWidth * 290.0 / 152.0)
        let item = NSCollectionLayoutItem(
            layoutSize: .init(widthDimension: .absolute(itemWidth), heightDimension: .absolute(itemHeight)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(itemHeight + 8)),
            subitems: Array(repeating: item, count: Int(cols)))
        group.interItemSpacing = .fixed(gap)
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 12, leading: hPad, bottom: 16, trailing: hPad)
        section.interGroupSpacing = 0
        return UICollectionViewCompositionalLayout(section: section)
    }

    // MARK: - Overlays

    private func setupOverlays() {
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true; loadingIndicator.color = .white
        view.addSubview(loadingIndicator)

        emptyLabel = UILabel()
        emptyLabel.textColor = Self.mutedFg; emptyLabel.font = .systemFont(ofSize: 16)
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
        if reset { currentPage = 1; hasNextPage = true }
        guard !isFetching, hasNextPage else { return }
        isFetching = true
        if reset { loadingIndicator.startAnimating(); emptyLabel.isHidden = true }

        AnimeService.sharedAnimeService.searchAnimeItems(
            title: currentTitle.isEmpty ? nil : currentTitle,
            genres: selectedGenres,
            formats: selectedFormats,
            statuses: selectedStatuses,
            sort: selectedSort ?? "SEARCH_MATCH",
            seasonYear: selectedYear.flatMap { Int($0) },
            season: selectedSeason,
            page: currentPage
        ) { [weak self] items, hasNext in
            guard let self = self else { return }
            if reset { self.animeResults = items } else { self.animeResults.append(contentsOf: items) }
            self.hasNextPage = hasNext; self.currentPage += 1; self.isFetching = false
            self.loadingIndicator.stopAnimating(); self.collectionView.reloadData()
            self.emptyLabel.isHidden = !self.animeResults.isEmpty
            if self.animeResults.isEmpty {
                self.emptyLabel.text = self.currentTitle.isEmpty
                    ? "No results found" : "No results for \"\(self.currentTitle)\""
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

    // Infinite scroll — matches use:infiniteScroll in Hayase
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let total = scrollView.contentSize.height; let frame = scrollView.frame.height
        guard total > frame, offsetY > total - frame - 400 else { return }
        fetchResults(reset: false)
    }
}

// MARK: - PHPickerViewControllerDelegate (iOS 14+)

@available(iOS 14, *)
extension SearchViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        // Reverse image search (trace.moe) would be integrated here
    }
}

// MARK: - UIImagePickerControllerDelegate (iOS 13)

extension SearchViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        // Reverse image search (trace.moe) would be integrated here
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
