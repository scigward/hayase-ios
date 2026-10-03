//
//  HomePage+Banner.swift
//  Hayase
//
//  Mirrors: `handleScroll` of interface routes/app/home/+page.svelte
//
//      function handleScroll (e: Event) {
//        const target = e.target as HTMLDivElement
//        hideBanner.value = target.scrollTop > 100
//      }
//      hideBanner.value = false
//
//  `hideBanner` is what banner-image.svelte reads to fade the picture to 5%. The picture here is
//  drawn behind the route, and a cover of the page's background hides it while the page is scrolled
//  past: a card row's gaps would otherwise show the faint picture through them.
//

import UIKit

extension HomeViewController {
    /// Applies the banner scroll effects based on the current contentOffset.
    /// Must be called any time the scroll position or the banner cell could be stale:
    ///   • from scrollViewDidScroll (every scroll event)
    ///   • from viewWillAppear (returning from a child VC — scrollViewDidScroll won't re-fire)
    ///   • after reloadData() (prepareForReuse resets the cell; the scroll event won't re-fire)
    func syncBannerToCurrentScrollPosition() {
        let offsetY = collectionView.contentOffset.y
        let bannerCell = collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? FullBannerCell

        if offsetY < 0 {
            // A real pull-down is an intentional reveal. Apply it immediately.
            cancelPendingBannerReveal()
            applyBannerVisibility(hidden: false, bannerCell: bannerCell)
            return
        }

        if offsetY > BannerImage.hideThreshold {
            // Hide immediately. The cover is a bleed-prevention mask, so it must
            // not spend frames half-transparent while rows are already over it.
            cancelPendingBannerReveal()
            applyBannerVisibility(hidden: true, bannerCell: bannerCell)
        } else if shouldRevealBannerImmediately(offsetY: offsetY) {
            cancelPendingBannerReveal()
            applyBannerVisibility(hidden: false, bannerCell: bannerCell)
        } else {
            // UIKit can chatter around 100 during rebound/deceleration. Do not
            // start a visible fade-in unless the scroll position stays on the
            // visible side of the threshold for a short moment.
            scheduleBannerRevealIfNeeded()
        }
    }

    /// A banner that is not on screen starts over the next time it is configured.
    func remountFeaturedBanner() {
        selectedFeaturedID = nil
        (collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? FullBannerCell)?.remount()
    }

    private func shouldRevealBannerImmediately(offsetY: CGFloat) -> Bool {
        guard offsetY > 0 else { return true }
        if collectionView.isDragging {
            return collectionView.panGestureRecognizer.velocity(in: collectionView).y > 0
        }
        return !collectionView.isDecelerating && !collectionView.isTracking
    }

    private func applyBannerVisibility(hidden: Bool, bannerCell: FullBannerCell?) {
        bannerCell?.setBannerHidden(hidden)
        transitionBackdropCover(hidden: hidden)
    }

    private func scheduleBannerRevealIfNeeded() {
        guard pendingBannerRevealWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingBannerRevealWorkItem = nil
            guard self.collectionView.contentOffset.y <= BannerImage.hideThreshold else { return }
            let bannerCell = self.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? FullBannerCell
            self.applyBannerVisibility(hidden: false, bannerCell: bannerCell)
        }
        pendingBannerRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + bannerRevealDelay, execute: workItem)
    }

    private func cancelPendingBannerReveal() {
        pendingBannerRevealWorkItem?.cancel()
        pendingBannerRevealWorkItem = nil
    }

    /// `transition-opacity duration-500` of the banner image, as the fade of the cover.
    private func transitionBackdropCover(hidden: Bool) {
        let targetCoverAlpha: CGFloat = hidden ? 1 : 0
        guard hidden != isBackdropCovered || abs(backdropCoverView.alpha - targetCoverAlpha) > 0.001 else { return }

        backdropCoverTransitionID += 1
        let transitionID = backdropCoverTransitionID
        isBackdropCovered = hidden

        if hidden {
            // Fade the mask itself instead of fading the gradient under a
            // semi-transparent mask. Once fully covered, park the backdrop at
            // its hidden alpha behind the mask so card gaps stay protected.
            backdropView.setFaded(false, animated: false)
            BannerImage.fade([backdropCoverView], to: 1) { [weak self] in
                guard let self, self.backdropCoverTransitionID == transitionID else { return }
                self.backdropView.setFaded(true, animated: false)
            }
        } else {
            // Prepare the full banner while it is still hidden by the mask, then
            // fade only the mask away. This avoids exposing an animating radial
            // gradient/cropped image during upward threshold crossings.
            backdropView.setFaded(false, animated: false)
            BannerImage.fade([backdropCoverView], to: 0)
        }
    }
}
