//
//  AnimeDetailViewController.swift
//  Hayase
//

import UIKit
import SafariServices
import ObjectiveC

// MARK: - AnimeDetailViewController

class AnimeDetailViewController: UIViewController {

    var animeEntity: Animes?
    var animeItem: AnimeItem?

    private var tableView: UITableView!
    private var headerView: AnimeInfoHeaderView!
    private var isFavorite = false
    private var isOnList = false
    private var episodes: [AniZipEpisode] = []
    private var anilistProgress: Int = 0
    private var currentListStatus: String?
    private var currentAnimeAccent: UIColor = .white
    private var relations: [AnimeRelation] = []
    private var staff: [AnimeStaffMember] = []
    private var scoreDistribution: [AnimeScorePoint] = []
    private var statusDistribution: [AnimeStatusCount] = []

    private let episodesPerPage = 16
    private var currentEpisodePage: Int = 1
    private var paginatedEpisodes: [AniZipEpisode] {
        let start = (currentEpisodePage - 1) * episodesPerPage
        let end = min(start + episodesPerPage, episodes.count)
        guard start < episodes.count else { return [] }
        return Array(episodes[start..<end])
    }
    private var totalEpisodePages: Int {
        max(1, Int(ceil(Double(episodes.count) / Double(episodesPerPage))))
    }
    private lazy var paginationBar: PaginationBarView = {
        let bar = PaginationBarView()
        bar.onPageChange = { [weak self] page in
            self?.setEpisodePage(page)
        }
        return bar
    }()

    private var threads: [AniListThread] = []
    private var themes: [AnimeThemesTheme] = []
    private var threadsLoading = false
    private var themesLoading = false

    private var activeSection: Section = .episodes

