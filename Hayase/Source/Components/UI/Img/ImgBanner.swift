//
//  ImgBanner.swift
//  Hayase
//
//  Mirrors: interface components/ui/img/banner.svelte and the `episodesCached` logo of
//  full-banner.svelte
//
//  The banner picture is not the banner's: it goes to the route-level `BannerImageView` (and to
//  the sidebar). The logo is the banner's own.
//

import UIKit

extension FullBannerCell {
    /// img/load.svelte `sizes`: what YouTube offers below maxresdefault.
    private static let thumbnailSizes = ["sddefault", "hqdefault", "mqdefault", "default"]

    /// util.ts `banner()`: the banner image, else the trailer's thumbnail, else the cover.
    private static func bannerURL(for item: AnimeItem) -> String? {
        if let banner = item.bannerURL { return banner }
        if let trailer = item.trailerYouTubeID { return "https://i.ytimg.com/vi/\(trailer)/maxresdefault.jpg" }
        return item.coverURL
    }

    // MARK: Banner

    /// img/banner.svelte: from `md` up the banner is the ani.zip backdrop (else its poster,
    /// else `banner()`); below `md` it is the cover, without waiting for ani.zip.
    func loadBanner(for item: AnimeItem) {
        bannerTask?.cancel()
        bannerTask = nil
        fanartTask?.cancel()
        fanartTask = nil
        currentSidebarBackdropURL = nil
        onBackdropImageChanged?(nil, nil)
        // The sidebar's slice is keyed on the media too: it goes now, not once the image is known.
        publishSidebarBackdrop()
        bannerGeneration += 1
        let generation = bannerGeneration
        let usesBackdrop = viewportWidth >= 768
        loadedBackdropArtwork = usesBackdrop
        guard usesBackdrop else {
            presentBanner(item.coverURL ?? Self.bannerURL(for: item), item: item, generation: generation)
            return
        }
        AniListClient.fetchFanartURL(anilistID: item.id) { [weak self] fanartURL in
            guard let self, self.bannerGeneration == generation else { return }
            self.presentBanner(fanartURL ?? Self.bannerURL(for: item), item: item, generation: generation)
        }
    }

