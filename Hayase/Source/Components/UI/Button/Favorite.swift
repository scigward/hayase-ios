//
//  Favorite.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/button/favorite.svelte: the icon is filled (`fill='currentColor'`) while the media
//  is one of the viewer's favourites, and beats like a heart when it is pressed (`animated-icon`).
//

import UIKit

enum FavoriteButton {
    static let iconAnimation: SelectButton.IconAnimation = .heartBeat

    static func icon(isFavorite: Bool, pointSize: CGFloat = 16) -> UIImage? {
        isFavorite ? UIImage.hayaseFilledIcon("heart", pointSize: pointSize) : UIImage.hayaseIcon("heart", pointSize: pointSize)
    }
}
