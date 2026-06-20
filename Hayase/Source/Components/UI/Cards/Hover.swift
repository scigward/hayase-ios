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

    private override init() {
        super.init()
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
        card.configure(media: media, actions: actions)
        window.addSubview(card)

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
        card.animateIn()
    }

    func unhover(source: UIView? = nil) {
        if let source, activeSource !== source { return }
        unhoverLastElement()
    }

    func unhoverLastElement() {
        activeMediaID = nil
        activeSource = nil
        activeHost = nil
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
}

extension UIViewController {
    func hayasePreviewCardActions() -> PreviewCardActions {
        PreviewCardActions(
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

    private func presentHayasePreviewExtensionSearch(media: AnimeItem, episode: Int) {
        let searchVC = ExtensionSearchViewController()
        searchVC.animeItem = media
        searchVC.initialEpisode = episode

        if traitCollection.horizontalSizeClass == .regular {
            searchVC.modalPresentationStyle = .custom
            searchVC.transitioningDelegate = searchVC
        } else {
            searchVC.modalPresentationStyle = .fullScreen
        }

        guard var presenter = view.window?.rootViewController else {
            present(searchVC, animated: true)
            return
        }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(searchVC, animated: true)
    }
}
