// Mirrors: ui/torrentclient/library/table.svelte column accessors.
import Foundation

enum TorrentLibrarySort {
    static func less(_ lhs: WebTorrentLibraryEntry, _ rhs: WebTorrentLibraryEntry,
                     column: Int, ascending: Bool) -> Bool {
        func ordered<T: Comparable>(_ a: T, _ b: T) -> Bool {
            if a == b { return lhs.hash < rhs.hash }
            return ascending ? a < b : a > b
        }
        switch column {
        case 0: return ordered(lhs.mediaID ?? 0, rhs.mediaID ?? 0)
        case 1: return ordered(lhs.episode ?? 0, rhs.episode ?? 0)
        case 2: return ordered(lhs.files, rhs.files)
        case 3: return ordered(lhs.size, rhs.size)
        case 4: return ordered(lhs.progress == 1 ? 1 : 0, rhs.progress == 1 ? 1 : 0)
        case 5: return ordered(lhs.date ?? 0, rhs.date ?? 0)
        default: return ordered(lhs.name.isEmpty ? lhs.hash : lhs.name, rhs.name.isEmpty ? rhs.hash : rhs.name)
        }
    }
}