    private lazy var tabBar: HTabBar = {
        let bar = HTabBar(titles: ["Episodes", "Relations", "Threads", "Themes"])
        bar.onChange = { [weak self] index in
            self?.tabChanged(to: index)
        }
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private var tabBarCenterXConstraint: NSLayoutConstraint?
    private var tabBarLeadingConstraint: NSLayoutConstraint?
    private var tabBarMaxWidthConstraint: NSLayoutConstraint?
    private var tabBarWidthFillConstraint: NSLayoutConstraint?
    private var tabBarTrailingConstraint: NSLayoutConstraint?

    private lazy var tabBarContainer: UIView = {
        let v = UIView()
        v.backgroundColor = hayasePageBackground
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(tabBar)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: v.topAnchor, constant: 24),
            tabBar.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8),
        ])

        tabBarCenterXConstraint = tabBar.centerXAnchor.constraint(equalTo: v.centerXAnchor)
        tabBarMaxWidthConstraint = tabBar.widthAnchor.constraint(lessThanOrEqualToConstant: 288)
        tabBarWidthFillConstraint = tabBar.widthAnchor.constraint(equalTo: v.widthAnchor, constant: -32)
        tabBarWidthFillConstraint?.priority = .defaultHigh

        tabBarLeadingConstraint = tabBar.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 56)
        tabBarTrailingConstraint = tabBar.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -56)

        return v
    }()

    private func applyTabBarLayoutForSizeClass() {
        let isRegular = traitCollection.horizontalSizeClass == .regular

        tabBar.isVertical = !isRegular

        if isRegular {
            tabBarCenterXConstraint?.isActive = false
            tabBarMaxWidthConstraint?.isActive = false
            tabBarWidthFillConstraint?.isActive = false
            tabBarLeadingConstraint?.isActive = true
            tabBarTrailingConstraint?.isActive = true
        } else {
            tabBarLeadingConstraint?.isActive = false
            tabBarTrailingConstraint?.isActive = false
            tabBarCenterXConstraint?.isActive = true
            tabBarMaxWidthConstraint?.isActive = true
            tabBarWidthFillConstraint?.isActive = true
        }
    }

    private enum Section: Int, CaseIterable {
        case header = 0, episodes, episodePagination, relations, threads, themes
    }

    // MARK: - Search navigation helpers

    private func navigateToSearchTab(genre: String) {
        let tbc = tabBarController
        guard let tbc,
              let controllers = tbc.viewControllers,
              controllers.count > 1,
              let navController = controllers[1] as? UINavigationController,
              let searchVC = navController.viewControllers.first as? SearchViewController else {
            tbc?.selectedIndex = 1
            return
        }
        let nav = navigationController
        searchVC.prefillSearchExtended(genre: genre)
        nav?.popToRootViewController(animated: false)
        tbc.selectedIndex = 1
    }

    private func navigateToSearchTab(filterType: String, value: String) {
        let tbc = tabBarController
        guard let tbc,
              let controllers = tbc.viewControllers,
              controllers.count > 1,
              let navController = controllers[1] as? UINavigationController,
              let searchVC = navController.viewControllers.first as? SearchViewController else {
            tbc?.selectedIndex = 1
            return
        }
        let nav = navigationController
        switch filterType {
        case "format":
            searchVC.prefillSearchExtended(format: value)
        case "status":
            searchVC.prefillSearchExtended(status: value)
        case "season":
            let parts = value.components(separatedBy: " ")
            if parts.count == 2, let year = Int(parts[1]) {
                searchVC.prefillSearchExtended(season: parts[0].uppercased(), seasonYear: year)
            } else {
                searchVC.prefillSearchExtended(season: value.uppercased())
            }
        case "score":
            searchVC.prefillSearchExtended(sort: value)
        default:
            break
        }
        nav?.popToRootViewController(animated: false)
        tbc.selectedIndex = 1
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = nil
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = hayasePageBackground

        setupTableView()
        setupHeaderView()
        applyTabBarLayoutForSizeClass()
        fetchEpisodes()
        fetchRelationsAndCharacters()
        fetchAniListProgress()
        refreshButtonStates()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let nb = navigationController?.navigationBar
        nb?.setBackgroundImage(UIImage(), for: .default)
        nb?.shadowImage = UIImage()
        nb?.tintColor = .white

        fetchAniListProgress()
        refreshButtonStates()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let nb = navigationController?.navigationBar
        nb?.setBackgroundImage(nil, for: .default)
        nb?.shadowImage = nil
        nb?.tintColor = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            applyTabBarLayoutForSizeClass()
            tableView.reloadData()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.tableView.reloadData()
        })
    }

    // MARK: - iPad two-column grid helpers

    private static let gridOuterPad: CGFloat = 56
    private static let gridMinColWidth: CGFloat = 500
    private static let episodeGap: CGFloat = 16
    private static let threadGap: CGFloat = 40

    private var episodeColumnCount: Int {
        let gridWidth = tableView.frame.width - 2 * Self.gridOuterPad
        if traitCollection.horizontalSizeClass == .regular
            && gridWidth >= 2 * Self.gridMinColWidth + Self.episodeGap {
            return 2
        }
        return 1
    }

    private var threadColumnCount: Int {
        let gridWidth = tableView.frame.width - 2 * Self.gridOuterPad
        if traitCollection.horizontalSizeClass == .regular
            && gridWidth >= 2 * Self.gridMinColWidth + Self.threadGap {
            return 2
        }
        return 1
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(EpisodeCell.self, forCellReuseIdentifier: EpisodeCell.reuseID)
        tableView.register(EpisodePairCell.self, forCellReuseIdentifier: EpisodePairCell.reuseID)
        tableView.register(ThreadPairCell.self, forCellReuseIdentifier: ThreadPairCell.reuseID)
        tableView.register(HorizontalCardsCell.self, forCellReuseIdentifier: HorizontalCardsCell.relationsReuseID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HeaderCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PaginationCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.separatorStyle = .none
        tableView.backgroundColor = hayasePageBackground
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.contentInsetAdjustmentBehavior = .never
        let tabBarH = tabBarController?.tabBar.frame.height ?? 83
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: tabBarH, right: 0)
        tableView.scrollIndicatorInsets = tableView.contentInset
        tableView.clipsToBounds = false
        view.clipsToBounds = true
        view.addSubview(tableView)
    }

    private func setupHeaderView() {
        headerView = AnimeInfoHeaderView()
        if let item = animeItem {
            headerView.configure(with: item)
            if let accent = ExtensionSearchViewController.uiColor(fromHex: item.coverColor) {
                tabBar.accentColor = accent
                currentAnimeAccent = accent
            }
        } else {
            headerView.configure(with: animeEntity)
        }
        headerView.onFavorite = { [weak self] in
            guard let self, let item = self.animeItem else { return }
            AniListTracking.shared.toggleFavourite(mediaID: item.id) { [weak self] _ in
                self?.refreshButtonStates()
            }
        }

        headerView.onBookmark = { [weak self] in
            guard let self, let item = self.animeItem else { return }
            if self.isOnList {
                AniListTracking.shared.fetchMediaWithEntry(anilistID: item.id) { [weak self] entry, _, _, _, _ in
                    if let listID = entry?.listID {
                        AniListTracking.shared.deleteEntry(listID: listID) { [weak self] _ in
                            self?.refreshButtonStates()
                        }
                    }
                }
            } else {
                AniListTracking.shared.entry(mediaID: item.id, status: "PLANNING") { [weak self] _ in
                    self?.refreshButtonStates()
                }
            }
        }

        headerView.onShare = { [weak self] in
            guard let self = self else { return }
            let title = self.animeItem?.titleEnglish ?? self.animeItem?.titleRomaji
                ?? self.animeEntity?.animeTitleEnglish ?? self.animeEntity?.animeTitleJapanese
                ?? "Anime"
            let id = self.animeItem?.id ?? self.animeEntity?.animeAnilistId?.intValue
            var items: [Any] = [title]
            if let id = id, let url = URL(string: "https://anilist.co/anime/\(id)") {
                items.append(url)
            }
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = self.view
            self.present(activity, animated: true)
        }
        headerView.onPlayTrailer = { [weak self] in
            guard let self = self,
                  let trailerID = self.animeItem?.trailerYouTubeID,
                  let url = URL(string: "https://www.youtube.com/watch?v=\(trailerID)") else { return }
            let safari = SFSafariViewController(url: url)
            self.present(safari, animated: true)
        }
        headerView.onWatch = { [weak self] in
            self?.openExtensionSearch(episode: 1)
        }
        headerView.onEntryEditor = { [weak self] in
            self?.showEntryEditor()
        }
        headerView.onOpenAniList = { [weak self] in
            guard let self = self else { return }
            let id = self.animeItem?.id ?? self.animeEntity?.animeAnilistId?.intValue
            guard let id, let url = URL(string: "https://anilist.co/anime/\(id)") else { return }
            let safari = SFSafariViewController(url: url)
            self.present(safari, animated: true)
        }
        headerView.onOpenMAL = { [weak self] in
            guard let self = self else { return }
            guard let malId = self.headerView?.malId,
                  let url = URL(string: "https://myanimelist.net/anime/\(malId)") else { return }
            let safari = SFSafariViewController(url: url)
            self.present(safari, animated: true)
        }

        headerView.onGenreTapped = { [weak self] genre in
            self?.navigateToSearchTab(genre: genre)
        }

        headerView.onBadgeTapped = { [weak self] filterType, value in
            self?.navigateToSearchTab(filterType: filterType, value: value)
        }
    }

    // MARK: - AniList Entry Editor

    private func showEntryEditor() {
        guard let item = animeItem else { return }

        AniListTracking.shared.fetchMediaWithEntry(anilistID: item.id) { [weak self] entry, _, _, _, _ in
            DispatchQueue.main.async {
                self?.presentEntryEditorSheet(mediaID: item.id, currentEntry: entry, totalEpisodes: item.episodes)
            }
        }
    }

    private func presentEntryEditorSheet(mediaID: Int, currentEntry: AnimeItem.MediaListEntry?, totalEpisodes: Int?) {
        let editorVC = EntryEditorViewController()
        editorVC.mediaID = mediaID
        editorVC.totalEpisodes = totalEpisodes
        editorVC.currentEntry = currentEntry
        editorVC.animeTitle = animeItem?.titleEnglish ?? animeItem?.titleRomaji ?? "Unknown"
        editorVC.coverURL = animeItem?.coverURL
        editorVC.bannerURL = animeItem?.bannerURL

        editorVC.onSave = { [weak self] in
            self?.fetchAniListProgress()
            self?.refreshButtonStates()
        }
        editorVC.onDelete = { [weak self] in
            self?.anilistProgress = 0
            self?.currentListStatus = nil
            self?.isOnList = false
            self?.tableView.reloadData()
            self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false, isOnList: false)
            self?.headerView?.updatePlayButtonTitle(listStatus: nil)
        }

        editorVC.modalPresentationStyle = .custom
        editorVC.transitioningDelegate = editorVC
        present(editorVC, animated: true)
    }

    // MARK: - Fetch episodes (AniZipService)

    private func isMovie(format: String?, titles: [String], synonyms: [String], duration: Int?, episodes: Int?) -> Bool {
        if format == "MOVIE" { return true }
        let allNames = titles + synonyms
        if allNames.contains(where: { $0.lowercased().contains("movie") }) { return true }
        return (duration ?? 0) > 80 && episodes == 1
    }

    private func isSingleEpisode(format: String?, titles: [String], synonyms: [String], duration: Int?, episodes: Int?) -> Bool {
        let movie = isMovie(format: format, titles: titles, synonyms: synonyms, duration: duration, episodes: episodes)
        return episodes == 1 || (movie && episodes == nil)
    }

    private func episodeByAirDate(
        alDate: Date?,
        filtered: [String: FilteredEpisode],
        episode: Int
    ) -> FilteredEpisode? {
        guard let alDate = alDate else {
            return filtered["\(episode)"]
        }
        let alMs = alDate.timeIntervalSince1970 * 1000

        var closest: [FilteredEpisode] = []
        var closestDist = Double.infinity
        for entry in filtered.values {
            guard let ms = entry.airdatems else { continue }
            let dist = abs(ms - alMs)
            if dist < closestDist {
                closestDist = dist
                closest = [entry]
            } else if dist == closestDist {
                closest.append(entry)
            }
        }

        guard !closest.isEmpty else { return filtered["\(episode)"] }

        return closest.min(by: {
            abs(Int($0.key) ?? 0 - episode) < abs(Int($1.key) ?? 0 - episode)
        })
    }

    private func fetchAniListProgress() {
        guard let id = animeItem?.id ?? animeEntity?.animeAnilistId?.intValue, id > 0 else { return }
        AniListTracking.shared.fetchProgress(anilistID: id) { [weak self] progress in
            guard let self = self else { return }
            let newProgress = progress ?? 0
            DispatchQueue.main.async {
                guard self.anilistProgress != newProgress else { return }
                self.anilistProgress = newProgress
                if newProgress > 0 {
                    let desiredPage = newProgress / self.episodesPerPage + 1
                    self.currentEpisodePage = min(max(1, desiredPage), self.totalEpisodePages)
                }
                self.tableView.reloadData()
            }
        }
    }

    private func refreshButtonStates() {
        guard let id = animeItem?.id ?? animeEntity?.animeAnilistId?.intValue, id > 0 else { return }
        AniListTracking.shared.checkIsFavourite(mediaID: id) { [weak self] isFav in
            DispatchQueue.main.async {
                self?.isFavorite = isFav
                self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false,
                                                     isOnList: self?.isOnList ?? false)
            }
        }
        AniListTracking.shared.fetchMediaWithEntry(anilistID: id) { [weak self] entry, _, _, _, _ in
            DispatchQueue.main.async {
                self?.isOnList = entry != nil
                self?.currentListStatus = entry?.status
                self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false,
                                                     isOnList: self?.isOnList ?? false)
                self?.headerView?.updatePlayButtonTitle(listStatus: entry?.status)
            }
        }
    }

    private func fetchEpisodes() {
        let anilistId: Int?
        if let entity = animeEntity {
            anilistId = entity.animeAnilistId?.intValue
        } else {
            anilistId = animeItem?.id
        }
        guard let id = anilistId else { return }

        let anilistEpisodes: Int?
        if let entity = animeEntity {
            anilistEpisodes = entity.animeTotalEps?.intValue
        } else {
            anilistEpisodes = animeItem?.episodes
        }

        let format = animeItem?.format

        AniZipService.shared.episodes(anilistID: id) { [weak self] response in
            guard let self = self, let response = response else { return }

            let hasAnidbId = response.mappings?.anidb_id != nil

            if !hasAnidbId, let fmt = format, ["SPECIAL", "OVA", "ONA"].contains(fmt) {
                self.resolveParentID(format: fmt) { [weak self] parentID in
                    guard let self = self else { return }
                    if let parentID = parentID {
                        AnimeService.sharedAnimeService.fetchMediaAiringSchedule(anilistID: id) { [weak self] schedResult in
                            guard let self = self else { return }

                            var alSchedule: [Int: Date] = schedResult?.schedule ?? [:]

                            if alSchedule[1] == nil {
                                let item = self.animeItem
                                let allTitles = [item?.titleEnglish, item?.titleRomaji].compactMap { $0 }
                                let singleEp = self.isSingleEpisode(
                                    format: fmt, titles: allTitles,
                                    synonyms: item?.synonyms ?? [],
                                    duration: item?.duration, episodes: anilistEpisodes)
                                if singleEp, let sd = schedResult?.startDate,
                                   let y = sd.year {
                                    let m = sd.month ?? 1
                                    let d = sd.day ?? 1
                                    var comps = DateComponents()
                                    comps.year = y; comps.month = m; comps.day = d
                                    if let date = Calendar(identifier: .gregorian).date(from: comps) {
                                        alSchedule[1] = date
                                    }
                                }
                            }

                            AniZipService.shared.episodes(anilistID: parentID) { [weak self] parentResponse in
                                guard let self = self else { return }
                                let finalResponse = parentResponse ?? response
                                self.processEpisodeResponse(finalResponse, anilistEpisodes: anilistEpisodes,
                                                            anilistId: id, alSchedule: alSchedule)
                            }
                        }
                    } else {
                        self.processEpisodeResponse(response, anilistEpisodes: anilistEpisodes, anilistId: id)
                    }
                }
                return
            }

            self.processEpisodeResponse(response, anilistEpisodes: anilistEpisodes, anilistId: id)
        }
    }

    private func resolveParentID(format: String, completion: @escaping (Int?) -> Void) {
        if let item = animeItem, !item.relations.isEmpty {
            let parentID = ["PARENT", "PREQUEL", "SEQUEL"].lazy.compactMap { relType -> Int? in
                item.relations.first { $0.relationType == relType }?.media.id
            }.first
            completion(parentID)
            return
        }

        guard let id = animeItem?.id ?? animeEntity?.animeAnilistId?.intValue else {
            completion(nil)
            return
        }
        AnimeService.sharedAnimeService.fetchDetailForItem(id: id) { [weak self] relations in
            self?.animeItem?.relations = relations
            self?.relations = relations
            let parentID = ["PARENT", "PREQUEL", "SEQUEL"].lazy.compactMap { relType -> Int? in
                relations.first { $0.relationType == relType }?.media.id
            }.first
            completion(parentID)
        }
    }

    private func processEpisodeResponse(_ response: AniZipEpisodesResponse, anilistEpisodes: Int?, anilistId: Int,
                                        alSchedule: [Int: Date]? = nil) {
        let episodesDict = response.episodes ?? [:]
        let episodesResCount = response.episodeCount
        let specialCount = response.specialCount ?? 0

        let count = anilistEpisodes ?? episodesResCount ?? 0

        var filtered: [String: FilteredEpisode] = [:]
        for (key, entry) in episodesDict {
            let airdate = entry.airdate ?? entry.airDate
            var airdatems: Double? = nil
            if let airdate = airdate {
                if let d = ISO8601DateFormatter().date(from: airdate) {
                    airdatems = d.timeIntervalSince1970 * 1000
                } else {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "yyyy-MM-dd"
                    fmt.locale = Locale(identifier: "en_US_POSIX")
                    if let d = fmt.date(from: airdate) {
                        airdatems = d.timeIntervalSince1970 * 1000
                    }
                }
            }
            filtered[key] = FilteredEpisode(key: key, entry: entry, airdatems: airdatems, anidbEid: entry.anidbEid)
        }

        let hasSpecial = specialCount > 0
        let hasCountMatch = (anilistEpisodes ?? 0) == (episodesResCount ?? 0)

        let now = Date().timeIntervalSince1970 * 1000

        var anizipBannerURL: String? = nil
        if let images = response.images {
            let fanart = images.first(where: { $0.coverType == "Fanart" })?.url
            let poster = images.first(where: { $0.coverType == "Poster" })?.url
            anizipBannerURL = fanart ?? poster
        }

        var parsed: [AniZipEpisode] = []
        guard count > 0 else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.episodes = []
                self.currentEpisodePage = 1
                self.tableView.reloadSections(IndexSet([Section.episodes.rawValue, Section.episodePagination.rawValue]), with: .none)
                if let bannerURL = anizipBannerURL {
                    self.headerView.updateBanner(from: bannerURL)
                }
            }
            return
        }

        for episode in 1...count {
            let hasEpisode = episodesDict["\(episode)"] != nil

            let needsValidation = !(!hasSpecial || (hasEpisode && hasCountMatch))

            let resolvedEntry: FilteredEpisode?
            if needsValidation {
                let alDate = alSchedule?[episode]
                resolvedEntry = self.episodeByAirDate(alDate: alDate, filtered: filtered, episode: episode)

                if let resolved = resolvedEntry {
                    var keysToRemove: [String] = []
                    for (key, entry) in filtered {
                        if let eid = entry.anidbEid, let resolvedEid = resolved.anidbEid, eid == resolvedEid {
                            keysToRemove.append(key)
                        } else if let entryMs = entry.airdatems, entryMs < (resolved.airdatems ?? now) {
                            keysToRemove.append(key)
                        }
                    }
                    for key in keysToRemove {
                        filtered.removeValue(forKey: key)
                    }
                }
            } else {
                resolvedEntry = filtered["\(episode)"]
            }

            let entry = resolvedEntry?.entry
            let titles = entry?.title ?? [:]
            let title = titles["en"] ?? titles["x-jat"] ?? titles["ja"] ?? ""
            let overview = (entry?.overview ?? entry?.summary ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let imageURL = entry?.image
            let airDateRaw = entry?.airdate ?? entry?.airDate
            let airDate: Date? = airDateRaw.flatMap { raw in
                if let d = ISO8601DateFormatter().date(from: raw) { return d }
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                fmt.locale = Locale(identifier: "en_US_POSIX")
                return fmt.date(from: raw)
            }
            let runtime = entry?.length ?? entry?.runtime ?? 0
            let rating: Double? = entry?.rating.flatMap(Double.init)

            parsed.append(AniZipEpisode(
                number: episode,
                title: title.isEmpty ? "Episode \(episode)" : title,
                overview: overview, imageURL: imageURL, airDate: airDate,
                runtime: runtime, rating: rating, isFiller: false))
        }

        AnimeDetailViewController.loadFillerSet(for: anilistId) { fillerSet in
            let finalEpisodes = parsed.map { ep in
                AniZipEpisode(number: ep.number, title: ep.title, overview: ep.overview,
                              imageURL: ep.imageURL, airDate: ep.airDate, runtime: ep.runtime,
                              rating: ep.rating, isFiller: fillerSet.contains(ep.number))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.episodes = finalEpisodes
                if self.currentEpisodePage > self.totalEpisodePages {
                    self.currentEpisodePage = 1
                }
                self.tableView.reloadSections(IndexSet([Section.episodes.rawValue, Section.episodePagination.rawValue]), with: .none)
                if let bannerURL = anizipBannerURL {
                    self.headerView.updateBanner(from: bannerURL)
                }
            }
        }
    }

    // MARK: - Filler cache

    private static var _fillerMap: [Int: Set<Int>] = [:]
    private static var _fillerMapLoaded = false
    private static var _fillerMapCallbacks: [([Int: Set<Int>]) -> Void] = []
    private static let _fillerQueue = DispatchQueue(label: "com.nyais.fillerCache")

    private static func loadFillerSet(for anilistId: Int, completion: @escaping (Set<Int>) -> Void) {
        _fillerQueue.async {
            if _fillerMapLoaded {
                let set = _fillerMap[anilistId] ?? []
                completion(set)
                return
            }
            let isFirst = _fillerMapCallbacks.isEmpty
            _fillerMapCallbacks.append { map in completion(map[anilistId] ?? []) }
            guard isFirst else { return }

            let url = URL(string: "https://raw.githubusercontent.com/ThaUnknown/filler-scrape/master/filler.json")!
            URLSession.shared.dataTask(with: url) { data, _, _ in
                var map: [Int: Set<Int>] = [:]
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for (key, val) in json {
                        if let aid = Int(key), let raw = val as? [Any] {
                            map[aid] = Set(raw.compactMap { ($0 as? NSNumber)?.intValue })
                        }
                    }
                }
                _fillerQueue.async {
                    let callbacks = _fillerMapCallbacks
                    _fillerMap = map
                    _fillerMapLoaded = true
                    _fillerMapCallbacks = []
                    for cb in callbacks { cb(map) }
                }
            }.resume()
        }
    }

    // MARK: - Fetch relations

    private func fetchRelationsAndCharacters() {
        let id: Int?
        if let entity = animeEntity { id = entity.animeAnilistId?.intValue }
        else { id = animeItem?.id }
        guard let anilistId = id else { return }

        AnimeService.sharedAnimeService.fetchDetailForItem(id: anilistId) { [weak self] relations in
            guard let self = self else { return }
            self.relations = relations
            if !relations.isEmpty {
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

    // MARK: - Tab bar

    private func tabChanged(to index: Int) {
        let sectionMap: [Int: Section] = [0: .episodes, 1: .relations, 2: .threads, 3: .themes]
        guard let sec = sectionMap[index] else { return }
        activeSection = sec
        let contentRange = Section.episodes.rawValue..<Section.allCases.count
        tableView.reloadSections(IndexSet(integersIn: contentRange), with: .automatic)
        if sec == .threads && threads.isEmpty && !threadsLoading { fetchThreads() }
        if sec == .themes  && themes.isEmpty  && !themesLoading  { fetchThemes()  }
    }

    private func setEpisodePage(_ page: Int) {
        let clamped = min(max(1, page), totalEpisodePages)
        guard clamped != currentEpisodePage else { return }
        currentEpisodePage = clamped
        let sectionsToReload = IndexSet([Section.episodes.rawValue, Section.episodePagination.rawValue])
        tableView.reloadSections(sectionsToReload, with: .automatic)
    }

    // MARK: - Threads (AnimeService)

    private func fetchThreads() {
        guard let id = animeItem?.id else { return }
        threadsLoading = true
        tableView.reloadSections(IndexSet(integer: Section.threads.rawValue), with: .none)

        AnimeService.sharedAnimeService.fetchForumThreads(mediaID: id) { [weak self] parsed in
            guard let self else { return }
            self.threads = parsed
            self.threadsLoading = false
            if self.activeSection == .threads {
                self.tableView.reloadSections(IndexSet(integer: Section.threads.rawValue), with: .fade)
            }
        }
    }

    // MARK: - Themes (AnimeThemesService)

    private func fetchThemes() {
        guard let id = animeItem?.id else { return }
        themesLoading = true
        tableView.reloadSections(IndexSet(integer: Section.themes.rawValue), with: .none)

        AnimeThemesService.shared.themes(anilistID: id) { [weak self] response in
            guard let self else { return }
            let parsed = response?.anime?.first?.animethemes ?? []
            DispatchQueue.main.async {
                self.themes = parsed
                self.themesLoading = false
                if self.activeSection == .themes {
                    self.tableView.reloadSections(IndexSet(integer: Section.themes.rawValue), with: .fade)
                }
            }
        }
    }

    // MARK: - Navigation

    private func openExtensionSearch(episode: Int) {
        let searchVC = ExtensionSearchViewController()
        searchVC.animeItem = animeItem
        searchVC.initialEpisode = episode

        if traitCollection.horizontalSizeClass == .regular {
            searchVC.modalPresentationStyle = .custom
            searchVC.transitioningDelegate = searchVC
        } else {
            searchVC.modalPresentationStyle = .fullScreen
        }

        guard var presenter = view.window?.rootViewController else {
            self.present(searchVC, animated: true)
            return
        }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(searchVC, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension AnimeDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .header:    return 1
        case .episodes:
            if activeSection != .episodes { return 0 }
            let cols = episodeColumnCount
            return (paginatedEpisodes.count + cols - 1) / cols
        case .episodePagination:
            return (activeSection == .episodes && totalEpisodePages > 1) ? 1 : 0
        case .relations: return (activeSection == .relations && !relations.isEmpty) ? 1 : 0
        case .threads:
            if activeSection != .threads { return 0 }
            if threadsLoading || threads.isEmpty { return 1 }
            let cols = threadColumnCount
            return (threads.count + cols - 1) / cols
        case .themes:
            if activeSection != .themes { return 0 }
            return themesLoading ? 1 : max(themes.count, 1)
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .header:
            let cell = tableView.dequeueReusableCell(withIdentifier: "HeaderCell", for: indexPath)
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.selectionStyle = .none
            cell.clipsToBounds = false
            cell.contentView.clipsToBounds = false
            if headerView.superview !== cell.contentView {
                headerView.clipsToBounds = false
                headerView.translatesAutoresizingMaskIntoConstraints = false
                tabBarContainer.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(headerView)
                cell.contentView.addSubview(tabBarContainer)
                NSLayoutConstraint.activate([
                    headerView.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    headerView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    headerView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    tabBarContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
                    tabBarContainer.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    tabBarContainer.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    tabBarContainer.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                ])
                applyTabBarLayoutForSizeClass()
            }
            headerView.updateLabelWidths(forContainerWidth: tableView.frame.width)
            return cell

        case .episodes:
            let cols = episodeColumnCount
            let currentAnilistID = animeItem?.id ?? (animeEntity?.animeAnilistId?.intValue ?? 0)
            let isCompleted = currentListStatus == "COMPLETED"
            if cols >= 2 {
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: EpisodePairCell.reuseID, for: indexPath) as? EpisodePairCell else {
                    return UITableViewCell()
                }
                let leftIdx = indexPath.row * 2
                let rightIdx = leftIdx + 1
                let leftEp = paginatedEpisodes[leftIdx]
                let rightEp = rightIdx < paginatedEpisodes.count ? paginatedEpisodes[rightIdx] : nil
                cell.configure(left: leftEp, right: rightEp, anilistID: currentAnilistID,
                               anilistProgress: anilistProgress, accentColor: currentAnimeAccent,
                               isListCompleted: isCompleted)
                cell.onTapEpisode = { [weak self] epNumber in
                    self?.openExtensionSearch(episode: epNumber)
                }
                return cell
            } else {
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: EpisodeCell.reuseID, for: indexPath) as? EpisodeCell else {
                    return UITableViewCell()
                }
                let ep = paginatedEpisodes[indexPath.row]
                cell.configure(with: ep, anilistID: currentAnilistID, anilistProgress: anilistProgress,
                               accentColor: currentAnimeAccent, isListCompleted: isCompleted)
                cell.cardView.onTap = { [weak self] epNumber in
                    self?.openExtensionSearch(episode: epNumber)
                }
                cell.applyPaddingForSizeClass(isRegular: traitCollection.horizontalSizeClass == .regular)
                return cell
            }

        case .episodePagination:
            let cell = tableView.dequeueReusableCell(withIdentifier: "PaginationCell", for: indexPath)
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.selectionStyle = .none
            if paginationBar.superview !== cell.contentView {
                paginationBar.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(paginationBar)
                NSLayoutConstraint.activate([
                    paginationBar.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    paginationBar.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    paginationBar.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    paginationBar.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                ])
            }
            paginationBar.configure(currentPage: currentEpisodePage, totalCount: episodes.count, perPage: episodesPerPage)
            paginationBar.applyPaddingForSizeClass(isRegular: traitCollection.horizontalSizeClass == .regular)
            return cell

        case .relations:
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

        case .threads:
            let cols = threadColumnCount
            if cols >= 2 && !threadsLoading && !threads.isEmpty {
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: ThreadPairCell.reuseID, for: indexPath) as? ThreadPairCell else {
                    return UITableViewCell()
                }
                let accentColor = animeItem.flatMap { item in
                    ExtensionSearchViewController.uiColor(fromHex: item.coverColor ?? "") } ?? UIColor(white: 0.15, alpha: 1)
                let leftIdx = indexPath.row * 2
                let rightIdx = leftIdx + 1
                let leftThread = threads[leftIdx]
                let rightThread = rightIdx < threads.count ? threads[rightIdx] : nil
                cell.configure(left: leftThread, right: rightThread, accentColor: accentColor)
                cell.onTapThread = { [weak self] threadID in
                    guard let self = self else { return }
                    guard let thread = self.threads.first(where: { $0.id == threadID }) else { return }
                    let threadVC = ThreadDetailViewController(threadID: thread.id, title: thread.title)
                    self.navigationController?.pushViewController(threadVC, animated: true)
                }
                return cell
            } else {
                let cell = makeThreadCell(for: indexPath)
                return cell
            }

        case .themes:
            let cell = makeThemeCell(for: indexPath)
            return cell

        case .none:
            return UITableViewCell()
        }
    }
}

