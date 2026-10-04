//
//  Play.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/button/play.svelte: the button that plays the next episode of a media. What it
//  says and which episode it plays follow the status of the media's list entry; the banner, the preview card and the
//  anime page each draw the button themselves, with their own sizes and colours.
//

import Foundation

enum PlayButton {
    /// "Rewatch" when the media is completed, "Continue" while it is being watched (or is paused or repeating),
    /// and "Watch Now" otherwise
    static func title(listStatus: String?) -> String {
        switch listStatus {
        case "COMPLETED": return "Rewatch"
        case "CURRENT", "REPEATING", "PAUSED": return "Continue"
        default: return "Watch Now"
        }
    }

    /// `$status === 'COMPLETED' ? 1 : ($progressStore ?? 0) + 1`
    static func episode(listStatus: String?, progress: Int?) -> Int {
        listStatus == "COMPLETED" ? 1 : (progress ?? 0) + 1
    }
}
