//
//  Sections.swift
//  Hayase
//
//  Mirrors: the script of interface routes/app/home/+page.svelte
//
//  The sections of Home and their queries: "Continue Watching", "Your List" and "Sequels You Missed"
//  for whoever is signed in, then the seven that everyone gets. A section's query waits (paused)
//  until its row is on screen, except for "Continue Watching" and the banner, which do not.
//

import UIKit

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
