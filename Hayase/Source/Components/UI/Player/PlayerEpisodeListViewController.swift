//
//  PlayerEpisodeListViewController.swift
//  Hayase
//
//  Created by scigward.
//  Mirrors: lib/components/ui/player/episodesmodal.svelte
//           (`Sheet.Trigger` = the player's episode description →
//            `Sheet.Content` hosting `EpisodesList.svelte`)
//  Sheet shell mirrors: lib/components/ui/sheet/sheet-content.svelte +
//                       lib/components/ui/sheet/index.ts (side: 'right')
//

import UIKit

// MARK: - PlayerEpisodeListViewController

/// Right-side slide-in sheet that lists every episode of the anime currently
/// playing, reusing the very same episode cards the anime detail page renders.
///
/// interface episodesmodal.svelte:
/// ```
/// <Sheet.Content class='w-full sm:w-[550px] p-0 ... bg-background overflow-y-scroll'>
///   {#await Promise.all([eps(mediaInfo.media.id), client.single(mediaInfo.media.id)]) then [eps, media]}
///     <EpisodesList {eps} media={media.data.Media} class='!px-0 !py-3 xs:!p-3 sm:!p-6 !mx-0' />
///   {/await}
/// </Sheet.Content>
/// ```
/// The two awaited requests map to `AniZipService.episodes(anilistID:)` and
/// `AniListClient.fetchAnimePageResult(id:)`.
final class PlayerEpisodeListViewController: UIViewController {

    // MARK: - Sheet metrics (sheet-content.svelte / sheet/index.ts)

    /// interface: `Sheet.Content class='w-full sm:w-[550px]'`.
    static let contentWidth: CGFloat = 550
    /// Tailwind `sm` breakpoint — below it the sheet fills the container (`w-full`).
    static let compactWidthBreakpoint: CGFloat = 640
    /// interface `sheetTransitions.right.in = { x: '100%', duration: 500 }`.
    static let presentDuration: TimeInterval = 0.5
    /// interface `sheetTransitions.right.out = { x: '100%', duration: 300 }`.
    static let dismissDuration: TimeInterval = 0.3

    // MARK: - Input (set before presenting)

    /// AniList media id of the anime being played.
    var anilistID: Int = 0
    /// Episode currently playing — used to preselect the matching page.
    var currentEpisode: Int = 0
    /// Media already resolved by the player, used until AniList answers.
    var media: AnimeItem?
    /// Episode count the player already knows about, used when AniList has none.
    var totalEpisodesHint: Int = 0
    /// Fired after the sheet dismissed itself, mirroring web's `playEp(media, episode)`.
    var onSelectEpisode: ((_ episode: Int, _ media: AnimeItem?) -> Void)?
    /// Fired once the sheet finished dismissing (used to re-arm control auto-hide).
    var onDismiss: (() -> Void)?

    // MARK: - State

    /// interface EpisodesList.svelte: `const perPage = 16`.
    private let perPage = 16

    private var episodes: [AniZipEpisode] = []
    private var currentPage = 1
    private var anilistProgress = 0
    private var listStatus: String?
    private var accentColor: UIColor = .white
    private var followersByEpisode: [Int: [AniListUserSummary]] = [:]
    private var isLoading = true
    private var pendingHeightInvalidation = false
    private var panStartOriginX: CGFloat = 0
    private var hasScrolledToCurrentEpisode = false

    private enum Section: Int, CaseIterable {
        case episodes
        case pagination
    }

