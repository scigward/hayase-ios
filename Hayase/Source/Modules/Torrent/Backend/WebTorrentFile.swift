//
//  WebTorrentFile.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

struct WebTorrentFile: Decodable {
    let name: String
    let hash: String
    let type: String
    let size: Int64
    let path: String
    let url: String
    let lan: String
    let id: Int
}
