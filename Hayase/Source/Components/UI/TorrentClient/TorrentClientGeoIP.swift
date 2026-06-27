//
//  TorrentClientGeoIP.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation
import CoreLocation

final class TorrentClientGeoIP {
    struct Location {
        let country: String
        let region: String
        let city: String
        let coordinate: CLLocationCoordinate2D
    }

    static let shared = TorrentClientGeoIP()

    private struct Params: Decodable {
        let numberNodesPerMidindex: Int

        enum CodingKeys: String, CodingKey {
            case numberNodesPerMidindex
            case numberNodesPerMidindexUpper = "NUMBER_NODES_PER_MIDINDEX"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.numberNodesPerMidindex =
                (try? container.decode(Int.self, forKey: .numberNodesPerMidindexUpper))
                ?? (try? container.decode(Int.self, forKey: .numberNodesPerMidindex))
                ?? 65_536
        }

        init(numberNodesPerMidindex: Int) {
            self.numberNodesPerMidindex = numberNodesPerMidindex
        }
    }

    private struct LocationRecord: Decodable {
        let country: String
        let region: String
        let city: String

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            country = try container.decode(String.self)
            region = try container.decode(String.self)
            city = try container.decode(String.self)
        }
    }

    private struct IPBlockRecord: Decodable {
        let start: UInt32
        let locationIndex: Int?
        let latitude: Double
        let longitude: Double

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            start = try container.decode(UInt32.self)
            locationIndex = try container.decodeIfPresent(Int.self)
            latitude = try container.decode(Double.self)
            longitude = try container.decode(Double.self)
        }
    }

    private let queue = DispatchQueue(label: "app.hayase.torrentclient.geoip")
    private var indexCache: [String: [UInt32]] = [:]
    private var blockCache: [String: [IPBlockRecord]] = [:]
    private var locationCache: [LocationRecord]?
    private var paramsCache: Params?

    private init() {}

    func lookup(_ ip: String) -> Location? {
        queue.sync {
            lookupLocked(ip)
        }
    }

    private func lookupLocked(_ stringifiedIP: String) -> Location? {
        guard let ip = ipStr2Num(stringifiedIP),
              let data = readIndexFile("index") else { return nil }

        let mask = ipStr2Num("255.255.255.255") ?? UInt32.max
        let rootIndex = binarySearch(data, item: ip) { $0 }
        guard rootIndex >= 0 else { return nil }

        var nextIP = getNextIP(data, index: rootIndex, currentNextIP: mask) { $0 }
        guard let data2 = readIndexFile("i\(rootIndex)") else { return nil }

        let midIndex = binarySearch(data2, item: ip) { $0 }
        guard midIndex >= 0 else { return nil }
        let blockIndex = midIndex + rootIndex * params().numberNodesPerMidindex
        nextIP = getNextIP(data2, index: midIndex, currentNextIP: nextIP) { $0 }

        guard let blocks = readBlockFile("\(blockIndex)") else { return nil }
        let index = binarySearch(blocks, item: ip) { $0.start }
        guard index >= 0, index < blocks.count else { return nil }

        _ = getNextIP(blocks, index: index, currentNextIP: nextIP) { $0.start }
        let block = blocks[index]
        guard let locationIndex = block.locationIndex,
              let locations = readLocations(),
              locationIndex >= 0,
              locationIndex < locations.count else { return nil }

        let location = locations[locationIndex]
        return Location(country: location.country,
                        region: location.region,
                        city: location.city,
                        coordinate: CLLocationCoordinate2D(latitude: block.latitude,
                                                           longitude: block.longitude))
    }

    private func params() -> Params {
        if let paramsCache { return paramsCache }
        let params = readJSON(Params.self, name: "params") ?? Params(numberNodesPerMidindex: 65_536)
        paramsCache = params
        return params
    }

    private func readLocations() -> [LocationRecord]? {
        if let locationCache { return locationCache }
        let locations = readJSON([LocationRecord].self, name: "locations")
        locationCache = locations
        return locations
    }

    private func readIndexFile(_ name: String) -> [UInt32]? {
        if let cached = indexCache[name] { return cached }
        guard let value = readJSON([UInt32].self, name: name) else { return nil }
        indexCache[name] = value
        return value
    }

    private func readBlockFile(_ name: String) -> [IPBlockRecord]? {
        if let cached = blockCache[name] { return cached }
        guard let value = readJSON([IPBlockRecord].self, name: name) else { return nil }
        blockCache[name] = value
        return value
    }

    private func readJSON<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name,
                                        withExtension: "json",
                                        subdirectory: "TorrentClientGeoIP")
            ?? Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func binarySearch<T>(_ list: [T], item: UInt32, extractKey: (T) -> UInt32) -> Int {
        guard !list.isEmpty else { return -1 }
        var low = 0
        var high = list.count - 1

        while true {
            let index = Int(round(Double(high - low) / 2)) + low
            let key = extractKey(list[index])
            if item < key {
                if index == high && index == low {
                    return -1
                } else if index == high {
                    high = low
                } else {
                    high = index
                }
            } else if item >= key && (index == list.count - 1 || item < extractKey(list[index + 1])) {
                return index
            } else {
                low = index
            }
        }
    }

    private func getNextIP<T>(_ data: [T],
                              index: Int,
                              currentNextIP: UInt32,
                              extractKey: (T) -> UInt32) -> UInt32 {
        if index < data.count - 1 {
            return extractKey(data[index + 1])
        }
        return currentNextIP
    }

    private func ipStr2Num(_ stringifiedIP: String) -> UInt32? {
        let parts = normalizedIPv4(stringifiedIP).split(separator: ".")
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for (index, part) in parts.enumerated() {
            guard let value = UInt32(part), value <= 255 else { return nil }
            result += value << UInt32((3 - index) * 8)
        }
        return result
    }

    private func normalizedIPv4(_ stringifiedIP: String) -> String {
        var value = stringifiedIP.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("::ffff:") {
            value.removeFirst("::ffff:".count)
        }
        if let colonIndex = value.lastIndex(of: ":") {
            let host = String(value[..<colonIndex])
            if host.contains(".") {
                value = host
            }
        }
        return value
    }
}