    private var paginatedEpisodes: [AniZipEpisode] {
        let start = (currentPage - 1) * perPage
        guard start >= 0, start < episodes.count else { return [] }
        let end = min(start + perPage, episodes.count)
        return Array(episodes[start..<end])
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(episodes.count) / Double(perPage))))
    }

    // MARK: - Views

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let paginationBar = PaginationBarView()
    private let spinner = UIActivityIndicatorView(style: .large)

    /// interface sheetVariants right side: `border-l`.
    private let leftBorder = UIView()

    /// interface sheet-content.svelte: `<SheetClose class='absolute right-4 top-4 ...'>`.
    private let closeButton = UIButton(type: .system)

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No episodes found."
        label.font = .nunito(ofSize: 14)
        label.textColor = UIColor.HayaseTheme.mutedForeground
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Presentation

    /// Configures the custom right-side sheet presentation.
    /// Mirrors `ExtensionSearchViewController.prepareOverlayPresentation(from:)`.
    func prepareSheetPresentation(from presenter: UIViewController?) {
        presenter?.definesPresentationContext = true
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    // MARK: - Chrome / orientation

    // The player runs landscape-only with a hidden status bar; inherit whatever
    // the presenter declares so opening the sheet never forces a rotation.
    override var prefersStatusBarHidden: Bool {
        presentingViewController?.prefersStatusBarHidden ?? false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        presentingViewController?.supportedInterfaceOrientations ?? .allButUpsideDown
    }

    override var shouldAutorotate: Bool {
        presentingViewController?.shouldAutorotate ?? true
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupDismissGesture()
        applyMediaState(media)
        loadEpisodes()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            onDismiss?()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The sheet is a narrow container inside a potentially very wide window,
        // so the pagination bar must size itself from the sheet, not the window.
        paginationBar.responsiveWidthOverride = view.bounds.width
    }

    private func setupViews() {
        // interface episodesmodal.svelte overrides the popover colour: `bg-background`.
        view.backgroundColor = UIColor.HayaseTheme.background
        view.clipsToBounds = true

        leftBorder.backgroundColor = UIColor.HayaseTheme.border
        leftBorder.translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsHorizontalScrollIndicator = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 140
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(EpisodeCell.self, forCellReuseIdentifier: EpisodeCell.reuseID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.paginationCellID)
        // interface class override on the list: `!px-0 !py-3 xs:!p-3 sm:!p-6`.
        // The top inset also clears the floating close button — the web sheet lets
        // the button overlap the list because it only appears on hover, but on
        // touch it would steal taps from the first card.
        tableView.contentInset = UIEdgeInsets(top: 52, left: 0, bottom: 24, right: 0)
        tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 52, left: 0, bottom: 24, right: 0)
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        closeButton.setImage(UIImage.hayaseIcon("x", pointSize: 16), for: .normal)
        closeButton.tintColor = UIColor.HayaseTheme.foreground
        // interface: `opacity-70 hover:opacity-100`, `rounded-sm`, `bg-secondary` when open.
        closeButton.alpha = 0.7
        closeButton.backgroundColor = UIColor.HayaseTheme.secondary.withAlphaComponent(0.7)
        closeButton.layer.cornerRadius = 4
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        paginationBar.onPageChange = { [weak self] page in
            self?.setPage(page)
        }

        view.addSubview(tableView)
        view.addSubview(leftBorder)
        view.addSubview(spinner)
        view.addSubview(emptyLabel)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            leftBorder.topAnchor.constraint(equalTo: view.topAnchor),
            leftBorder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftBorder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftBorder.widthAnchor.constraint(equalToConstant: 1),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // interface sheet-content.svelte: `absolute right-4 top-4`.
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private static let paginationCellID = "PlayerEpisodePaginationCell"

    // MARK: - Swipe to dismiss

    private func setupDismissGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        guard let container = view.superview else { return }
        switch gesture.state {
        case .began:
            panStartOriginX = view.frame.origin.x
        case .changed:
            let dx = max(0, gesture.translation(in: container).x)
            view.frame.origin.x = panStartOriginX + dx
        case .ended:
            let dx = max(0, gesture.translation(in: container).x)
            let velocity = gesture.velocity(in: container).x
            if dx > view.bounds.width / 3 || velocity > 800 {
                dismiss(animated: true)
            } else {
                snapBack()
            }
        case .cancelled, .failed:
            snapBack()
        default:
            break
        }
    }

    private func snapBack() {
        let target = panStartOriginX
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut], animations: {
            self.view.frame.origin.x = target
        }, completion: nil)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func setPage(_ page: Int) {
        let clamped = min(max(1, page), totalPages)
        guard clamped != currentPage else { return }
        currentPage = clamped
        hasScrolledToCurrentEpisode = true
        tableView.reloadData()
        if !paginatedEpisodes.isEmpty {
            tableView.scrollToRow(at: IndexPath(row: 0, section: Section.episodes.rawValue),
                                  at: .top, animated: false)
        }
    }

    /// interface EpisodesList.svelte: clicking an episode card calls `playEp(media, episode)`.
    /// The sheet closes first so playback starts on the uncovered player.
    private func selectEpisode(_ episode: Int) {
        let resolvedMedia = media
        let handler = onSelectEpisode
        dismiss(animated: true) {
            handler?(episode, resolvedMedia)
        }
    }

    private func scheduleHeightInvalidation() {
        guard !pendingHeightInvalidation else { return }
        pendingHeightInvalidation = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingHeightInvalidation = false
            guard self.isViewLoaded, self.view.window != nil else { return }
            UIView.performWithoutAnimation {
                self.tableView.beginUpdates()
                self.tableView.endUpdates()
            }
        }
    }

    // MARK: - Data

    private func applyMediaState(_ item: AnimeItem?) {
        guard let item else { return }
        anilistProgress = item.mediaListEntry?.progress ?? 0
        listStatus = item.mediaListEntry?.status
        if let accent = ExtensionSearchViewController.uiColor(fromHex: item.coverColor) {
            accentColor = accent
        }
    }

    /// Mirrors episodesmodal.svelte's `Promise.all([eps(id), client.single(id)])`.
    private func loadEpisodes() {
        guard anilistID > 0 else {
            finishLoading(with: [])
            return
        }

        let group = DispatchGroup()
        var anizipResponse: AniZipEpisodesResponse?
        var pagePayload: AnimePagePayload?

        group.enter()
        AniZipService.shared.episodes(anilistID: anilistID) { response in
            anizipResponse = response
            group.leave()
        }

        group.enter()
        AniListClient.shared.fetchAnimePageResult(id: anilistID) { result in
            switch result {
            case .success(let payload):
                pagePayload = payload
            case .failure(let error):
                NSLog("[PlayerEpisodeList] AnimePage failed: %@", error.description)
            }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            self?.handleFetched(anizip: anizipResponse, page: pagePayload)
        }
    }

    private func handleFetched(anizip: AniZipEpisodesResponse?, page: AnimePagePayload?) {
        if let fetchedMedia = page?.media {
            media = fetchedMedia
            Router.shared.cacheAnimeItem(fetchedMedia)
            applyMediaState(fetchedMedia)
        }
        if let entries = page?.followingEntries, !entries.isEmpty {
            followersByEpisode = Dictionary(grouping: entries, by: \.progress)
                .mapValues { $0.map(\.user) }
        }

        // AniZip has no data for brand new anime — build the list from the AniList
        // airing schedule instead. Matches web `makeEpisodeList(media, eps)` which
        // tolerates `eps == null`.
        let response = anizip ?? AniZipEpisodesResponse(
            titles: nil, episodes: nil, episodeCount: nil,
            specialCount: nil, images: nil, mappings: nil)

        var knownCount: Int? = media?.episodes
        if knownCount == nil, totalEpisodesHint > 0 {
            knownCount = totalEpisodesHint
        }
        if let knownCount {
            buildEpisodes(from: response, count: knownCount, schedule: nil)
            return
        }

        // Mirrors AnimeDetailViewController.computeEpisodeCount / web `episodes(media)`:
        // when AniList has no confirmed episode count, fall back to the airing
        // schedule, the user's progress and the episode already playing.
        _ = AniListClient.shared.fetchMediaAiringScheduleResult(anilistID: anilistID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                var schedule: [Int: Date] = [:]
                switch result {
                case .success(let value):
                    schedule = value.schedule
                case .failure(let error):
                    NSLog("[PlayerEpisodeList] Media schedule failed: %@", error.description)
                }
                let candidates = [schedule.keys.max() ?? 0, self.anilistProgress, self.currentEpisode]
                let best = candidates.max() ?? 0
                self.buildEpisodes(from: response, count: best > 0 ? best : nil, schedule: schedule)
            }
        }
    }

    private func buildEpisodes(from response: AniZipEpisodesResponse, count: Int?, schedule: [Int: Date]?) {
        let parsed = AnimeDetailViewController.buildEpisodeList(
            from: response,
            anilistEpisodes: count,
            alSchedule: schedule,
            fallbackRuntime: media?.duration)

        guard !parsed.isEmpty else {
            finishLoading(with: [])
            return
        }

        AnimeDetailViewController.loadFillerSet(for: anilistID) { fillerSet in
            let withFiller = parsed.map { ep in
                AniZipEpisode(number: ep.number, title: ep.title, overview: ep.overview,
                              imageURL: ep.imageURL, airDate: ep.airDate, runtime: ep.runtime,
                              rating: ep.rating, isFiller: fillerSet.contains(ep.number))
            }
            DispatchQueue.main.async { [weak self] in
                self?.finishLoading(with: withFiller)
            }
        }
    }

    private func finishLoading(with episodes: [AniZipEpisode]) {
        isLoading = false
        spinner.stopAnimating()
        spinner.isHidden = true
        self.episodes = episodes
        emptyLabel.isHidden = !episodes.isEmpty

        // interface EpisodesList.svelte: `let currentPage = Math.floor(progress / perPage) + 1`.
        // The player anchors on the episode being played when it is known.
        let anchor = max(currentEpisode > 0 ? currentEpisode - 1 : 0, anilistProgress)
        currentPage = min(max(1, anchor / perPage + 1), totalPages)

        tableView.reloadData()
        scrollToCurrentEpisodeIfNeeded()
    }

    private func scrollToCurrentEpisodeIfNeeded() {
        guard !hasScrolledToCurrentEpisode, currentEpisode > 0 else { return }
        guard let row = paginatedEpisodes.firstIndex(where: { $0.number == currentEpisode }) else { return }
        hasScrolledToCurrentEpisode = true
        tableView.layoutIfNeeded()
        tableView.scrollToRow(at: IndexPath(row: row, section: Section.episodes.rawValue),
                              at: .middle, animated: false)
    }
}

