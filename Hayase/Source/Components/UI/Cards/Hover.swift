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
    /// The preview that is up, for D-pad navigation to reach what is in it
    var previewView: UIView? { previewCard }
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
              actions: PreviewCardActions,
              trace: TraceAnime? = nil,
              alignsToCardStart: Bool = false) {
        cell.hoverProvider = { [weak host, weak cell] in
            guard let host, let cell, let media = mediaProvider() else { return }
            Hover.shared.hoverElement(source: cell, host: host, media: media, actions: actions, trace: trace,
                                      alignsToCardStart: alignsToCardStart)
        }
        cell.unhoverProvider = { [weak cell] in
            guard let cell else { return }
            Hover.shared.unhover(source: cell)
        }
    }

    func handleTouchSelection(source: UIView,
                              host: UIViewController,
                              media: AnimeItem,
                              actions: PreviewCardActions,
                              trace: TraceAnime? = nil,
                              alignsToCardStart: Bool = false) -> Bool {
        if activeMediaID == media.id, activeSource === source {
            unhoverLastElement()
            return false
        }
        hoverElement(source: source, host: host, media: media, actions: actions, trace: trace,
                     alignsToCardStart: alignsToCardStart)
        return true
    }

    func hoverElement(source: UIView,
                      host: UIViewController,
                      media: AnimeItem,
                      actions: PreviewCardActions,
                      trace: TraceAnime? = nil,
                      alignsToCardStart: Bool = false) {
        if activeMediaID == media.id, activeSource === source { return }
        guard let window = host.view.window ?? source.window else { return }
        unhoverLastElement()
        activeSource = source
        activeHost = host
        activeMediaID = media.id

        let card = PreviewCard()
        card.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(card)
        card.configure(media: media, actions: actions, trace: trace)

        let sourceFrame = source.convert(source.bounds, to: window)
        // query.svelte gives the first card of a page `left-36 md:left-1/2`: below `md` its preview
        // starts 4pt in from the card instead of being centred on it
        let centerX = alignsToCardStart && window.bounds.width < 768
            ? sourceFrame.minX + 144
            : sourceFrame.midX
        // `top-0 bottom-0 m-auto h-80`: centred on the card, which is a few points taller. Like
        // the interface's, it goes where it goes: a card at the edge of the screen shows a
        // preview that the edge cuts.
        let top = sourceFrame.minY + (sourceFrame.height - PreviewCard.size.height) / 2

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
        // `{#if !hidden && hoverable}`: the preview is gone the moment it is not hovered
        card.prepareForDismissal()
        card.removeFromSuperview()
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
                // play.svelte: `$status === 'COMPLETED' ? 1 : ($progressStore ?? 0) + 1`
                let entry = media.listEntry
                let episode = PlayButton.episode(listStatus: entry?.status, progress: entry?.progress)
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
                AniListTracking.shared.toggleBookmark(media: media, completion: completion)
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