// MARK: - UITableViewDelegate

extension AnimeDetailViewController: UITableViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        if offsetY < 0 {
            headerView.applyOverscrollZoom(-offsetY)
        } else {
            headerView.applyOverscrollZoom(0)
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return nil
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return nil
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section) {
        case .relations:          return 160
        default:                  return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        if Section(rawValue: indexPath.section) == .header { return 600 }
        return 100
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .episodes:
            if episodeColumnCount >= 2 { break }
            let ep = paginatedEpisodes[indexPath.row]
            openExtensionSearch(episode: ep.number)
        case .threads:
            if threadColumnCount >= 2 { break }
            guard !threadsLoading, !threads.isEmpty else { return }
            let thread = threads[indexPath.row]
            let threadVC = ThreadDetailViewController(threadID: thread.id, title: thread.title)
            navigationController?.pushViewController(threadVC, animated: true)
        case .themes:
            break
        default: break
        }
    }
}

// MARK: - UICollectionViewDataSource

extension AnimeDetailViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch collectionView.tag {
        case 100: return relations.count
        case 300: return staff.count
        default:  return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch collectionView.tag {
        case 100:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: RelationCardCell.reuseID, for: indexPath) as? RelationCardCell
            else { return UICollectionViewCell() }
            cell.configure(with: relations[indexPath.item])
            return cell
        case 300:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: StaffCardCell.reuseID, for: indexPath) as? StaffCardCell
            else { return UICollectionViewCell() }
            cell.configure(with: staff[indexPath.item])
            return cell
        default:
            return UICollectionViewCell()
        }
    }
}

