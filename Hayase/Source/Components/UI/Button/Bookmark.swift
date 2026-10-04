//
//  Bookmark.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/button/bookmark.svelte: the icon is filled (`fill='currentColor'`) while the media
//  is on one of the viewer's lists, and wobbles when it is pressed (`animated-icon`).
//

import UIKit

enum BookmarkButton {
    static let iconAnimation: SelectButton.IconAnimation = .wobble

    static func icon(isOnList: Bool, pointSize: CGFloat = 16) -> UIImage? {
        isOnList ? UIImage.hayaseFilledIcon("bookmark", pointSize: pointSize) : UIImage.hayaseIcon("bookmark", pointSize: pointSize)
    }
}
