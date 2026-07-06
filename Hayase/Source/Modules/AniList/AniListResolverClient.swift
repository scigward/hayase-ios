//
//  AniListResolverClient.swift
//  Hayase
//
//  Resolver-oriented AniList helpers.
//  Mirrors: client.ts searchCompound/malIdsCompound/singleTitle helpers.
//

import Foundation

extension AniListClient {
    func searchCompoundResult(flattenedTitles: [(key: String, title: String, year: String?, isAdult: Bool)],
                              completion: @escaping (Result<[String: Int], AniListRequestError>) -> Void) {
        var groups: [String: (titles: [String], year: String?)] = [:]
        for title in flattenedTitles {
            var group = groups[title.key] ?? (titles: [], year: nil)
            group.titles.append(title.title)
            if group.year == nil { group.year = title.year }
            groups[title.key] = group
        }
        let grouped = groups
            .map { (key: $0.key, titles: $0.value.titles, year: $0.value.year) }
            .sorted { $0.key < $1.key }
        searchResolverAnimeIDsResult(titleGroups: grouped, completion: completion)
    }

    func malIdsCompoundResult(_ malIDs: [Int],
                              completion: @escaping (Result<[Int: Int], AniListRequestError>) -> Void) {
        let ids = Array(Set(malIDs)).sorted()
        guard !ids.isEmpty else {
            DispatchQueue.main.async { completion(.success([:])) }
            return
        }

        var result: [Int: Int] = [:]
        var firstError: AniListRequestError?
        let chunks = stride(from: 0, to: ids.count, by: 3500).map {
            Array(ids[$0..<min($0 + 3500, ids.count)])
        }

        func run(_ index: Int) {
            guard index < chunks.count else {
                DispatchQueue.main.async {
                    if let firstError {
                        completion(.failure(firstError))
                    } else {
                        completion(.success(result))
                    }
                }
                return
            }

            let chunk = chunks[index]
            let query = """
            query($ids: [Int]) {
              Page(perPage: 50) {
                media(idMal_in: $ids, type: ANIME) {
                  id
                  idMal
                }
              }
            }
            """
            AniListRequestExecutor.shared.execute(query: query,
                                                  variables: ["ids": chunk],
                                                  authorized: true,
                                                  dedupeKey: "malIds|\(chunk)") { graphResult in
                switch graphResult {
                case .success(let graphQLResult):
                    let page = (graphQLResult.json["data"] as? [String: Any])?["Page"] as? [String: Any]
                    let media = page?["media"] as? [[String: Any]] ?? []
                    for item in media {
                        guard let anilistID = item["id"] as? Int,
                              let malID = item["idMal"] as? Int else { continue }
                        result[malID] = anilistID
                    }
                case .failure(let error):
                    if firstError == nil { firstError = error }
                }
                run(index + 1)
            }
        }

        run(0)
    }

    func singleTitleResult(id: Int,
                           completion: @escaping (Result<AniListSingleTitle?, AniListRequestError>) -> Void) {
        AniListRequestExecutor.shared.execute(query: AniListQueries.idTitle,
                                              variables: ["id": id],
                                              authorized: true,
                                              dedupeKey: "singleTitle|\(id)") { result in
            switch result {
            case .success(let graphQLResult):
                let media = (graphQLResult.json["data"] as? [String: Any])?["Media"] as? [String: Any]
                let title = media?["title"] as? [String: Any]
                let payload = media.flatMap { media -> AniListSingleTitle? in
                    guard let id = media["id"] as? Int else { return nil }
                    return AniListSingleTitle(id: id, userPreferred: title?["userPreferred"] as? String)
                }
                DispatchQueue.main.async { completion(.success(payload)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func updateUserResult(lists: [String]? = nil,
                          displayAdultContent: Bool? = nil,
                          titleLanguage: String? = nil,
                          completion: @escaping (Result<TrackerViewer, AniListRequestError>) -> Void) {
        var variables: [String: Any] = [:]
        if let lists { variables["lists"] = lists }
        if let displayAdultContent { variables["adult"] = displayAdultContent }
        if let titleLanguage { variables["language"] = titleLanguage }

        AniListRequestExecutor.shared.execute(query: AniListQueries.updateUser,
                                              variables: variables,
                                              authorized: true,
                                              dedupeKey: "updateUser|\(variables)") { result in
            switch result {
            case .success(let graphQLResult):
                guard let viewer = (graphQLResult.json["data"] as? [String: Any])?["UpdateUser"] as? [String: Any],
                      let parsed = TrackerViewer(anilistViewer: viewer) else {
                    DispatchQueue.main.async { completion(.failure(.emptyData)) }
                    return
                }
                AniListMutationUpdaters.applyViewerUpdate(parsed)
                DispatchQueue.main.async { completion(.success(parsed)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}

private extension TrackerViewer {
    init?(anilistViewer viewer: [String: Any]) {
        guard let id = viewer["id"] as? Int,
              let name = viewer["name"] as? String else { return nil }
        let avatar = (viewer["avatar"] as? [String: Any])?["large"] as? String
        let options = viewer["options"] as? [String: Any]
        let animeList = (viewer["mediaListOptions"] as? [String: Any])?["animeList"] as? [String: Any]
        let customLists = (animeList?["customLists"] as? [Any] ?? []).compactMap { $0 as? String }
        self.init(
            id: String(id),
            name: name,
            avatarURL: avatar,
            bannerURL: viewer["bannerImage"] as? String,
            titleLanguage: options?["titleLanguage"] as? String,
            displayAdultContent: options?["displayAdultContent"] as? Bool,
            customLists: customLists)
    }
}
