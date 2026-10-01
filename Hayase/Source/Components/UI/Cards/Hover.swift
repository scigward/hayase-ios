//
//  Hover.swift
//  Hayase
//
//  Mirrors interface modules/navigate.ts hover behavior for card previews.
//

import UIKit

final class Hover: NSObject {
    static let shared = Hover()

    private weak var activeSource: UIView?
    private weak var activeHost: UIViewController?
    private var previewCard: PreviewCard?
    private var activeMediaID: Int?
    private var activeSourceFrameInWindow: CGRect = .null
    private var sourceTracker: CADisplayLink?

    private override init() {
        super.init()
        // Preview media has no reason to keep decoding while the app is inactive,
        // or after a memory/power change. Reopening re-evaluates effect support.
        for notification in [UIApplication.willResignActiveNotification,
                             UIApplication.didReceiveMemoryWarningNotification,
                             Notification.Name.NSProcessInfoPowerStateDidChange] {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(suspendPreview(_:)),
                                                   name: notification,
                                                   object: nil)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        sourceTracker?.invalidate()
    }

    @objc private func suspendPreview(_ notification: Notification) {
        if Thread.isMainThread {
            unhoverLastElement()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.unhoverLastElement()
            }
        }
    }

    func bind(to cell: AnimeCollectionViewCell,
              host: UIViewController,
              mediaProvider: @escaping () -> AnimeItem?,
              actions: PreviewCardActions) {
        cell.hoverProvider = { [weak host, weak cell] in
            guard let host, let cell, let media = mediaProvider() else { return }
            Hover.shared.hoverElement(source: cell, host: host, media: media, actions: actions)
        }
        cell.unhoverProvider = { [weak cell] in
            guard let cell else { return }
            Hover.shared.unhover(source: cell)
        }
    }

    func handleTouchSelection(source: UIView,
                              host: UIViewController,
                              media: AnimeItem,
                              actions: PreviewCardActions) -> Bool {
        if activeMediaID == media.id, activeSource === source {
            unhoverLastElement()
            return false
        }
        hoverElement(source: source, host: host, media: media, actions: actions)
        return true
    }

    func hoverElement(source: UIView,
                      host: UIViewController,
                      media: AnimeItem,
                      actions: PreviewCardActions) {
        if activeMediaID == media.id, activeSource === source { return }
        guard let window = host.view.window ?? source.window else { return }
        unhoverLastElement()
        activeSource = source
        activeHost = host
        activeMediaID = media.id

        let card = PreviewCard()
        card.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(card)
        card.configure(media: media, actions: actions)

        let sourceFrame = source.convert(source.bounds, to: window)
        let centerX = min(max(sourceFrame.midX, PreviewCard.size.width / 2),
                          window.bounds.width - PreviewCard.size.width / 2)
        let top = min(max(sourceFrame.minY, 8),
                      window.bounds.height - PreviewCard.size.height - 8)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: window.leadingAnchor, constant: centerX),
            card.topAnchor.constraint(equalTo: window.topAnchor, constant: top),
        ])
        previewCard = card
        activeSourceFrameInWindow = sourceFrame
        startTrackingSourceFrame()
        card.animateIn()
    }

    func unhover(source: UIView? = nil) {
        if let source, activeSource !== source { return }
        unhoverLastElement()
    }

    func unhoverLastElement() {
        stopTrackingSourceFrame()
        activeMediaID = nil
        activeSource = nil
        activeHost = nil
        activeSourceFrameInWindow = .null
        guard let card = previewCard else { return }
        previewCard = nil
        card.prepareForDismissal()
        UIView.animate(withDuration: 0.18, animations: {
            card.alpha = 0
            card.transform = CGAffineTransform(translationX: 0, y: 10).scaledBy(x: 0.98, y: 0.98)
        }, completion: { _ in
            card.removeFromSuperview()
        })
    }

    func scrollDidOccur() {
        unhoverLastElement()
    }

    func dragDidOccur() {
        unhoverLastElement()
    }

    private func startTrackingSourceFrame() {
        stopTrackingSourceFrame()
        let link = CADisplayLink(target: self, selector: #selector(checkActiveSourceFrame))
        link.add(to: .main, forMode: .common)
        sourceTracker = link
    }

    private func stopTrackingSourceFrame() {
        sourceTracker?.invalidate()
        sourceTracker = nil
    }

    @objc private func checkActiveSourceFrame() {
        guard let source = activeSource,
              let host = activeHost,
              let window = source.window,
              host.view.window === window else {
            unhoverLastElement()
            return
        }

        // Reused cells and hidden route ancestors can remain in the same window
        // without changing their frame. They must not retain an active trailer.
        if let cell = source as? AnimeCollectionViewCell,
           cell.configuredAnimeItem?.id != activeMediaID {
            unhoverLastElement()
            return
        }
        var ancestor: UIView? = source
        while let view = ancestor {
            if view.isHidden || view.alpha <= 0 {
                unhoverLastElement()
                return
            }
            if view === window { break }
            ancestor = view.superview
        }

        let frame = source.convert(source.bounds, to: window)
        guard frame.intersects(window.bounds) else {
            unhoverLastElement()
            return
        }

        if !activeSourceFrameInWindow.isNull {
            let dx = abs(frame.midX - activeSourceFrameInWindow.midX)
            let dy = abs(frame.midY - activeSourceFrameInWindow.midY)
            if dx > 3 || dy > 3 {
                unhoverLastElement()
            }
        }
    }

}

extension UIViewController {
    func hayasePreviewCardActions() -> PreviewCardActions {
        PreviewCardActions(
            open: { [weak self] media in
                self?.openHayasePreviewAnime(media)
            },
            play: { [weak self] media in
                guard let self else { return }
                let status = media.mediaListEntry?.status
                let episode: Int
                if status == "COMPLETED" {
                    episode = 1
                } else {
                    episode = (media.mediaListEntry?.progress ?? 0) + 1
                }
                self.presentHayasePreviewExtensionSearch(media: media, episode: episode)
            },
            favorite: { media, completion in
                guard media.id > 0 else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                AniListTracking.shared.toggleFavourite(mediaID: media.id) { success in
                    DispatchQueue.main.async { completion(success) }
                }
            },
            bookmark: { media, completion in
                guard media.id > 0 else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                AniListTracking.shared.fetchMediaWithEntry(anilistID: media.id) { entry, _, _, _, _ in
                    if let listID = entry?.listID {
                        AniListTracking.shared.deleteEntry(listID: listID, mediaID: media.id) { success in
                            DispatchQueue.main.async { completion(success) }
                        }
                    } else {
                        AniListTracking.shared.entry(mediaID: media.id, status: "PLANNING") { entry in
                            DispatchQueue.main.async { completion(entry != nil) }
                        }
                    }
                }
            })
    }

    private func openHayasePreviewAnime(_ media: AnimeItem) {
        Hover.shared.unhoverLastElement()
        Router.shared.navigateToAnime(media, hostTabIndex: hayaseTabIndex)
    }

    private func presentHayasePreviewExtensionSearch(media: AnimeItem, episode: Int) {
        Hover.shared.unhoverLastElement()
        let searchVC = ExtensionSearchViewController()
        searchVC.animeItem = media
        searchVC.initialEpisode = episode

        guard var presenter = view.window?.rootViewController else {
            searchVC.prepareOverlayPresentation(from: self)
            present(searchVC, animated: true)
            return
        }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        searchVC.prepareOverlayPresentation(from: presenter)
        presenter.present(searchVC, animated: true)
    }
}
