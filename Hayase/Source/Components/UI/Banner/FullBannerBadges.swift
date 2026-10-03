//
//  FullBannerBadges.swift
//  Hayase
//
//  Mirrors: the two button rows of interface components/ui/banner/full-banner.svelte, the
//  badges under the title and the genres at the right.
//

import UIKit

/// What a button of the banner searches for:
/// `goto('/#/app/search', { state: { search: { … } } })`.
enum BannerFilter {
    case format(String?)
    case status(String?)
    case season(String?, Int?)
    case score
    case genre(String)
}

enum FullBannerBadges {
    /// text-green-700, text-orange-400 and text-red-500: `getTextColorForRating`
    private static func ratingColor(_ rating: Float) -> UIColor {
        if rating >= 75 { return UIColor(red: 21/255.0, green: 128/255.0, blue: 61/255.0, alpha: 1) }
        if rating >= 65 { return UIColor(red: 251/255.0, green: 146/255.0, blue: 60/255.0, alpha: 1) }
        return UIColor(red: 239/255.0, green: 68/255.0, blue: 68/255.0, alpha: 1)
    }

    /// The row under the title: how many episodes (or how long), then the format, the status, the
    /// season and the score. `!text-custom` is the colour of the media's cover, except for the score.
    static func badgeViews(for item: AnimeItem, color: UIColor, onFilter: @escaping (BannerFilter) -> Void) -> [UIView] {
        var views: [UIView] = []

        // `{$ofStore ?? duration(current) ?? 'N/A'}` is a plain div; the rest are Buttons.
        let duration = item.duration.flatMap { $0 > 0 ? "\($0) Minute\($0 > 1 ? "s" : "")" : nil }
        views.append(BannerBadge(text: AniListUtil.episodesText(for: item) ?? duration ?? "N/A",
                                 textColor: color, kind: .label))

        func addButton(_ text: String, color: UIColor, filter: BannerFilter) {
            let badge = BannerBadge(text: text, textColor: color, kind: .button)
            badge.addAction(UIAction { _ in onFilter(filter) }, for: .touchUpInside)
            views.append(badge)
        }

        // Both are there even when AniList does not know them: `format(current)` is 'N/A' then.
        addButton(AniListUtil.format(item.format), color: color, filter: .format(item.format))
        addButton(AniListUtil.status(item.status), color: color, filter: .status(item.status))

        // `class='capitalize'`
        if let seasonText = AniListUtil.seasonText(for: item) {
            addButton(seasonText.capitalized, color: color, filter: .season(item.season, item.year))
        }

        // `{#if current.averageScore}`, without `!text-custom`
        if let score = item.score, score > 0 {
            addButton(String(format: "%.0f%%", score), color: ratingColor(score), filter: .score)
        }
        return views
    }

    /// The genres at the right of the grid, every one, unwrapped (`flex-nowrap`).
    static func genreViews(for item: AnimeItem, color: UIColor, onFilter: @escaping (BannerFilter) -> Void) -> [UIView] {
        item.genres.map { genre in
            let badge = BannerBadge(text: genre, textColor: color, kind: .ghostButton)
            badge.addAction(UIAction { _ in onFilter(.genre(genre)) }, for: .touchUpInside)
            return badge
        }
    }
}
