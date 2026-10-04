//
//  Castplayer.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/player/castplayer.svelte: while the video is cast to a display the player shows
//  "Now Casting" with the title, the episode, the time and the controls, and the displays are asked for on a timer.
//

import AVKit
import CoreMedia
import UIKit
import UniformTypeIdentifiers

extension VideoPlayerViewController {
    /// Mirrors: hayase-app/interface/src/lib/components/ui/player/castplayer.svelte
    /// (non-miniplayer branch) and episodesmodal.svelte. `$breakpoints['4xs']`
    /// is `(min-width: 280px)` — true on every iOS device — so the buttons
    /// always use the 4xs-true sizing (size-12/24px icons/h-12 text-lg), never
    /// the non-4xs fallback.
    func setupNowCastingView() {
        nowCastingContainer.translatesAutoresizingMaskIntoConstraints = false
        nowCastingContainer.backgroundColor = UIColor.HayaseTheme.background   // bg-background
        nowCastingContainer.isHidden = true
        view.addSubview(nowCastingContainer)

        nowCastingTitleLabel.text = "Now Casting"
        nowCastingTitleLabel.textColor = UIColor.HayaseTheme.foreground
        nowCastingTitleLabel.font = .nunito(ofSize: 24, weight: .bold)   // text-2xl font-bold
        nowCastingTitleLabel.numberOfLines = 1   // line-clamp-1

        // episodesmodal.svelte title div: text-lg font-normal, text-shadow-lg —
        // shadow parameters match Hayase's existing titleLabel approximation
        // of the same three-layer text-shadow-lg (same component, same look).
        nowCastingAnimeTitleButton.setTitleColor(UIColor.HayaseTheme.foreground, for: .normal)
        nowCastingAnimeTitleButton.titleLabel?.font = .nunito(ofSize: 18, weight: .regular)   // text-lg font-normal
        nowCastingAnimeTitleButton.titleLabel?.numberOfLines = 1   // line-clamp-1
        nowCastingAnimeTitleButton.titleLabel?.lineBreakMode = .byTruncatingTail
        nowCastingAnimeTitleButton.contentHorizontalAlignment = .leading
        nowCastingAnimeTitleButton.titleLabel?.layer.shadowColor = UIColor.black.cgColor
        nowCastingAnimeTitleButton.titleLabel?.layer.shadowOffset = .zero
        nowCastingAnimeTitleButton.titleLabel?.layer.shadowOpacity = 0.8
        nowCastingAnimeTitleButton.titleLabel?.layer.shadowRadius = 3
        nowCastingAnimeTitleButton.addTarget(self, action: #selector(titleTapped), for: .touchUpInside)

        // episodesmodal.svelte Sheet.Trigger: text-[rgba(217,217,217,0.6)]
        // text-sm font-light, text-shadow-lg — not muted-foreground, a
        // distinct literal color (see UIColor.HayaseTheme.castMutedText).
        nowCastingEpisodeButton.setTitleColor(UIColor.HayaseTheme.castMutedText, for: .normal)
        nowCastingEpisodeButton.titleLabel?.font = .nunito(ofSize: 14, weight: .light)   // text-sm font-light
        nowCastingEpisodeButton.titleLabel?.numberOfLines = 1   // line-clamp-1
        nowCastingEpisodeButton.titleLabel?.lineBreakMode = .byTruncatingTail
        nowCastingEpisodeButton.contentHorizontalAlignment = .leading
        nowCastingEpisodeButton.titleLabel?.layer.shadowColor = UIColor.black.cgColor
        nowCastingEpisodeButton.titleLabel?.layer.shadowOffset = .zero
        nowCastingEpisodeButton.titleLabel?.layer.shadowOpacity = 0.8
        nowCastingEpisodeButton.titleLabel?.layer.shadowRadius = 3
        nowCastingEpisodeButton.addTarget(self, action: #selector(episodeLabelTapped), for: .touchUpInside)

        // `ml-auto self-end ... mt-3` — right-aligned within the full-width
        // column, no text-shadow-lg here (only the two episodesmodal lines get it).
        nowCastingTimeLabel.textColor = UIColor.HayaseTheme.foreground
        nowCastingTimeLabel.font = .nunito(ofSize: 14, weight: .light)   // text-sm font-light
        nowCastingTimeLabel.textAlignment = .right

        // `relative w-full h-1 ... rounded-[2px]` wrapping two absolutely
        // positioned h-0.5 bars; absolute children with no top/bottom ignore
        // the parent's items-center, keeping their static (top) position.
        nowCastingProgressContainer.clipsToBounds = true
        nowCastingProgressContainer.layer.cornerRadius = 2   // rounded-[2px]
        nowCastingProgressTrack.backgroundColor = UIColor.HayaseTheme.castProgressTrack
        nowCastingProgressFill.backgroundColor = UIColor.HayaseTheme.primary   // bg-primary
        nowCastingProgressContainer.addSubview(nowCastingProgressTrack)
        nowCastingProgressContainer.addSubview(nowCastingProgressFill)

        nowCastingErrorLabel.textColor = UIColor.HayaseTheme.castError   // text-red-500
        nowCastingErrorLabel.font = .nunito(ofSize: 14, weight: .light)   // text-sm font-light
        nowCastingErrorLabel.numberOfLines = 0   // whitespace-pre-wrap — a stack trace can wrap multiple lines
        nowCastingErrorLabel.isHidden = true

        nowCastingStopButton.setImage(UIImage.hayaseFilledIcon("square", pointSize: 24), for: .normal)   // size='24px' fill='currentColor'
        nowCastingStopButton.addTarget(self, action: #selector(stopCastingTapped), for: .touchUpInside)

        nowCastingPrevButton.setImage(UIImage.hayaseFilledIcon("skip-back", pointSize: 24), for: .normal)   // fill='currentColor' strokeWidth='1'
        nowCastingPrevButton.tintColor = UIColor.HayaseTheme.foreground
        nowCastingPrevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)

        nowCastingNextButton.setImage(UIImage.hayaseFilledIcon("skip-forward", pointSize: 24), for: .normal)
        nowCastingNextButton.tintColor = UIColor.HayaseTheme.foreground
        nowCastingNextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        nowCastingPlaylistButton.setTitle("Playlist", for: .normal)   // px-8 h-12 text-lg font-bold py-0
        nowCastingPlaylistButton.titleLabel?.font = .nunito(ofSize: 18, weight: .bold)
        nowCastingPlaylistButton.setTitleColor(UIColor.HayaseTheme.foreground, for: .normal)
        nowCastingPlaylistButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 32, bottom: 0, right: 32)
        nowCastingPlaylistButton.setContentHuggingPriority(.required, for: .horizontal)   // don't stretch — only the trailing spacer does
        nowCastingPlaylistButton.addTarget(self, action: #selector(nowCastingPlaylistTapped), for: .touchUpInside)

        // `flex w-full pt-3 gap-2` — left-packed, not stretched or spread;
        // a trailing spacer (low hugging) absorbs the rest of the row's width.
        let trailingSpacer = UIView()
        nowCastingControlsRow.axis = .horizontal
        nowCastingControlsRow.spacing = 8   // gap-2
        nowCastingControlsRow.alignment = .center
        nowCastingControlsRow.distribution = .fill
        [nowCastingStopButton, nowCastingPrevButton, nowCastingPlaylistButton, nowCastingNextButton, trailingSpacer]
            .forEach { nowCastingControlsRow.addArrangedSubview($0) }

        nowCastingColumn.axis = .vertical
        nowCastingColumn.spacing = 8   // gap-2
        nowCastingColumn.alignment = .fill   // text-left; flex-col default align-items:stretch
        [nowCastingTitleLabel, nowCastingAnimeTitleButton, nowCastingEpisodeButton,
         nowCastingTimeLabel, nowCastingProgressContainer, nowCastingErrorLabel, nowCastingControlsRow].forEach {
            nowCastingColumn.addArrangedSubview($0)
        }
        nowCastingColumn.setCustomSpacing(16, after: nowCastingTitleLabel)          // gap-2 + mb-2
        nowCastingColumn.setCustomSpacing(20, after: nowCastingEpisodeButton)       // gap-2 + mt-3 (on the label after)
        nowCastingColumn.setCustomSpacing(20, after: nowCastingProgressContainer)   // gap-2 + pt-3 (on the row after)
        nowCastingColumn.setCustomSpacing(20, after: nowCastingErrorLabel)          // same, when {:catch} replaces time+progress
        nowCastingContainer.addSubview(nowCastingColumn)

        [nowCastingColumn, nowCastingProgressContainer, nowCastingProgressTrack, nowCastingProgressFill,
         nowCastingControlsRow, nowCastingStopButton, nowCastingPrevButton, nowCastingPlaylistButton,
         nowCastingNextButton, trailingSpacer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        let fillWidth = nowCastingProgressFill.widthAnchor.constraint(equalTo: nowCastingProgressContainer.widthAnchor, multiplier: 0)
        nowCastingProgressFillWidth = fillWidth

        NSLayoutConstraint.activate([
            nowCastingColumn.centerXAnchor.constraint(equalTo: nowCastingContainer.centerXAnchor),
            nowCastingColumn.centerYAnchor.constraint(equalTo: nowCastingContainer.centerYAnchor),
            nowCastingColumn.widthAnchor.constraint(lessThanOrEqualToConstant: 320),   // max-w-[320px]
            nowCastingColumn.leadingAnchor.constraint(greaterThanOrEqualTo: nowCastingContainer.leadingAnchor, constant: 32),   // px-8
            nowCastingColumn.trailingAnchor.constraint(lessThanOrEqualTo: nowCastingContainer.trailingAnchor, constant: -32),

            nowCastingProgressContainer.heightAnchor.constraint(equalToConstant: 4),   // h-1
            nowCastingProgressTrack.leadingAnchor.constraint(equalTo: nowCastingProgressContainer.leadingAnchor),
            nowCastingProgressTrack.trailingAnchor.constraint(equalTo: nowCastingProgressContainer.trailingAnchor),
            nowCastingProgressTrack.topAnchor.constraint(equalTo: nowCastingProgressContainer.topAnchor),
            nowCastingProgressTrack.heightAnchor.constraint(equalToConstant: 2),   // h-0.5
            nowCastingProgressFill.leadingAnchor.constraint(equalTo: nowCastingProgressContainer.leadingAnchor),
            nowCastingProgressFill.topAnchor.constraint(equalTo: nowCastingProgressContainer.topAnchor),
            nowCastingProgressFill.heightAnchor.constraint(equalToConstant: 2),   // h-0.5
            fillWidth,

            nowCastingStopButton.widthAnchor.constraint(equalToConstant: 48),   // size-12
            nowCastingStopButton.heightAnchor.constraint(equalToConstant: 48),
            nowCastingPrevButton.widthAnchor.constraint(equalToConstant: 48),
            nowCastingPrevButton.heightAnchor.constraint(equalToConstant: 48),
            nowCastingNextButton.widthAnchor.constraint(equalToConstant: 48),
            nowCastingNextButton.heightAnchor.constraint(equalToConstant: 48),
            nowCastingPlaylistButton.heightAnchor.constraint(equalToConstant: 48),   // h-12
        ])
        NSLayoutConstraint.activate([
            nowCastingContainer.topAnchor.constraint(equalTo: view.topAnchor),
            nowCastingContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nowCastingContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nowCastingContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Starts polling the WebTorrent bridge for Chromecast/DLNA displays.
    /// Mirrors `native.getDisplays(cb)` in native.ts, which on interface's
    /// real (non-browser) desktop build is backed by the same
    /// listenDisplay()/chromecasts+dlnas discovery this bridge now exposes —
    /// polled here since our transport is request/response, not push.
    /// Interval matches the actual rescan cadence in torrent-client's
    /// ChromeCasts/DLNAs classes (`setInterval(() => this.update(), 1 * 60 *
    /// 1000)` in both) — polling faster than the source itself refreshes
    /// would just re-fetch the same list.
    func startCastDisplaysTimer() {
        castDisplaysTimer?.invalidate()
        guard isWebTorrentPlayback else { return }
        updateCastDisplays()
        let timer = Timer(timeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.updateCastDisplays()
        }
        RunLoop.main.add(timer, forMode: .common)
        castDisplaysTimer = timer
    }

    func updateCastDisplays() {
        TorrentBackendManager.shared.webTorrentListDisplays { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let displays) = result else { return }
                self.webTorrentDisplays = displays
            }
        }
    }

    /// MIME type for the cast receiver's `contentType`. Hayase doesn't have
    /// a shared extension→MIME helper elsewhere yet, so this stays local and
    /// narrow — it only needs to cover the containers WebTorrent playback
    /// actually serves.
    func castContentType(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "mp4", "m4v": return "video/mp4"
        default: return "application/octet-stream"
        }
    }

    /// Mirrors: hayase-app/interface/src/lib/components/ui/player/castplayer.svelte
    /// `actualMedia` (lines 76-99) — same field set, same source per field:
    /// contentId/contentType/customData come from the file being cast, not
    /// from AniList; metadata.title/subtitle come from the session (anime
    /// title/episode description), duration is intentionally the anime's
    /// AniList-reported duration, not the actual file's real duration (see
    /// castDurationSeconds below).
    func castMediaPayload() -> [String: Any]? {
        guard let entity = videoEntity,
              let contentId = entity.videoLanPath ?? entity.videoPath else { return nil }

        let metadata: [String: Any] = [
            "metadataType": 2,
            "posterUrl": entity.torrents?.animes?.animeImgL ?? "",
            "title": animeTitleText(),
            "seriesTitle": animeTitleText(),
            "subtitle": episodeDescriptionText(),
            "episodeTitle": episodeDescriptionText(),
            "episode": episodeNumber,
            "episodeNumber": episodeNumber,
        ]

        return [
            "contentId": contentId,
            "contentType": castContentType(forPath: entity.videoName ?? contentId),
            "metadata": metadata,
            "customData": [
                "hash": entity.torrents?.torrentHashString ?? "",
                "id": entity.videoIndex?.intValue ?? Int(fileIndex),
                "audioLanguage": Settings.audioLanguage,
                "subtitleLanguage": Settings.subtitleLanguage,
            ],
            "streamType": "BUFFERED",
            "mediaCategory": "VIDEO",
        ]
    }

    /// `(mediaInfo.media.duration ?? 24) * 60` — the anime's AniList duration
    /// in minutes, not the real file duration. The cast device reports no
    /// position back to us, so this — like web — is a fiction used only to
    /// size the progress bar and to feed checkCompletion's threshold.
    func castDurationSeconds() -> Double {
        Double((currentResolvedVideo?.media?.duration ?? 24) * 60)
    }

    func startCasting(to display: WebTorrentDisplay) {
        guard let media = castMediaPayload() else { return }
        let hash = videoEntity?.torrents?.torrentHashString ?? ""
        let id = videoEntity?.videoIndex?.intValue ?? Int(fileIndex)

        activeCastDisplay = display
        nowCastingAnimeTitleButton.setTitle(animeTitleText(), for: .normal)
        nowCastingEpisodeButton.setTitle(episodeDescriptionText(), for: .normal)
        nowCastingPrevButton.isEnabled = prevButton.isEnabled
        nowCastingNextButton.isEnabled = nextButton.isEnabled
        nowCastingErrorLabel.isHidden = true
        nowCastingTimeLabel.isHidden = false
        nowCastingProgressContainer.isHidden = false
        nowCastingContainer.isHidden = false
        surface.mpv.pausePlayback()
        startCastElapsedTimer()

        TorrentBackendManager.shared.webTorrentPlayDisplay(host: display.host, hash: hash, id: id, media: media) { [weak self] result in
            guard let self, case .failure(let error) = result else { return }
            DispatchQueue.main.async {
                guard self.activeCastDisplay == display else { return }
                self.showCastError(error.localizedDescription)
            }
        }
    }

    /// {:catch error} — the time/progress area is replaced by the error text; the rest of the
    /// screen (title, EpisodesModal, Stop/Prev/Playlist/Next) stays exactly as-is, no auto-dismiss.
    func showCastError(_ message: String) {
        castElapsedTimer?.invalidate()
        nowCastingTimeLabel.isHidden = true
        nowCastingProgressContainer.isHidden = true
        nowCastingErrorLabel.isHidden = false
        nowCastingErrorLabel.text = message
    }

    /// `const elapsed = writable(0, set => setInterval(() => set((Date.now() -
    /// startTime) / 1000), 1000))` — reuses currentTime/duration/
    /// checkCompletion so AniList progress tracking behaves identically to
    /// local playback (see checkCompletion above), just fed a clock instead
    /// of MPV's real position.
    func startCastElapsedTimer() {
        castElapsedTimer?.invalidate()
        castStartTime = Date()
        castDuration = castDurationSeconds()
        updateCastElapsedUI()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCastElapsedUI()
        }
        RunLoop.main.add(timer, forMode: .common)
        castElapsedTimer = timer
    }

    func updateCastElapsedUI() {
        guard let castStartTime else { return }
        let elapsed = min(Date().timeIntervalSince(castStartTime), castDuration)
        nowCastingTimeLabel.text = "\(fmtTime(elapsed)) / \(fmtTime(castDuration))"
        let progress = castDuration > 0 ? CGFloat(elapsed / castDuration) : 0
        nowCastingProgressFillWidth?.isActive = false
        nowCastingProgressFillWidth = nowCastingProgressFill.widthAnchor.constraint(
            equalTo: nowCastingProgressContainer.widthAnchor, multiplier: min(max(progress, 0), 1))
        nowCastingProgressFillWidth?.isActive = true
        checkCompletion(currentTime: elapsed, duration: castDuration)
        onCastTick?(elapsed, castDuration)
    }

    func stopCasting() {
        guard let display = activeCastDisplay else { return }
        activeCastDisplay = nil
        castElapsedTimer?.invalidate()
        castElapsedTimer = nil
        castStartTime = nil
        nowCastingContainer.isHidden = true
        surface.mpv.play()
        TorrentBackendManager.shared.webTorrentCloseDisplay(host: display.host) { _ in }
    }

    @objc func stopCastingTapped() {
        stopCasting()
    }

    /// Mirrors: hayase-app/interface/src/lib/components/ui/player/castplayer.svelte
    /// Dialog.Root/Dialog.Content (lines 131-144) via CastPlaylistDialog.
    @objc func nowCastingPlaylistTapped() {
        let videos = playlistVideos
        guard !videos.isEmpty else { return }
        let items = videos.map { video in
            CastPlaylistDialog.Item(title: video.videoName ?? "Untitled") { [weak self] in
                self?.selectPlaylistVideo(video)
            }
        }
        let dialog = CastPlaylistDialog(items: items)
        present(dialog, animated: true)
    }

    var activeCastDisplay: WebTorrentDisplay? {
        didSet { onCastStateChanged?() }
    }

    /// MiniPlayerManager reads these to build the miniplayer's own
    /// castplayer.svelte `isMiniplayer` branch — it can't reuse this VC's
    /// view once minimized (reparented into a different window), so it
    /// needs the state and a tick callback instead.
    var isCasting: Bool { activeCastDisplay != nil }

    var activeCastDisplayName: String? { activeCastDisplay?.friendlyName }
}

// MARK: - CastPlaylistDialog

//  Created by scigward.
//

// Mirrors: hayase-app/interface/src/lib/components/ui/dialog/dialog-overlay.svelte
// and dialog-content.svelte, as instantiated by castplayer.svelte's Playlist
// Dialog.Root/Dialog.Content (lines 131-144) and button/index.ts's `ghost`
// button variant for each row. Scoped to this one call site — Hayase has no
// general-purpose ui/dialog port yet, and building one wasn't what this
// feature needed. Backdrop reuses HayaseStripeLayer.swift's existing
// custom-bg implementation rather than a new one.

final class CastPlaylistDialog: UIViewController {
    struct Item {
        let title: String
        let action: () -> Void
    }

    private let items: [Item]
    private var itemActions: [() -> Void] = []

    // dialog-overlay.svelte: `custom-bg` + `backdrop-blur-sm`, no extra dim
    // tint in that CSS — HayaseStripeLayer.swift already implements the
    // exact `custom-bg` gradient (and bundles the blur with it), reused here
    // rather than rebuilt.
    private let backdrop = HayaseStripedBackdropView()
    private let dismissGestureView = UIView()

    // dialog-content.svelte base classes merged with castplayer.svelte's
    // override: bg-background (base bg-popover overridden), border-4
    // (base border overridden), p-10 py-6, max-w-5xl (base max-w-lg
    // overridden), w-auto below md/w-full at md: and up (base w-full,
    // not overridden), rounded-xl, gap-4, items-center flex flex-col,
    // max-h-[calc(100%-1rem)], overflow-y-auto, shadow-lg (base, not
    // overridden).
    private let card = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    // Dialog.Close: `absolute right-4 top-4 rounded-sm`, Cross2 `size-4`.
    private let closeButton = UIButton(type: .system)
    private var cardStretchWidth: NSLayoutConstraint?

    private var cardTransform: CGAffineTransform {
        CGAffineTransform(scaleX: 0.95, y: 0.95).translatedBy(x: 0, y: -8)   // flyAndScale defaults: start 0.95, y -8
    }

    init(items: [Item]) {
        self.items = items
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — CastPlaylistDialog is only created programmatically")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupBackdrop()
        setupCard()
        populateItems()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        card.alpha = 0
        card.transform = cardTransform
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {   // duration: 200 (castplayer.svelte override)
            self.card.alpha = 1
            self.card.transform = .identity
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // `md:w-full` (base, not overridden by castplayer.svelte): at >=768px
        // the card stretches to fill its container (capped by max-w-5xl)
        // instead of hugging content.
        let shouldStretch = view.bounds.width >= 768
        if cardStretchWidth == nil {
            let constraint = card.widthAnchor.constraint(greaterThanOrEqualTo: view.widthAnchor, constant: -16)
            constraint.priority = .required
            cardStretchWidth = constraint
        }
        cardStretchWidth?.isActive = shouldStretch
    }

    private func dismiss(animated: Bool) {
        guard animated else {
            dismiss(animated: false, completion: nil)
            return
        }
        UIView.animate(withDuration: 0.15, animations: {   // dialog-overlay.svelte fade: duration 150
            self.card.alpha = 0
            self.card.transform = self.cardTransform
            self.backdrop.alpha = 0
        }, completion: { _ in
            self.dismiss(animated: false, completion: nil)
        })
    }

    private func setupBackdrop() {
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)

        dismissGestureView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dismissGestureView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
        dismissGestureView.addGestureRecognizer(tap)

        for v in [backdrop, dismissGestureView] {
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: view.topAnchor),
                v.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
    }

    @objc private func backdropTapped() {
        dismiss(animated: true)
    }

    private func setupCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.HayaseTheme.background   // bg-background
        card.layer.borderWidth = 4   // border-4
        card.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        card.layer.cornerRadius = 12   // rounded-xl
        card.layer.masksToBounds = false
        // shadow-lg (base, not overridden): approximated as one CALayer
        // shadow — CSS's two-layer box-shadow has no direct CALayer
        // equivalent, so this uses the dominant (larger) of the two.
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.1
        card.layer.shadowRadius = 7.5
        card.layer.shadowOffset = CGSize(width: 0, height: 10)
        view.addSubview(card)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false   // *::-webkit-scrollbar { display: none }
        scrollView.clipsToBounds = true
        card.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16   // gap-4
        stack.alignment = .center   // items-center — buttons size to content, not stretched
        scrollView.addSubview(stack)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage.hayaseIcon("x", pointSize: 16), for: .normal)   // Cross2 (radix-icons) size-4=16px; lucide "x" is the closest bundled equivalent
        closeButton.tintColor = UIColor.HayaseTheme.foreground
        closeButton.layer.cornerRadius = 2   // rounded-sm
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        card.addSubview(closeButton)

        let widthConstraint = card.widthAnchor.constraint(lessThanOrEqualToConstant: 1024)   // max-w-5xl = 64rem

        // The card has no intrinsic height (a UIScrollView's frame doesn't
        // follow its content); hug the content up to the max-h cap, then let
        // the scroll view take over. 64 = 8+8 outer margin + 24+24 (py-6).
        let hugContent = scrollView.heightAnchor.constraint(equalTo: stack.heightAnchor)
        hugContent.priority = .defaultHigh
        let maxHeight = scrollView.heightAnchor.constraint(
            lessThanOrEqualTo: view.heightAnchor, constant: -64)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            widthConstraint,
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 8),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -8),
            // max-h-[calc(100%-1rem)]: 1rem (16pt) total headroom, split top/bottom.
            card.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 8),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),

            closeButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),   // top-4
            closeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),   // right-4
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            scrollView.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),   // py-6
            scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 40),   // p-10 (horizontal)
            scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -40),
            hugContent,
            maxHeight,
            card.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 24),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func populateItems() {
        for item in items {
            // button/index.ts `ghost` variant: base h-9 px-4 py-2 text-sm
            // font-medium (GhostButton handles rounded-md + the select:
            // press state + disabled:opacity-50; only the size-specific
            // bits are set here).
            let button = GhostButton(type: .system)
            button.setTitle(item.title, for: .normal)
            button.setTitleColor(UIColor.HayaseTheme.foreground, for: .normal)
            button.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)   // text-sm font-medium
            button.titleLabel?.lineBreakMode = .byTruncatingTail   // text-ellipsis text-nowrap overflow-clip
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)   // py-2 px-4
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true   // h-9
            button.addTarget(self, action: #selector(playlistItemTapped(_:)), for: .touchUpInside)
            itemActions.append(item.action)
            button.tag = itemActions.count - 1
            stack.addArrangedSubview(button)
        }
    }

    @objc private func playlistItemTapped(_ sender: UIButton) {
        guard itemActions.indices.contains(sender.tag) else { return }
        let action = itemActions[sender.tag]
        dismiss(animated: true)
        action()
    }
}
