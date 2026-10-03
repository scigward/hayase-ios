//
//  FullBanner+Layout.swift
//  Hayase
//
//  Mirrors: the Tailwind breakpoints of interface full-banner.svelte
//
//    sm (640)  the badge row shows
//    md (768)  the social block's `md:pt-14 md:pl-10`; the artwork is the backdrop of ani.zip
//    lg (1024) `grid-cols-2`: the description and the genres go to the right column, and the
//              title is `text-4xl`, left aligned
//

import UIKit

extension FullBannerCell {
    /// The width of the window's content, which Tailwind's breakpoints are measured against.
    var viewportWidth: CGFloat { window?.rootViewController?.view.bounds.width ?? bounds.width }

    func applyLayout(forWidth width: CGFloat) {
        let key = width >= 1024 ? 3 : (width >= 768 ? 2 : (width >= 640 ? 1 : 0))
        guard featuredLayoutKey != key else { return }
        featuredLayoutKey = key
        if let loaded = loadedBackdropArtwork, loaded != (width >= 768), let item = currentItem {
            // `$breakpoints.md` is reactive in banner.svelte; rotation or Split View can cross it.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentItem?.id == item.id else { return }
                self.loadBanner(for: item)
            }
        }

        let large = width >= 1024
        // grid-cols-1 lg:grid-cols-2; the right column is `self-end`
        columnsStack.axis = large ? .horizontal : .vertical
        columnsStack.alignment = large ? .bottom : .fill
        leftColumn.alignment = large ? .leading : .center           // lg:items-start
        titleLink.setLargeLayout(large)                              // lg:text-4xl lg:text-left

        // The description is `text-xs lg:text-sm`, centred and then right aligned, `line-clamp-2
        // lg:line-clamp-3`, and sits under the buttons until `lg` puts it in the right column.
        descriptionLabel.textAlignment = large ? .right : .center
        descriptionLabel.font = .nunito(ofSize: large ? 14 : 12)
        descriptionLabel.lineHeight = large ? 20 : 16
        descriptionLabel.numberOfLines = large ? 3 : 2
        if large {
            if descriptionLabel.superview !== rightColumn {
                leftColumn.removeArrangedSubview(descriptionLabel)
                descriptionLabel.removeFromSuperview()
                rightColumn.insertArrangedSubview(descriptionLabel, at: 0)
            }
            rightColumn.isHidden = false
            rightColumn.setCustomSpacing(16, after: descriptionLabel)   // pt-4 of the genres
        } else {
            if descriptionLabel.superview !== leftColumn {
                rightColumn.removeArrangedSubview(descriptionLabel)
                descriptionLabel.removeFromSuperview()
                leftColumn.addArrangedSubview(descriptionLabel)
            }
            rightColumn.isHidden = true
        }

        descriptionMaxWidthConstraint.isActive = false
        if large {
            // lg:max-w-[75%] of the right column's content box, which lg:pr-5 narrows by 20.
            descriptionMaxWidthConstraint = descriptionLabel.widthAnchor.constraint(
                lessThanOrEqualTo: rightColumn.widthAnchor, multiplier: 0.75, constant: -15)
        } else {
            descriptionMaxWidthConstraint = descriptionLabel.widthAnchor.constraint(
                lessThanOrEqualTo: columnsStack.widthAnchor, multiplier: 0.90)   // max-w-[90%]
        }
        descriptionMaxWidthConstraint.isActive = true

        // lg:pl-4 on the grid, lg:pr-5 inside the right column. Below lg the grid has no padding;
        // the title, description and buttons carry their own max-widths.
        columnsLeadingConstraint.constant = large ? 16 : 0
        rightColumn.directionalLayoutMargins = large ? NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 20) : .zero
        rightColumn.isLayoutMarginsRelativeArrangement = large

        badgeStack.isHidden = width < 640                    // hidden sm:flex
        followingTopConstraint.constant = width >= 768 ? 56 : 16        // md:pt-14
        followingLeadingConstraint.constant = width >= 768 ? 40 : 16    // md:pl-10
        if let item = currentItem {
            updateGenres(for: item, customColor: Self.uiColor(fromHex: item.coverColor) ?? .white)
        }
    }

    /// `text-balance` wraps at the narrowest width that keeps the lines, so each label is told how
    /// wide the element it stands for could be.
    func updateBalancedWidths() {
        titleLink.updateBalance(columnWidth: leftColumn.bounds.width)
        if viewportWidth >= 1024 {
            descriptionLabel.balanceMaxWidth = max(0, rightColumn.bounds.width * 0.75 - 15)
        } else {
            descriptionLabel.balanceMaxWidth = max(0, columnsStack.bounds.width * 0.90)
        }
    }
}