// MARK: - UICollectionViewDelegate

extension AnimeDetailViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard collectionView.tag == 100 else { return }
        let relation = relations[indexPath.item]
        guard let detailVC = storyboard?.instantiateViewController(
            withIdentifier: "AnimeDetailVC") as? AnimeDetailViewController else { return }
        detailVC.animeItem = relation.media
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - Thread & Theme cell builders

extension AnimeDetailViewController {

    private func makeEmptyStateCell(text: String, loading: Bool) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        let label = UILabel()
        label.text = loading ? "Loading…" : text
        label.textColor = UIColor(white: loading ? 0.7 : 0.5, alpha: 1)
        label.font = .nunito(ofSize: 14)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
            label.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 40),
            label.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -40),
        ])
        return cell
    }

    func makeThreadCell(for indexPath: IndexPath) -> UITableViewCell {
        if threadsLoading || threads.isEmpty {
            return makeEmptyStateCell(
                text: "No threads found.",
                loading: threadsLoading)
        }
        let thread = threads[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .default

        let card = UIView()
        card.backgroundColor = hayaseCardBackground
        card.layer.cornerRadius = 6
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(card)

        let titleLabel = UILabel()
        titleLabel.text = thread.title
        titleLabel.font = .nunito(ofSize: 12.8, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let statsLabel = UILabel()
        statsLabel.text = "♥ \(thread.likeCount)  👁 \(thread.viewCount)  💬 \(thread.replyCount)\(thread.isLocked ? "  🔒" : "")"
        statsLabel.font = .nunito(ofSize: 9.6)
        statsLabel.textColor = UIColor(white: 0.6, alpha: 1)
        statsLabel.translatesAutoresizingMaskIntoConstraints = false

        let footerLabel = UILabel()
        var footerParts = [thread.sinceString]
        if let name = thread.userName { footerParts.append("by \(name)") }
        footerLabel.text = footerParts.joined(separator: " · ")
        footerLabel.font = .nunito(ofSize: 9.6)
        footerLabel.textColor = UIColor(white: 0.5, alpha: 1)
        footerLabel.translatesAutoresizingMaskIntoConstraints = false

        let accentColor = animeItem.flatMap { item in
            ExtensionSearchViewController.uiColor(fromHex: item.coverColor ?? "") } ?? UIColor(white: 0.15, alpha: 1)
        let badgeStack = UIStackView()
        badgeStack.axis = .horizontal
        badgeStack.spacing = 8
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        for cat in thread.categories.prefix(3) {
            let badge = ThreadBadgeLabel()
            badge.text = cat
            badge.font = .nunito(ofSize: 9.6, weight: .bold)
            badge.textColor = ExtensionSearchViewController.luminanceContrastColor(for: accentColor)
            badge.backgroundColor = accentColor
            badge.layer.cornerRadius = 4
            badge.clipsToBounds = true
            badge.textAlignment = .center
            badge.translatesAutoresizingMaskIntoConstraints = false
            badgeStack.addArrangedSubview(badge)
        }

        card.addSubview(titleLabel)
        card.addSubview(statsLabel)
        card.addSubview(footerLabel)
        card.addSubview(badgeStack)
        statsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let sidePad: CGFloat = traitCollection.horizontalSizeClass == .regular ? 56 : 16

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 14),
            card.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -14),
            card.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: sidePad),
            card.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -sidePad),
            card.heightAnchor.constraint(lessThanOrEqualToConstant: 112),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: statsLabel.leadingAnchor, constant: -8),

            statsLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            statsLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            footerLabel.topAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: 6),
            footerLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            footerLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            badgeStack.centerYAnchor.constraint(equalTo: footerLabel.centerYAnchor),
            badgeStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return cell
    }

    func makeThemeCell(for indexPath: IndexPath) -> UITableViewCell {
        if themesLoading || themes.isEmpty {
            return makeEmptyStateCell(
                text: "No themes found.",
                loading: themesLoading)
        }
        let theme = themes[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none

        let card = UIView()
        card.backgroundColor = hayaseCardBackground
        card.layer.cornerRadius = 6
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(card)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let headerRow = UIView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        let typeLabel = UILabel()
        typeLabel.text = theme.slug?.uppercased() ?? theme.type?.uppercased() ?? ""
        typeLabel.font = .nunito(ofSize: 12, weight: .bold)
        typeLabel.textColor = UIColor(white: 0.7, alpha: 1)
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(typeLabel)

        let songTitle = NSMutableAttributedString(
            string: theme.song?.title ?? "Unknown",
            attributes: [.font: UIFont.nunito(ofSize: 16, weight: .bold), .foregroundColor: UIColor.white])
        let artistNames = theme.song?.artists?.compactMap { $0.name }.joined(separator: ", ") ?? ""
        if !artistNames.isEmpty {
            songTitle.append(NSAttributedString(
                string: " by ",
                attributes: [.font: UIFont.nunito(ofSize: 12, weight: .medium), .foregroundColor: UIColor(white: 0.5, alpha: 1)]))
            songTitle.append(NSAttributedString(
                string: artistNames,
                attributes: [.font: UIFont.nunito(ofSize: 16, weight: .bold), .foregroundColor: UIColor.white]))
        }
        let songLabel = UILabel()
        songLabel.attributedText = songTitle
        songLabel.numberOfLines = 1
        songLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(songLabel)

        NSLayoutConstraint.activate([
            headerRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            typeLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            typeLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            typeLabel.widthAnchor.constraint(equalToConstant: 48),
            songLabel.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor),
            songLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            songLabel.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
        ])
        stack.addArrangedSubview(headerRow)

        let accentColor = currentAnimeAccent

        for entry in (theme.animethemeentries ?? []) {
            let row = UIView()
            row.translatesAutoresizingMaskIntoConstraints = false

            let verLabel = UILabel()
            verLabel.text = "v\(entry.version ?? 1)"
            verLabel.font = .nunito(ofSize: 12)
            verLabel.textColor = UIColor(white: 0.5, alpha: 1)
            verLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(verLabel)

            let epLabel = UILabel()
            let eps = entry.episodes ?? ""
            epLabel.text = eps.isEmpty ? "" : "Episodes \(eps)"
            epLabel.font = .nunito(ofSize: 12)
            epLabel.textColor = UIColor(white: 0.5, alpha: 1)
            epLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(epLabel)

            let playBtn = UIButton(type: .system)
            let playIconCfg = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            playBtn.setImage(UIImage(systemName: "play.fill")?.withConfiguration(playIconCfg), for: .normal)
            playBtn.tintColor = ExtensionSearchViewController.luminanceContrastColor(for: accentColor)
            playBtn.backgroundColor = accentColor
            playBtn.layer.cornerRadius = 13
            playBtn.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(playBtn)

            let videoLink = entry.videos?.last?.link
            if let urlStr = videoLink {
                playBtn.addTarget(self, action: #selector(themePlayTapped(_:)), for: .touchUpInside)
                objc_setAssociatedObject(playBtn, &themeURLKey, urlStr, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            } else {
                playBtn.isHidden = true
            }

            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
                verLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                verLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                verLabel.widthAnchor.constraint(equalToConstant: 48),
                epLabel.leadingAnchor.constraint(equalTo: verLabel.trailingAnchor),
                epLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                playBtn.leadingAnchor.constraint(greaterThanOrEqualTo: epLabel.trailingAnchor, constant: 8),
                playBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                playBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                playBtn.widthAnchor.constraint(equalToConstant: 26),
                playBtn.heightAnchor.constraint(equalToConstant: 26),
            ])
            stack.addArrangedSubview(row)
        }

        let themeSidePad: CGFloat = traitCollection.horizontalSizeClass == .regular ? 56 : 16

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -4),
            card.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: themeSidePad),
            card.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -themeSidePad),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
        ])
        return cell
    }

    @objc private func themePlayTapped(_ sender: UIButton) {
        guard let urlStr = objc_getAssociatedObject(sender, &themeURLKey) as? String,
              let url = URL(string: urlStr) else { return }
        let player = ThemePlayerViewController(videoURL: url)
        present(player, animated: true)
    }
}
