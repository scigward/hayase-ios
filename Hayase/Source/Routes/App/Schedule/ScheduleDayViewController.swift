//
//  ScheduleDayViewController.swift
//  Hayase
//
//  Mirrors: the Drawer of interface routes/app/schedule/+page.svelte (vaul-svelte with
//  `shouldScaleBackground`), whose content is drawer-content.svelte, a Header holding only the
//  close button and a Footer holding the day's episodes.
//

import UIKit

final class ScheduleDayViewController: UIViewController, UIGestureRecognizerDelegate {
    private let episodes: [ScheduleAiringEpisode]
    private let extraLarge: Bool
    private let select: (Int) -> Void
    private let backdrop = HayaseStripedBackdropView()
    private let panel = UIView()
    private let border = UIView()
    private let scroll = UIScrollView()
    private let rows = UIStackView()
    private let closeButton = HayaseCloseButton(style: .sheet)
    private var isDismissing = false

    /// vaul's transition: 0.5s, cubic-bezier(0.32, 0.72, 0, 1).
    private static let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.32, y: 0.72),
                                                        controlPoint2: CGPoint(x: 0, y: 1))
    private static let duration: TimeInterval = 0.5

    init(episodes: [ScheduleAiringEpisode], extraLarge: Bool, select: @escaping (Int) -> Void) {
        self.episodes = episodes
        self.extraLarge = extraLarge
        self.select = select
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(backdrop)
        backdrop.alpha = 0
        backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        panel.backgroundColor = UIColor.HayaseTheme.background
        panel.accessibilityViewIsModal = true
        // shadow-2xl: 0 25px 50px -12px rgb(0 0 0 / 0.25)
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.25
        panel.layer.shadowRadius = 25
        panel.layer.shadowOffset = CGSize(width: 0, height: 25)
        view.addSubview(panel)
        border.backgroundColor = UIColor.HayaseTheme.border.withAlphaComponent(0.6)   // border-t-border/60 border-t-4
        panel.addSubview(border)
        panel.addSubview(scroll)
        scroll.alwaysBounceVertical = false
        rows.axis = .vertical
        rows.spacing = 14   // the footer's gap-2 and each row's mt-1.5
        rows.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(rows)
        for episode in episodes {
            let row = ScheduleEpisodeRow(episode: episode, style: .drawer, extraLarge: extraLarge)
            row.onSelect = { [weak self] in
                guard let self else { return }
                self.dismissDrawer { self.select(episode.mediaID) }
            }
            rows.addArrangedSubview(row)
        }
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 6),   // mt-1.5
            rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 12),   // px-3
            rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -12),
            rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            rows.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -24),
        ])
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        panel.addSubview(closeButton)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.delegate = self
        panel.addGestureRecognizer(pan)
    }

    /// The drawer: its border, the header (`p-4`, nothing in it) and the footer (`p-4`, `gap-2`).
    private var panelHeight: CGFloat {
        let count = CGFloat(episodes.count)
        let content = 4 + 32 + 16 + 16 + (count > 0 ? count * 22 + (count - 1) * 8 : 0)
        // `mt-24` above it
        return min(max(0, view.bounds.height - 96), content + view.safeAreaInsets.bottom)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
        let height = panelHeight
        if !isDismissing, !isDragging {
            panel.frame = CGRect(x: 0, y: view.bounds.height - height, width: view.bounds.width, height: height)
        }
        border.frame = CGRect(x: 0, y: 0, width: panel.bounds.width, height: 4)
        // absolute right-4 top-4 inside the border
        closeButton.frame = CGRect(x: panel.bounds.width - 32, y: 20, width: 16, height: 16)
        scroll.frame = CGRect(x: 16, y: 52, width: max(0, panel.bounds.width - 32),
                              height: max(0, height - 52 - 16 - view.safeAreaInsets.bottom))
    }

    // MARK: - vaul

    /// `shouldScaleBackground`: the page behind sits scaled to the width less 26px, down by the
    /// safe area and 14px, with rounded corners.
    private var pageView: UIView? { view.window?.rootViewController?.view }

    private func scalePage(_ progress: CGFloat) {
        guard let page = pageView, let window = view.window else { return }
        window.backgroundColor = .black   // html: !bg-black
        let width = window.bounds.width
        let scale = 1 - (1 - (width - 26) / width) * progress
        let offset = (window.safeAreaInsets.top + 14) * progress
        let lift = -(1 - scale) * page.bounds.height / 2
        page.layer.cornerRadius = 8 * progress
        page.clipsToBounds = true
        page.transform = CGAffineTransform(translationX: 0, y: offset + lift).scaledBy(x: scale, y: scale)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animate(opening: true)
    }

    private func animate(opening: Bool, completion: (() -> Void)? = nil) {
        let height = panel.bounds.height
        if opening { panel.transform = CGAffineTransform(translationX: 0, y: height) }
        let changes = {
            self.panel.transform = opening ? .identity : CGAffineTransform(translationX: 0, y: height)
            self.backdrop.alpha = opening ? 1 : 0
            self.scalePage(opening ? 1 : 0)
        }
        guard !UIAccessibility.isReduceMotionEnabled else {
            changes()
            completion?()
            return
        }
        let animator = UIViewPropertyAnimator(duration: Self.duration, timingParameters: Self.timing)
        animator.addAnimations(changes)
        animator.addCompletion { _ in completion?() }
        animator.startAnimation()
    }

    private func dismissDrawer(completion: (() -> Void)? = nil) {
        guard !isDismissing else { return }
        isDismissing = true
        animate(opening: false) { [weak self] in
            self?.pageView?.layer.cornerRadius = 0
            self?.pageView?.clipsToBounds = false
            self?.dismiss(animated: false, completion: completion)
        }
    }

    private var isDragging = false

    @objc private func drag(_ pan: UIPanGestureRecognizer) {
        let height = max(panel.bounds.height, 1)
        let offset = max(0, pan.translation(in: view).y)
        switch pan.state {
        case .began:
            isDragging = true
        case .changed:
            panel.transform = CGAffineTransform(translationX: 0, y: offset)
            let progress = 1 - min(offset / height, 1)
            backdrop.alpha = progress
            scalePage(progress)
        case .ended, .cancelled:
            isDragging = false
            // closeThreshold 0.25, velocity above 0.4px/ms
            let velocity = pan.velocity(in: view).y / 1000
            if offset / height > 0.25 || velocity > 0.4 {
                dismissDrawer()
            } else {
                animate(opening: true)
            }
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        // Down, and from the top of the list.
        return velocity.y > abs(velocity.x) && scroll.contentOffset.y <= 0
    }

    @objc private func close() { dismissDrawer() }
    override func accessibilityPerformEscape() -> Bool { close(); return true }
}