    private func presentBanner(_ urlString: String?, item: AnimeItem, generation: Int, thumbnailAttempt: Int = 0) {
        guard let urlString, let url = URL(string: urlString) else {
            onBackdropImageChanged?(nil, nil)
            return
        }
        currentSidebarBackdropURL = urlString
        onBackdropImageChanged?(urlString, nil)
        publishSidebarBackdrop(urlString: urlString,
                               scrollOffset: 0,
                               alpha: bannerHidden ? BannerImage.hiddenAlpha : 1)
        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            onBackdropImageChanged?(urlString, cached)
            return
        }
        fanartTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.bannerGeneration == generation,
                      self.currentSidebarBackdropURL == urlString else { return }
                // img/load.svelte verifyThumbnail: a YouTube size that does not exist is
                // answered with a 120x90 placeholder, so step down to a smaller one.
                if urlString.hasPrefix("https://i.ytimg.com/"),
                   image.size == CGSize(width: 120, height: 90),
                   thumbnailAttempt < Self.thumbnailSizes.count,
                   let video = item.trailerYouTubeID {
                    let smaller = "https://i.ytimg.com/vi/\(video)/\(Self.thumbnailSizes[thumbnailAttempt]).jpg"
                    self.presentBanner(smaller, item: item, generation: generation,
                                       thumbnailAttempt: thumbnailAttempt + 1)
                    return
                }
                SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
                self.onBackdropImageChanged?(urlString, image)
            }
        }
        fanartTask?.resume()
    }

    // MARK: Logo

    /// Fetches the logo (transparent title art) from ani.zip for the current item.
    /// If found, displays it and hides the text title. Otherwise keeps the text.
    /// Matches full-banner.svelte:
    ///   `{#await episodesCached(current.id) then metadata}`
    /// Highest-voted English TMDB logo with aspect ratio greater than 1.2.
    func loadClearlogo(for item: AnimeItem) {
        clearlogoTask?.cancel()
        clearlogoTask = nil
        let itemID = item.id
        let generation = artworkGeneration
        AniListClient.fetchClearlogoURL(anilistID: itemID) { [weak self] clearlogoURL in
            guard let self, self.artworkGeneration == generation else { return }
            // The interface inserts the logo here; only an image ready within the 300ms
            // `load-in` animation still shows its blur.
            let inserted = CACurrentMediaTime()
            // Make sure we're still displaying the same item (rotation may have advanced)
            guard self.currentItem?.id == itemID else { return }
            guard let urlStr = clearlogoURL, let url = URL(string: urlStr) else {
                // No logo: the text title
                DispatchQueue.main.async { self.showTitleText(forItemID: itemID, generation: generation) }
                return
            }
            if let cached = SharedImageCache.shared.object(forKey: urlStr as NSString) {
                self.showClearlogo(cached, forItemID: itemID, blurred: true)
                return
            }
            self.clearlogoTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = UIImage(data: data) else {
                    // Download failed: the text title
                    DispatchQueue.main.async { self?.showTitleText(forItemID: itemID, generation: generation) }
                    return
                }
                SharedImageCache.shared.setObject(image, forKey: urlStr as NSString)
                DispatchQueue.main.async {
                    guard self?.artworkGeneration == generation else { return }
                    self?.showClearlogo(image, forItemID: itemID,
                                        blurred: CACurrentMediaTime() - inserted < LoadIn.blurWindow)
                }
            }
            self.clearlogoTask?.resume()
        }
    }

    private func showTitleText(forItemID itemID: Int, generation: Int) {
        guard artworkGeneration == generation, currentItem?.id == itemID else { return }
        titleLink.titleLabel.isHidden = false
    }

    private func showClearlogo(_ image: UIImage, forItemID: Int, blurred: Bool) {
        guard currentItem?.id == forItemID else { return }
        clearlogoAspectConstraint?.isActive = false
        clearlogoAspectConstraint = titleLink.logoView.heightAnchor.constraint(
            equalTo: titleLink.logoView.widthAnchor,
            multiplier: image.size.height / max(image.size.width, 1)
        )
        clearlogoAspectConstraint?.priority = UILayoutPriority(999)
        clearlogoAspectConstraint?.isActive = true
        titleLink.logoView.isHidden = false
        titleLink.titleLabel.isHidden = true
        LoadIn.show(image, in: titleLink.logoView, blurred: blurred)
    }

    // MARK: Sidebar

    /// The height of the picture behind the route: `h-[80vh] md:h-[90vh]`, of which the banner is
    /// `h-[70vh] md:h-[80vh]`.
    private var backdropHeight: CGFloat {
        let wide = viewportWidth >= 768
        if contentView.bounds.height > 0 {
            return contentView.bounds.height * (wide ? 90.0 / 80.0 : 80.0 / 70.0)
        }
        return UIScreen.main.bounds.height * (wide ? 0.90 : 0.80)
    }

    /// Sends the sidebar this banner's state again. The interface's sidebar reads the same
    /// `bannerSrc` and `hideBanner` stores as the page; here it keeps a copy that the page shown
    /// in between (an anime page scrolled past its banner) may have left hidden.
    func republishSidebarBackdrop() {
        guard let urlString = currentSidebarBackdropURL else { return }
        publishSidebarBackdrop(urlString: urlString, scrollOffset: 0,
                               alpha: bannerHidden ? BannerImage.hiddenAlpha : 1)
    }

    /// `hideBanner.value = scrollTop > 100`
    func setBannerHidden(_ hidden: Bool) {
        guard hidden != bannerHidden else { return }
        bannerHidden = hidden
        publishSidebarBackdrop(urlString: currentSidebarBackdropURL,
                               alpha: hidden ? BannerImage.hiddenAlpha : 1)
    }

    private func publishSidebarBackdrop(urlString: String? = nil, scrollOffset: CGFloat? = nil, alpha: CGFloat? = nil) {
        BannerBackdrop.post(height: backdropHeight,
                            mediaID: currentItem?.id,
                            urlString: urlString,
                            scrollOffset: scrollOffset,
                            alpha: alpha)
    }
}
