//
//  Preview.swift
//  Hayase
//
//  Mirrors interface cards/preview.svelte.
//

import UIKit

struct PreviewCardActions {
    let open: (AnimeItem) -> Void
    let play: (AnimeItem) -> Void
    let favorite: (AnimeItem, @escaping (Bool) -> Void) -> Void
    let bookmark: (AnimeItem, @escaping (Bool) -> Void) -> Void
}

final class PreviewCard: UIView, UIGestureRecognizerDelegate {
    static let size = CGSize(width: 280, height: 320)

    private let bannerContainer: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.isOpaque = false
        v.clipsToBounds = true
        v.layer.cornerRadius = 4
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        return v
    }()

    private let bannerGlow = PreviewAmbientGlowView(
        bannerSize: CGSize(width: PreviewCard.size.width, height: PreviewCard.size.height * 0.45)
    )
    private let bodyBackground: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.HayaseTheme.muted
        view.layer.cornerRadius = 4
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.isUserInteractionEnabled = false
        return view
    }()

    private let bannerImageView: UIImageView = {
        let iv = UIImageView()
        iv.backgroundColor = UIColor.HayaseTheme.background
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        return iv
    }()

    private let bannerGradient: PreviewBannerGradientView = {
        let view = PreviewBannerGradientView()
        view.isUserInteractionEnabled = false
        return view
    }()
    private let youtubeIframe = YoutubeIframe()
    private let videoframe = Videoframe()

    // `text-lg font-bold truncate inline-block w-full text-foreground pt-2`: 18pt on a line of 28pt
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    // PlayButton (size xs: h-[1.6rem] rounded-sm px-2 text-xs) and, ghost, size icon-sm
    // (size-[1.6rem] rounded-sm), the FavoriteButton and the BookmarkButton
    private let playButton = SelectButton()
    private let favoriteButton = SelectButton()
    private let bookmarkButton = SelectButton()

    // `details text-foreground capitalize pt-3 pb-2 flex text-[11px] overflow-clip text-nowrap`: no ellipsis
    private let detailsLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 1
        l.lineBreakMode = .byClipping
        return l
    }()

    // `text-[.7rem] text-muted-foreground line-clamp-4`
    private let descriptionLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 4
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    /// `h-[1.6rem]` and `size-[1.6rem]`
    private static let buttonSize: CGFloat = 25.6

    private var media: AnimeItem?
    /// The frame a trace.moe lookup matched: its picture and clip stand in for the banner and trailer.
    private var trace: TraceAnime?
    private var actions: PreviewCardActions?
    private var imageTask: URLSessionDataTask?
    private var currentImageURL: String?
    private var bannerLoadToken = 0
    private var effectsEnabled = false
    private var isDismissed = false
    private var isFavorite = false
    private var isBookmarked = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { prepareForDismissal() }
    }

    private func setup() {
        // The glow must escape the card. Only the foreground banner and body
        // have rounded surfaces; clipping this root cuts off the ambient light.
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        isUserInteractionEnabled = true

        [bannerGlow, youtubeIframe.ambientView, bannerContainer, bodyBackground].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        [bannerImageView, videoframe, youtubeIframe, bannerGradient].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            bannerContainer.addSubview($0)
        }

        let buttonRow = UIStackView(arrangedSubviews: [playButton, favoriteButton, bookmarkButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .center
        buttonRow.distribution = .fill
        playButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        favoriteButton.setContentHuggingPriority(.required, for: .horizontal)
        bookmarkButton.setContentHuggingPriority(.required, for: .horizontal)

        let contentStack = UIStackView(arrangedSubviews: [titleLabel, buttonRow, detailsLabel, descriptionLabel])
        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.setCustomSpacing(12, after: buttonRow)    // pt-3 of the details
        contentStack.setCustomSpacing(8, after: detailsLabel)  // pb-2
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        configureButtons()
        configureCardTap()
        configureFrameCallbacks()

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size.width),
            heightAnchor.constraint(equalToConstant: Self.size.height),

            bannerContainer.topAnchor.constraint(equalTo: topAnchor),
            bannerContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerContainer.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.45),

            bodyBackground.topAnchor.constraint(equalTo: bannerContainer.bottomAnchor),
            bodyBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            bodyBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            bodyBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: bannerContainer.bottomAnchor, constant: 8),   // pt-2 of the title
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),              // px-4
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            playButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            favoriteButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            favoriteButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            bookmarkButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            bookmarkButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
        ])

        [bannerGlow, youtubeIframe.ambientView, bannerImageView, videoframe, youtubeIframe, bannerGradient].forEach {
            NSLayoutConstraint.activate([
                $0.topAnchor.constraint(equalTo: bannerContainer.topAnchor),
                $0.leadingAnchor.constraint(equalTo: bannerContainer.leadingAnchor),
                $0.trailingAnchor.constraint(equalTo: bannerContainer.trailingAnchor),
                $0.bottomAnchor.constraint(equalTo: bannerContainer.bottomAnchor),
            ])
        }

        transform = CGAffineTransform(translationX: 0, y: 19.2).scaledBy(x: 0.95, y: 0.95)
        alpha = 0
    }


    private func configureFrameCallbacks() {
        youtubeIframe.onHide = { [weak self] hidden in
            self?.setBackdropBlurHidden(!hidden)
        }
        videoframe.onHide = { [weak self] hidden in
            // no blurred copy of the clip here, so the picture's glow stays behind it
            self?.setBackdropBlurHidden(!hidden, keepsGlow: true)
        }
    }

    private func setBackdropBlurHidden(_ hidden: Bool, keepsGlow: Bool = false) {
        bannerGlow.isHidden = !effectsEnabled || (hidden && !keepsGlow)
        // Reveal the already-playing foreground beneath the banner, rather than
        // hiding the image abruptly or fading both layers through the page below.
        // Interface keeps its banner mounted underneath the fading trailer.
        if hidden {
            UIView.animate(withDuration: 0.3, delay: 0,
                           options: [.beginFromCurrentState, .curveEaseInOut]) {
                self.bannerImageView.alpha = 0
            }
        } else {
            bannerImageView.layer.removeAllAnimations()
            bannerImageView.alpha = 1
        }
    }

    private func configureButtons() {
        // default variant: bg-primary text-primary-foreground select:bg-primary/60 shadow
        playButton.applyPrimaryVariant()
        playButton.layer.cornerRadius = 2   // rounded-sm
        playButton.titleLabel?.font = .nunito(ofSize: 12, weight: .bold)   // text-xs font-bold
        // Play fill='currentColor' class='mr-2' size={iconSizes.xs}: 0.6rem and 8pt before the text
        playButton.setImage(UIImage.hayaseFilledIcon("play", pointSize: 9.6), for: .normal)
        playButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        playButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        // ghost: select:bg-secondary-foreground/20 select:text-accent-foreground, and the animated icon
        [favoriteButton, bookmarkButton].forEach {
            $0.applyGhostVariant()
            $0.layer.cornerRadius = 2   // rounded-sm
        }
        favoriteButton.iconAnimation = FavoriteButton.iconAnimation
        bookmarkButton.iconAnimation = BookmarkButton.iconAnimation
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        bookmarkButton.addTarget(self, action: #selector(bookmarkTapped), for: .touchUpInside)
    }

    private func configureCardTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)
        onDPadClick = { [weak self] in self?.cardTapped() }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view, current !== self {
            if current is UIControl { return false }
            view = current.superview
        }
        return true
    }

    func configure(media: AnimeItem, actions: PreviewCardActions, trace: TraceAnime? = nil) {
        isDismissed = false
        self.trace = trace
        // Native counterpart of SUPPORTS.isUnderPowered, with Low Power Mode
        // respected as well. Neither blurred images nor dual trailer decoders run.
        effectsEnabled = !ProcessInfo.processInfo.isLowPowerModeEnabled
            && ProcessInfo.processInfo.physicalMemory >= 4 * 1_024 * 1_024 * 1_024
        self.media = media
        self.actions = actions
        titleLabel.attributedText = CSSText.string(AniListUtil.title(for: media),
                                                   font: .nunito(ofSize: 18, weight: .bold),
                                                   color: UIColor.HayaseTheme.foreground, lineHeight: 28)
        descriptionLabel.attributedText = descriptionText(for: media)
        updateDetails(for: media)
        updatePlayTitle(for: media)
        // preview.svelte's buttons read the viewer's lists and the media's `isFavourite`, as the
        // banner's do; the card does not ask AniList about the media it is shown for
        isFavorite = media.isFavouriteForViewer
        isBookmarked = media.listEntry != nil
        refreshActionIcons()
        setBackdropBlurHidden(false)
        loadBanner(for: media)

        videoframe.reset()
        videoframe.isHidden = true
        if let trace {
            // preview.svelte: `{#if trace}` the picture and `<Videoframe src={trace.video}>` instead
            // of the banner and the trailer
            youtubeIframe.reset()
            youtubeIframe.isHidden = true
            videoframe.isHidden = false
            videoframe.configure(src: trace.video)
        } else if !effectsEnabled {
            youtubeIframe.reset()
            youtubeIframe.isHidden = true
        } else {
            youtubeIframe.isHidden = media.trailerYouTubeID == nil
            youtubeIframe.configure(id: media.trailerYouTubeID)
        }

    }

    func animateIn() {
        // preview.svelte: animation 0.3s ease 0s 1 load-in
        let animator = UIViewPropertyAnimator(
            duration: 0.3,
            controlPoint1: CGPoint(x: 0.25, y: 0.1),
            controlPoint2: CGPoint(x: 0.25, y: 1)
        ) { [weak self] in
            self?.alpha = 1
            self?.transform = .identity
        }
        animator.startAnimation()
    }

    private func updateDetails(for media: AnimeItem) {
        detailsLabel.attributedText = detailsAttributedText(for: media)
    }

    /// `.details span+span::before { content: '•'; padding: 0 .3rem; font-size: .4rem; align-self: center;
    /// color: #737373 }`: a small bullet between the details, 4.8pt of room on each side, in the middle
    /// of the line whatever the text is doing.
    private func detailsAttributedText(for media: AnimeItem) -> NSAttributedString {
        let lineHeight: CGFloat = 16.5   // text-[11px] on the page's line-height of 1.5
        let textFont = UIFont.nunito(ofSize: 11)
        let bulletFont = UIFont.nunito(ofSize: 6.4)
        let textAttributes = CSSText.attributes(font: textFont, color: UIColor.HayaseTheme.foreground,
                                                lineHeight: lineHeight, lineBreak: .byClipping)
        // The bullet's own line box is 1.5 times its font size, and sits in the middle of the span.
        let textBaseline = (lineHeight - textFont.lineHeight) / 2 + textFont.ascender
        let bulletBaseline = (lineHeight - bulletFont.pointSize * 1.5) / 2
            + (bulletFont.pointSize * 1.5 - bulletFont.lineHeight) / 2 + bulletFont.ascender
        var bulletAttributes = textAttributes
        bulletAttributes[.font] = bulletFont
        bulletAttributes[.foregroundColor] = UIColor(red: 115 / 255, green: 115 / 255, blue: 115 / 255, alpha: 1)   // #737373
        bulletAttributes[.baselineOffset] = (lineHeight - textFont.lineHeight) / 2 + (textBaseline - bulletBaseline)
        bulletAttributes[.kern] = 4.8

        let result = NSMutableAttributedString()
        for (index, detail) in detailParts(for: media).enumerated() {
            if index > 0 {
                result.addAttribute(.kern, value: 4.8, range: NSRange(location: result.length - 1, length: 1))
                result.append(NSAttributedString(string: "•", attributes: bulletAttributes))
            }
            result.append(NSAttributedString(string: detail, attributes: textAttributes))
        }
        return result
    }

    private func detailParts(for media: AnimeItem) -> [String] {
        var details: [String] = [AniListUtil.format(media.format)]
        details.append(progressOrDurationText(for: media) ?? "N/A")

        if let season = seasonText(for: media), !season.isEmpty {
            details.append(season)
        }
        if !shouldHideScore(for: media), let score = media.score, score > 0 {
            details.append("\(Int(safe: Double(score)))%")
        }
        return details
    }

    private func progressOrDurationText(for media: AnimeItem) -> String? {
        if let text = AniListUtil.episodesText(for: media) { return text }
        if let duration = media.duration, duration > 0 {
            return "\(duration) Minute\(duration == 1 ? "" : "s")"
        }
        return nil
    }

    private func seasonText(for media: AnimeItem) -> String? {
        AniListUtil.seasonText(for: media)?.capitalized
    }

    private func shouldHideScore(for media: AnimeItem) -> Bool {
        guard Settings.hideSpoilers else { return false }
        let status = media.listEntry?.status
        return status == "CURRENT" || status == "PLANNING"
    }

    /// util.ts `desc(media)`, set in an element that collapses white space.
    private func descriptionText(for media: AnimeItem) -> NSAttributedString {
        let text = media.description.map(CSSText.collapsingWhitespace) ?? "No description available."
        return CSSText.string(text, font: .nunito(ofSize: 11.2), color: UIColor.HayaseTheme.mutedForeground,
                              lineHeight: 16.8)   // text-[.7rem] on 1.5
    }

    private func updatePlayTitle(for media: AnimeItem) {
        playButton.setTitle(PlayButton.title(listStatus: media.listEntry?.status), for: .normal)
    }

    private func refreshActionIcons() {
        favoriteButton.setImage(FavoriteButton.icon(isFavorite: isFavorite, pointSize: 11.2), for: .normal)
        bookmarkButton.setImage(BookmarkButton.icon(isOnList: isBookmarked, pointSize: 11.2), for: .normal)
    }

    private func loadBanner(for media: AnimeItem) {
        imageTask?.cancel()
        imageTask = nil
        bannerLoadToken += 1
        let token = bannerLoadToken
        currentImageURL = nil
        bannerImageView.image = nil
        bannerGlow.reset()
        bannerImageView.backgroundColor = UIColor.HayaseTheme.background

        if let trace {
            loadResolvedBannerURL(trace.image, media: media, token: token)
            return
        }
        let fallbackURL = resolvedFallbackBannerURL(for: media)
        guard usesWideBannerSource else {
            loadResolvedBannerURL(fallbackURL, media: media, token: token)
            return
        }

        AniZipService.shared.imagesCached(anilistID: media.id) { [weak self] response in
            DispatchQueue.main.async {
                guard let self,
                      !self.isDismissed,
                      self.bannerLoadToken == token,
                      self.media?.id == media.id else { return }
                self.loadResolvedBannerURL(Self.anizipBannerURL(from: response) ?? fallbackURL,
                                           media: media,
                                           token: token)
            }
        }
    }

    private var usesWideBannerSource: Bool {
        // Mirrors the web Banner component's md breakpoint for preview cards.
        let width = window?.bounds.width ?? UIScreen.main.bounds.width
        return width >= 768
    }

    private func resolvedFallbackBannerURL(for media: AnimeItem) -> String? {
        if usesWideBannerSource {
            return media.bannerURL ?? Self.youtubeThumbnailURL(for: media.trailerYouTubeID) ?? media.coverURL
        }
        return media.coverURL ?? media.bannerURL ?? Self.youtubeThumbnailURL(for: media.trailerYouTubeID)
    }

    private static func anizipBannerURL(from response: AniZipImagesResponse?) -> String? {
        let backdrop = response?.backdrops?
            .sorted { $0.voteAverage > $1.voteAverage }
            .first { $0.iso6391 == nil && $0.aspectRatio > 1.2 && !$0.filePath.isEmpty }?
            .filePath
        let poster = response?.posters?
            .sorted { $0.voteAverage > $1.voteAverage }
            .first { $0.iso6391 == nil && $0.aspectRatio > 1.2 && !$0.filePath.isEmpty }?
            .filePath
        return backdrop ?? poster
    }

    private static func youtubeThumbnailURL(for id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg"
    }

    private static func nextYoutubeThumbnailURL(after urlString: String, media: AnimeItem) -> String? {
        guard let id = media.trailerYouTubeID, !id.isEmpty,
              urlString.contains("i.ytimg.com/vi/\(id)/") else { return nil }
        let sizes = ["maxresdefault", "sddefault", "hqdefault", "mqdefault", "default"]
        guard let current = sizes.firstIndex(where: { urlString.contains("/\($0).jpg") }) else { return nil }
        let next = sizes.index(after: current)
        guard next < sizes.endIndex else { return nil }
        return "https://i.ytimg.com/vi/\(id)/\(sizes[next]).jpg"
    }

    private static func isMissingYoutubeThumbnail(_ image: UIImage, urlString: String) -> Bool {
        urlString.contains("i.ytimg.com/vi/")
            && Int(image.size.width.rounded()) == 120
            && Int(image.size.height.rounded()) == 90
    }

    private func loadResolvedBannerURL(_ urlString: String?, media: AnimeItem, token: Int) {
        currentImageURL = urlString
        guard let urlString, let url = URL(string: urlString) else { return }
        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            if Self.isMissingYoutubeThumbnail(cached, urlString: urlString),
               let nextURL = Self.nextYoutubeThumbnailURL(after: urlString, media: media) {
                loadResolvedBannerURL(nextURL, media: media, token: token)
                return
            }
            applyImage(cached, for: urlString)
            return
        }
        imageTask?.cancel()
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard !self.isDismissed,
                      self.bannerLoadToken == token,
                      self.media?.id == media.id,
                      self.currentImageURL == urlString else { return }
                if Self.isMissingYoutubeThumbnail(image, urlString: urlString),
                   let nextURL = Self.nextYoutubeThumbnailURL(after: urlString, media: media) {
                    self.loadResolvedBannerURL(nextURL, media: media, token: token)
                    return
                }
                SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
                self.applyImage(image, for: urlString)
            }
        }
        imageTask?.resume()
    }

    private func applyImage(_ image: UIImage, for urlString: String) {
        guard !isDismissed, currentImageURL == urlString else { return }
        bannerImageView.image = image
        if effectsEnabled {
            bannerGlow.configure(image: image, cacheKey: urlString)
        }
    }



    @objc private func cardTapped() {
        guard let media else { return }
        actions?.open(media)
    }

    @objc private func playTapped() {
        guard let media else { return }
        actions?.play(media)
    }

    @objc private func favoriteTapped() {
        guard let media else { return }
        actions?.favorite(media) { [weak self] success in
            guard let self, success else { return }
            self.isFavorite.toggle()
            self.refreshActionIcons()
        }
    }

    @objc private func bookmarkTapped() {
        guard let media else { return }
        actions?.bookmark(media) { [weak self] success in
            guard let self, success else { return }
            self.isBookmarked.toggle()
            self.refreshActionIcons()
        }
    }

    func prepareForDismissal() {
        isDismissed = true
        bannerLoadToken += 1
        imageTask?.cancel()
        imageTask = nil
        bannerGlow.reset()
        youtubeIframe.reset()
        videoframe.reset()
        setBackdropBlurHidden(false)
    }
}

private final class PreviewBannerGradientView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [
                                            UIColor.HayaseTheme.muted.withAlphaComponent(0).cgColor,
                                            UIColor.HayaseTheme.muted.withAlphaComponent(0).cgColor,
                                            UIColor.HayaseTheme.muted.withAlphaComponent(0.89).cgColor,
                                            UIColor.HayaseTheme.muted.cgColor,
                                        ] as CFArray,
                                        locations: [0.0, 0.80, 0.95, 1.0]) else { return }
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: bounds.midX, y: bounds.minY),
                                   end: CGPoint(x: bounds.midX, y: bounds.maxY),
                                   options: [])
    }
}