// MARK: - UITableViewDataSource / UITableViewDelegate

extension PlayerEpisodeListViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .episodes:
            return paginatedEpisodes.count
        case .pagination:
            return episodes.isEmpty ? 0 : 1
        case .none:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .episodes:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: EpisodeCell.reuseID, for: indexPath) as? EpisodeCell else {
                return UITableViewCell()
            }
            guard let episode = paginatedEpisodes[safe: indexPath.row] else { return cell }
            cell.configure(with: episode,
                           anilistID: anilistID,
                           anilistProgress: anilistProgress,
                           accentColor: accentColor,
                           isListCompleted: listStatus == "COMPLETED",
                           isRepeating: listStatus == "REPEATING",
                           hideSpoilers: Settings.hideSpoilers,
                           followers: followersByEpisode[episode.number] ?? [],
                           onHeightChange: { [weak self] in self?.scheduleHeightInvalidation() })
            cell.cardView.onTap = { [weak self] number in
                self?.selectEpisode(number)
            }
            // interface class override on the sheet list: `xs:!p-3` → 12pt gutters.
            // The sheet is never wide enough for the `xl:px-14` variant.
            cell.applyPageSideInset(AnimeDetailViewController.interfacePageSideInset(for: view.bounds.width))
            return cell

        case .pagination:
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.paginationCellID, for: indexPath)
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.selectionStyle = .none
            if paginationBar.superview !== cell.contentView {
                paginationBar.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(paginationBar)
                NSLayoutConstraint.activate([
                    paginationBar.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    paginationBar.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    paginationBar.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    paginationBar.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                ])
            }
            paginationBar.responsiveWidthOverride = view.bounds.width
            paginationBar.configure(currentPage: currentPage, totalCount: episodes.count, perPage: perPage)
            // The sheet never gets the anime page's wide gutters.
            paginationBar.applyPaddingForSizeClass(isRegular: false)
            return cell

        case .none:
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .episodes,
              let episode = paginatedEpisodes[safe: indexPath.row] else { return }
        selectEpisode(episode.number)
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        Section(rawValue: indexPath.section) == .pagination ? 60 : 140
    }
}

