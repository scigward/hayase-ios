//
//  ScheduleTooltip.swift
//  Hayase
//
//  Mirrors: interface components/ui/tooltip (`bg-primary text-primary-foreground rounded-md px-3
//  py-1.5 text-xs`, `flyAndScale` over 150ms, `sideOffset={4}`) as the schedule page uses it:
//  `openDelay={100}`, `sameWidth`, over an episode (its cover) or over "+ n more..." (the episodes
//  left over).
//

import UIKit

final class ScheduleTooltip {
    static let shared = ScheduleTooltip()

    private weak var tooltip: ScheduleTooltipView?
    private weak var anchor: UIView?
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?

    private init() {}

    /// Over an episode: its `coverImage.extraLarge`, on its `color`, with no padding.
    func showCover(for episode: ScheduleAiringEpisode, from anchor: UIView) {
        present(from: anchor) { width in
            ScheduleTooltipView(cover: episode.coverURL, color: episode.coverColor, width: width)
        }
    }

    /// Over "+ n more...": the episodes past the fifth, as links.
    func showEpisodes(_ episodes: [ScheduleAiringEpisode], extraLarge: Bool, from anchor: UIView,
                      onSelect: @escaping (Int) -> Void) {
        present(from: anchor) { width in
            ScheduleTooltipView(episodes: episodes, extraLarge: extraLarge, width: width) { [weak self] id in
                self?.hide()
                onSelect(id)
            }
        }
    }

    func scheduleHide() {
        showWork?.cancel()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        // The pointer may be on its way into the tooltip, which stays while it is over it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func cancelHide() {
        hideWork?.cancel()
    }

    func hide() {
        showWork?.cancel()
        hideWork?.cancel()
        guard let tooltip else { return }
        self.tooltip = nil
        anchor = nil
        UIView.animate(withDuration: 0.15, animations: {
            tooltip.alpha = 0
            tooltip.transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.95, y: 0.95)
        }, completion: { _ in tooltip.removeFromSuperview() })
    }

    private func present(from anchor: UIView, make: @escaping (CGFloat) -> ScheduleTooltipView) {
        hideWork?.cancel()
        if self.anchor === anchor, tooltip != nil { return }
        showWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak anchor] in
            guard let self, let anchor, let window = anchor.window else { return }
            if let old = self.tooltip {
                old.removeFromSuperview()
                self.tooltip = nil
            }
            let frame = anchor.convert(anchor.bounds, to: window)
            let view = make(frame.width)
            let size = view.fittingSize
            // Above the trigger, `sideOffset` 4 away, and below it when there is no room above.
            var y = frame.minY - 4 - size.height
            if y < window.safeAreaInsets.top { y = frame.maxY + 4 }
            let x = min(max(frame.minX, 4), window.bounds.width - size.width - 4)
            view.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.95, y: 0.95)
            view.onHover = { [weak self] hovering in
                if hovering { self?.cancelHide() } else { self?.scheduleHide() }
            }
            window.addSubview(view)
            UIView.animate(withDuration: 0.15) {
                view.alpha = 1
                view.transform = .identity
            }
            self.tooltip = view
            self.anchor = anchor
        }
        showWork = work
        // openDelay={100}
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
}

final class ScheduleTooltipView: UIView {
    var onHover: ((Bool) -> Void)?
    private(set) var fittingSize = CGSize.zero

    private init(width: CGFloat) {
        super.init(frame: .zero)
        backgroundColor = UIColor.HayaseTheme.primary
        layer.cornerRadius = 6
        clipsToBounds = true
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        fittingSize.width = width
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        onHover?(recognizer.state == .began || recognizer.state == .changed)
    }

    /// The cover, at the trigger's width and as tall as it is.
    convenience init(cover: String?, color: String?, width: CGFloat) {
        self.init(width: width)
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = ExtensionSearchViewController.uiColor(fromHex: color) ?? UIColor.HayaseTheme.muted
        var ratio: CGFloat = 1.5
        if let cover, let cached = SharedImageCache.shared.object(forKey: cover as NSString), cached.size.width > 0 {
            imageView.image = cached
            ratio = cached.size.height / cached.size.width
        } else if let cover, let url = URL(string: cover) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                SharedImageCache.shared.setObject(image, forKey: cover as NSString)
                DispatchQueue.main.async {
                    imageView.image = image
                    imageView.alpha = 0
                    UIView.animate(withDuration: 0.3) { imageView.alpha = 1 }
                }
            }.resume()
        }
        let height = ceil(width * ratio)
        imageView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        addSubview(imageView)
        fittingSize = CGSize(width: width, height: height)
    }

    /// The remaining episodes: `px-3 py-1.5`, `gap-1.5` between rows.
    convenience init(episodes: [ScheduleAiringEpisode], extraLarge: Bool, width: CGFloat,
                     onSelect: @escaping (Int) -> Void) {
        self.init(width: width)
        var y: CGFloat = 6
        for (index, episode) in episodes.enumerated() {
            let row = ScheduleEpisodeRow(episode: episode, style: .overflow, extraLarge: extraLarge)
            row.onSelect = { onSelect(episode.mediaID) }
            row.frame = CGRect(x: 12, y: y, width: max(0, width - 24), height: 16)
            addSubview(row)
            y += 16 + (index == episodes.count - 1 ? 0 : 6)
        }
        fittingSize = CGSize(width: width, height: y + 6)
    }
}