// MARK: - UIGestureRecognizerDelegate

extension PlayerEpisodeListViewController: UIGestureRecognizerDelegate {
    /// Only start the dismiss pan for a clearly rightwards horizontal swipe so the
    /// episode list keeps scrolling vertically.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return velocity.x > 0 && velocity.x > abs(velocity.y)
    }
}

// MARK: - UIViewControllerTransitioningDelegate

extension PlayerEpisodeListViewController: UIViewControllerTransitioningDelegate {

    func presentationController(forPresented presented: UIViewController,
                                presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        RightSideSheetPresentationController(presentedViewController: presented, presenting: presenting)
    }

    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        RightSideSheetAnimator(isPresenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        RightSideSheetAnimator(isPresenting: false)
    }
}

// MARK: - RightSideSheetPresentationController

/// Anchors the presented view to the trailing edge of the container, full height.
///
/// interface sheetVariants `side: 'right'` = `inset-y-0 right-0 h-full`, and the
/// dimmed backdrop mirrors sheet-overlay.svelte (`custom-bg` + `backdrop-blur-sm`,
/// click-to-close).
final class RightSideSheetPresentationController: UIPresentationController {

    private let dimmingView = HayaseStripedBackdropView(dimColor: UIColor.black.withAlphaComponent(0.55))

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView = containerView else { return .zero }
        let bounds = containerView.bounds
        // interface: `w-full sm:w-[550px]`.
        let width = bounds.width < PlayerEpisodeListViewController.compactWidthBreakpoint
            ? bounds.width
            : PlayerEpisodeListViewController.contentWidth
        return CGRect(x: bounds.maxX - width, y: bounds.minY, width: width, height: bounds.height)
    }

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView else { return }

        dimmingView.frame = containerView.bounds
        dimmingView.alpha = 0
        containerView.insertSubview(dimmingView, at: 0)

        // interface dialog-overlay.svelte: pointerdown on the overlay closes it.
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimmingTapped))
        dimmingView.addGestureRecognizer(tap)

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.dimmingView.alpha = 1
        })
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.dimmingView.alpha = 0
        })
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed {
            dimmingView.removeFromSuperview()
        } else {
            dimmingView.alpha = 1
        }
    }

    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        dimmingView.frame = containerView?.bounds ?? .zero
        // The animator owns the frame while sliding in/out, and the swipe-to-dismiss
        // gesture owns it while dragging. Only correct it for rotations/resizes.
        guard !presentedViewController.isBeingPresented,
              !presentedViewController.isBeingDismissed else { return }
        presentedView?.frame = frameOfPresentedViewInContainerView
    }

    @objc private func dimmingTapped() {
        presentedViewController.dismiss(animated: true)
    }
}

// MARK: - RightSideSheetAnimator

/// Slides the sheet in from / out to the trailing edge.
/// interface sheetTransitions.right: `in { x: '100%', duration: 500 }`,
/// `out { x: '100%', duration: 300 }` (svelte `fly` uses cubicOut easing).
final class RightSideSheetAnimator: NSObject, UIViewControllerAnimatedTransitioning {

    private let isPresenting: Bool

    init(isPresenting: Bool) {
        self.isPresenting = isPresenting
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        isPresenting
            ? PlayerEpisodeListViewController.presentDuration
            : PlayerEpisodeListViewController.dismissDuration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView
        let duration = transitionDuration(using: transitionContext)

        if isPresenting {
            guard let toController = transitionContext.viewController(forKey: .to) else {
                transitionContext.completeTransition(false)
                return
            }
            let candidate: UIView? = transitionContext.view(forKey: .to) ?? toController.view
            guard let sheet = candidate else {
                transitionContext.completeTransition(false)
                return
            }
            if sheet.superview == nil {
                container.addSubview(sheet)
            }
            let finalFrame = transitionContext.finalFrame(for: toController)
            sheet.frame = finalFrame.offsetBy(dx: finalFrame.width, dy: 0)
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.curveEaseOut, .allowUserInteraction],
                           animations: {
                sheet.frame = finalFrame
            }, completion: { _ in
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            })
        } else {
            let candidate: UIView? = transitionContext.view(forKey: .from)
                ?? transitionContext.viewController(forKey: .from)?.view
            guard let sheet = candidate else {
                transitionContext.completeTransition(false)
                return
            }
            let start = sheet.frame
            let target = CGRect(x: container.bounds.maxX, y: start.minY,
                                width: start.width, height: start.height)
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.curveEaseOut, .allowUserInteraction],
                           animations: {
                sheet.frame = target
            }, completion: { _ in
                let finished = !transitionContext.transitionWasCancelled
                if finished {
                    sheet.removeFromSuperview()
                }
                transitionContext.completeTransition(finished)
            })
        }
    }
}
