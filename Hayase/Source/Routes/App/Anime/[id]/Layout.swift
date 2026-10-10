//
//  Layout.swift
//  Hayase
//
//  Mirrors: src/routes/app/anime/[id]/+layout.svelte (cover trigger), src/routes/app/anime/[id]/+page.svelte (Tabs.Root bound value state), src/app.css (:active interaction)
//

import UIKit
import SafariServices
import ObjectiveC
import CoreImage
import WebKit

// MARK: - Color constants

// interface Default / Blackout theme tokens.
let hayasePageBackground = UIColor.HayaseTheme.background
let hayaseCardBackground = UIColor.HayaseTheme.card

private let hayaseAnimeBannerBackdropDidChange = Notification.Name("HayaseHomeBannerBackdropDidChange")
private let hayaseAnimeBannerBackdropURLKey = "url"
private let hayaseAnimeBannerBackdropAlphaKey = "alpha"
private let hayaseAnimeBannerBackdropScrollOffsetKey = "scrollOffset"
private let hayaseAnimeBannerBackdropHeightKey = "height"
private let hayaseAnimeBannerBackdropRouteKey = "route"
private let hayaseAnimeBannerBackdropMediaKey = "media"
private let hayaseAnimeBannerBackdropAnimeRoute = "anime"

// MARK: - AnimeDetailBannerBackdropView

private final class AnimeDetailBannerBackdropView: UIView {
    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .clear
        return view
    }()
    private let gradientView = BannerGradientView()
    private var currentURLString: String?
    /// The address the page asked for, which is not the one loading while a thumbnail is retried.
    private var requestedURLString: String?
    private var thumbnailAttempt = 0
    private var imageTask: URLSessionDataTask?
    private var heightConstraint: NSLayoutConstraint?
    private var displayedAlpha: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        imageTask?.cancel()
    }

    private func setup() {
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = false

        [imageView, gradientView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let height = heightAnchor.constraint(equalToConstant: 368)
        heightConstraint = height
        NSLayoutConstraint.activate([
            height,
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gradientView.topAnchor.constraint(equalTo: imageView.topAnchor),
            gradientView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
        ])
    }

    func configure(height: CGFloat, compact: Bool) {
        heightConstraint?.constant = height
        gradientView.setCompact(compact)
    }

    func applyScrollOffset(_ _: CGFloat) {
        transform = .identity
    }

    func applyAlpha(_ alpha: CGFloat, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        let clamped = min(max(alpha, 0), 1)
        guard abs(clamped - displayedAlpha) > 0.001 else {
            completion?(true)
            return
        }

        displayedAlpha = clamped
        if animated {
            // banner-image.svelte: `transition-opacity duration-500`
            BannerImage.fade([self], to: clamped) { completion?(true) }
        } else {
            layer.removeAllAnimations()
            self.alpha = clamped
            completion?(true)
        }
    }

    func setImage(urlString: String?) {
        guard let urlString else {
            currentURLString = nil
            requestedURLString = nil
            imageTask?.cancel()
            imageTask = nil
            imageView.image = nil
            return
        }

        guard requestedURLString != urlString else { return }
        requestedURLString = urlString
        thumbnailAttempt = 0
        load(urlString, requested: urlString)
    }

    /// The sizes YouTube is asked for, one after the other, when a thumbnail is not there:
    /// `verifyThumbnail` of `img/banner.svelte`.
    private static let thumbnailSizes = ["sddefault", "hqdefault", "mqdefault", "default"]

    private func load(_ urlString: String, requested: String) {
        currentURLString = urlString
        imageTask?.cancel()
        imageTask = nil

        // a thumbnail that YouTube does not have comes back as a 120 by 90 picture
        let isThumbnail = urlString.hasPrefix("https://i.ytimg.com/vi/")
        let placeholder = CGSize(width: 120, height: 90)

        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString),
           !(isThumbnail && cached.size == placeholder) {
            imageView.image = cached
            return
        }

        guard let url = URL(string: urlString) else {
            imageView.image = nil
            return
        }

        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.currentURLString == urlString else { return }

                if isThumbnail, image.size == placeholder {
                    let parts = urlString.components(separatedBy: "/")
                    if parts.count > 4, self.thumbnailAttempt < Self.thumbnailSizes.count {
                        let next = "https://i.ytimg.com/vi/\(parts[4])/\(Self.thumbnailSizes[self.thumbnailAttempt]).jpg"
                        self.thumbnailAttempt += 1
                        self.load(next, requested: requested)
                        return
                    }
                }

                SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
                SharedImageCache.shared.setObject(image, forKey: requested as NSString)
                UIView.transition(with: self.imageView,
                                  duration: 0.3,
                                  options: .transitionCrossDissolve,
                                  animations: { self.imageView.image = image })
            }
        }
        imageTask?.resume()
    }
}

// MARK: - AnimeInfoHeaderView

final class AnimeInfoHeaderView: UIView, UIGestureRecognizerDelegate {

    // MARK: - Callbacks

    var onFavorite: (() -> Void)?
    var onBookmark: (() -> Void)?
    var onShare: (() -> Void)?
    var onPlayTrailer: (() -> Void)?
    var onWatch: (() -> Void)?
    var onEntryEditor: (() -> Void)?
    /// A genre or a tag, whose name and whether it is a tag.
    var onGenreTapped: ((String, Bool) -> Void)?
    var onBadgeTapped: ((_ filterType: String, _ value: String) -> Void)?
    var onOpenAniList: (() -> Void)?
    var onOpenMAL: (() -> Void)?
    var onOpenCover: ((_ urlString: String?, _ image: UIImage?) -> Void)?

    var anilistId: Int?
    var malId: Int?
    var displayedBannerURL: String?
    var storedAccentColor: UIColor = .white

    static let bannerHeight: CGFloat = 368

    // MARK: - Stacks

    private var contentStack: UIStackView!
    private var coverAndTextColumn: UIStackView!
    private var textColumn: UIStackView!
    private var actionsRow: UIStackView!
    private var playCombo: UIStackView!
    private let actionsTrailingSpacer: UIView = {
        let v = UIView()
        v.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        v.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
        return v
    }()
    private let headerFollowerStack = FollowerAvatarStackView()

    private var contentTopConstraint: NSLayoutConstraint?
    private var contentMaxWidthConstraint: NSLayoutConstraint?
    private var contentWidthConstraint: NSLayoutConstraint?
    private var contentCenterXConstraint: NSLayoutConstraint?
    private var playComboWidthConstraint: NSLayoutConstraint?
    private enum ActionLayoutMode {
        case regular
        case compactNarrow
        case compactWide
    }
    private var appliedActionLayoutMode: ActionLayoutMode?
    private var appliedPlayComboWidth: CGFloat = -1

    // MARK: - Cover

    /// `Load`'s `div`: `style:background={color ?? '#1890ff'}`, with the picture in it
    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.isUserInteractionEnabled = true
        iv.layer.cornerRadius = 4   // interface Dialog.Trigger: rounded = Tailwind 0.25rem = 4pt
        iv.backgroundColor = AnimeInfoHeaderView.coverBackground(nil)
        return iv
    }()

    /// `Load`'s `img`: it fades in on the color of the `div`, which stays where it is
    private let coverPicture: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let coverOverlayView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0)
        v.isUserInteractionEnabled = false
        return v
    }()

    private let coverOverlayIcon: UIImageView = {
        let iv = UIImageView(image: UIImage.hayaseIcon("maximize-2", withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)))
        iv.tintColor = UIColor.HayaseTheme.foreground
        iv.contentMode = .scaleAspectFit
        iv.alpha = 0
        iv.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        return iv
    }()

    private let coverButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        button.accessibilityLabel = "Open cover"
        button.adjustsImageWhenHighlighted = false
        button.noActiveScale = true   // the cover scales itself (`applyCoverState`)
        return button
    }()

    // MARK: - Text labels

    private let romajiLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 16, weight: .light)
        l.textColor = UIColor.HayaseTheme.mutedForeground
        l.numberOfLines = 1
        l.setContentCompressionResistancePriority(.init(760), for: .vertical)
        l.isHidden = true
        return l
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 30, weight: .black)
        l.textColor = .white
        l.numberOfLines = 2
        l.lineBreakMode = .byWordWrapping
        l.setContentCompressionResistancePriority(.init(760), for: .vertical)
        return l
    }()

    // MARK: - Badges

    private let badgesScrollView: BadgeRowScrollView = {
        let sv = BadgeRowScrollView()
        sv.isScrollEnabled = false   // overflow-x-clip: the badges are cut off, not scrolled
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.isHidden = true
        return sv
    }()

    private let descriptionLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14, weight: .light)
        l.textColor = UIColor(white: 0.649, alpha: 1.0)
        l.numberOfLines = 4
        // interface: whitespace-pre-wrap preserves \n, word-wrap for soft wrapping
        l.lineBreakMode = .byWordWrapping
        return l
    }()

    // MARK: - Action buttons

    // PlayButton: bg-custom select:!bg-custom-600 text-contrast rounded-r-none, font-bold
    private let playButton: SelectButton = {
        let b = SelectButton()
        b.setImage(UIImage.hayaseFilledIcon("play", pointSize: 13), for: .normal)
        b.setTitle("Watch Now", for: .normal)
        b.restingBackground = .white
        b.selectedBackground = UIColor.white.withHSLLightness(0.4)
        b.restingTint = .black
        b.selectedTint = .black
        b.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        b.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        b.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        b.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        return b
    }()

    // EntryEditor trigger: rounded-l-none bg-custom-400 select:!bg-custom-700 text-contrast animated-icon
    private let entryEditorButton: SelectButton = {
        let b = SelectButton()
        b.setLayeredIcon(.penLine)
        b.restingBackground = UIColor(white: 0.75, alpha: 1)
        b.selectedBackground = UIColor(white: 0.75, alpha: 1)
        b.restingTint = .black
        b.selectedTint = .black
        b.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        return b
    }()

    // The secondary icon buttons: select:bg-secondary/60, and `select:!text-custom` on the
    // favourite, bookmark, share and trailer buttons (set once the media's colour is known).
    private let favoriteButton: SelectButton = {
        let b = SelectButton()
        b.setImage(UIImage.hayaseIcon("heart", pointSize: 16), for: .normal)
        b.applySecondaryVariant()
        b.iconAnimation = FavoriteButton.iconAnimation
        return b
    }()

    private let bookmarkButton: SelectButton = {
        let b = SelectButton()
        b.setImage(UIImage.hayaseIcon("bookmark", pointSize: 16), for: .normal)
        b.applySecondaryVariant()
        b.iconAnimation = BookmarkButton.iconAnimation
        return b
    }()

    private let shareButton: SelectButton = {
        let b = SelectButton()
        b.setImage(UIImage.hayaseIcon("share-2", pointSize: 16), for: .normal)
        b.applySecondaryVariant()
        return b
    }()

    private let trailerButton: SelectButton = {
        let b = SelectButton()
        b.setLayeredIcon(.clapperboard)
        b.applySecondaryVariant()
        b.isHidden = true
        return b
    }()

    private let anilistButton: SelectButton = {
        let b = SelectButton()
        b.applySecondaryVariant()
        b.isHidden = true
        let icon = AniListIconView(frame: .zero)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isUserInteractionEnabled = false
        b.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            icon.centerXAnchor.constraint(equalTo: b.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: b.centerYAnchor),
        ])
        return b
    }()

    private let malButton: SelectButton = {
        let b = SelectButton()
        b.applySecondaryVariant()
        b.isHidden = true
        let icon = MALIconView(frame: .zero)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isUserInteractionEnabled = false
        b.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            icon.centerXAnchor.constraint(equalTo: b.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: b.centerYAnchor),
        ])
        return b
    }()

    // MARK: - Genres

    private let genresScrollView: ChipRowScrollView = {
        let sv = ChipRowScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    private let genresContainer = UIView()

    private var coverImageTask: URLSessionDataTask?
    private var loadedCoverURL: String?
    private var displayedCoverURL: String?
    private var coverScaleAnimator: UIViewPropertyAnimator?
    private var coverOverlayAnimator: UIViewPropertyAnimator?
    private var isCoverPressed = false
    private var isCoverHovered = false
    private var bannerHidden = false
    private var hasTrailer = false
    // "Also available on YouTube!": +layout.svelte's `trailerIsMedia`
    private var trailerMedia: AnimeItem?
    private var trailerVideoID: String?
    private var trailerMinutes = 0
    private var trailerMinutesLoader: TrailerMinutes?
    private var mappedEpisodeCount = 0
    /// Whether the anizip answer for the page is in, which is `eps` not being `null`.
    private var episodesMappingsKnown = false
    private var trailerTooltip: TrailerTooltipView?
    private var trailerTooltipConstraints: [NSLayoutConstraint] = []
    private var trailerTooltipMedium: Bool?
    private var rawDescription: String?
    private var lastAppliedLabelMaxWidth: CGFloat = 0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear

        genresScrollView.translatesAutoresizingMaskIntoConstraints = false

        badgesScrollView.translatesAutoresizingMaskIntoConstraints = false

        textColumn = UIStackView(arrangedSubviews: [romajiLabel, titleLabel, badgesScrollView, descriptionLabel])
        textColumn.axis = .vertical
        textColumn.spacing = 6   // gap-1.5
        textColumn.alignment = .fill

        coverAndTextColumn = UIStackView(arrangedSubviews: [coverImageView, textColumn])
        coverAndTextColumn.axis = .vertical
        coverAndTextColumn.spacing = 16
        coverAndTextColumn.alignment = .center
        coverAndTextColumn.isLayoutMarginsRelativeArrangement = true

        coverOverlayView.translatesAutoresizingMaskIntoConstraints = false
        coverOverlayIcon.translatesAutoresizingMaskIntoConstraints = false
        coverButton.translatesAutoresizingMaskIntoConstraints = false
        // the picture is under the overlay, which is `absolute` above it
        coverImageView.addSubview(coverPicture)
        coverImageView.addSubview(coverOverlayView)
        coverOverlayView.addSubview(coverOverlayIcon)
        coverImageView.addSubview(coverButton)
        NSLayoutConstraint.activate([
            coverPicture.topAnchor.constraint(equalTo: coverImageView.topAnchor),
            coverPicture.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor),
            coverPicture.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor),
            coverPicture.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor),
            coverOverlayView.topAnchor.constraint(equalTo: coverImageView.topAnchor),
            coverOverlayView.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor),
            coverOverlayView.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor),
            coverOverlayView.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor),
            coverOverlayIcon.centerXAnchor.constraint(equalTo: coverOverlayView.centerXAnchor),
            coverOverlayIcon.centerYAnchor.constraint(equalTo: coverOverlayView.centerYAnchor),
            coverOverlayIcon.widthAnchor.constraint(equalToConstant: 40),
            coverOverlayIcon.heightAnchor.constraint(equalToConstant: 40),
            coverButton.topAnchor.constraint(equalTo: coverImageView.topAnchor),
            coverButton.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor),
            coverButton.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor),
            coverButton.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor),
        ])
        let coverPress = UILongPressGestureRecognizer(target: self, action: #selector(coverPressChanged(_:)))
        coverPress.minimumPressDuration = 0
        coverPress.cancelsTouchesInView = false
        coverPress.delegate = self
        coverButton.addGestureRecognizer(coverPress)
        // the pointer of an iPad is `:hover`
        coverButton.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(coverHoverChanged(_:))))
        coverButton.addTarget(self, action: #selector(coverTapped), for: .touchUpInside)

        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        trailerButton.addTarget(self, action: #selector(trailerTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        entryEditorButton.addTarget(self, action: #selector(entryEditorTapped), for: .touchUpInside)
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        bookmarkButton.addTarget(self, action: #selector(bookmarkTapped), for: .touchUpInside)
        anilistButton.addTarget(self, action: #selector(anilistTapped), for: .touchUpInside)
        malButton.addTarget(self, action: #selector(malTapped), for: .touchUpInside)

        playCombo = UIStackView(arrangedSubviews: [playButton, entryEditorButton])
        playCombo.axis = .horizontal
        playCombo.spacing = 0
        playCombo.alignment = .fill
        playCombo.setContentHuggingPriority(.defaultLow, for: .horizontal)
        playCombo.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        actionsRow = UIStackView(arrangedSubviews: [bookmarkButton, favoriteButton, playCombo, shareButton, trailerButton, anilistButton, malButton])
        actionsRow.axis = .horizontal
        actionsRow.spacing = 8
        actionsRow.alignment = .fill
        actionsRow.isLayoutMarginsRelativeArrangement = true

        headerFollowerStack.setContentHuggingPriority(.required, for: .horizontal)
        headerFollowerStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        genresContainer.addSubview(genresScrollView)
        NSLayoutConstraint.activate([
            genresScrollView.topAnchor.constraint(equalTo: genresContainer.topAnchor),
            genresScrollView.bottomAnchor.constraint(equalTo: genresContainer.bottomAnchor),
            genresScrollView.centerXAnchor.constraint(equalTo: genresContainer.centerXAnchor),
            genresScrollView.widthAnchor.constraint(equalTo: genresContainer.widthAnchor),
            genresContainer.heightAnchor.constraint(equalToConstant: 28),
        ])

        contentStack = UIStackView(arrangedSubviews: [coverAndTextColumn, actionsRow, genresContainer])
        contentStack.axis = .vertical
        contentStack.spacing = 24
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 16, left: 12, bottom: 0, right: 12)

        [contentStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            coverImageView.widthAnchor.constraint(equalToConstant: 180),
            coverImageView.heightAnchor.constraint(equalToConstant: 256),

            actionsRow.heightAnchor.constraint(equalToConstant: 36),
            bookmarkButton.widthAnchor.constraint(equalToConstant: 36),
            favoriteButton.widthAnchor.constraint(equalToConstant: 36),
            entryEditorButton.widthAnchor.constraint(equalToConstant: 36),
            shareButton.widthAnchor.constraint(equalToConstant: 36),
            trailerButton.widthAnchor.constraint(equalToConstant: 36),
            anilistButton.widthAnchor.constraint(equalToConstant: 36),
            malButton.widthAnchor.constraint(equalToConstant: 36),

            badgesScrollView.heightAnchor.constraint(equalToConstant: 24),
        ])
        playComboWidthConstraint = playCombo.widthAnchor.constraint(equalToConstant: 180)
        playComboWidthConstraint?.priority = UILayoutPriority(999)
        playComboWidthConstraint?.isActive = true

        contentTopConstraint = contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 64)
        contentTopConstraint?.isActive = true
        contentMaxWidthConstraint = contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: 1600)
        contentMaxWidthConstraint?.isActive = true
        contentWidthConstraint = contentStack.widthAnchor.constraint(equalTo: widthAnchor)
        contentWidthConstraint?.priority = .defaultHigh
        contentWidthConstraint?.isActive = true
        contentCenterXConstraint = contentStack.centerXAnchor.constraint(equalTo: centerXAnchor)
        contentCenterXConstraint?.isActive = true
        NSLayoutConstraint.activate([
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        textColumnWidthConstraint = textColumn.widthAnchor.constraint(equalTo: coverAndTextColumn.widthAnchor)
        textColumnWidthConstraint?.isActive = true

        applyLayoutForSizeClass()
    }

    private var textColumnWidthConstraint: NSLayoutConstraint?

    // MARK: - Adaptive layout

    /// What the media queries of the interface (`md`, `xl`, `min-[380px]`) are asked: the window, whatever
    /// the size class of the screen is. A phone turned sideways is wider than `md`.
    private var viewportWidth: CGFloat {
        window?.bounds.width ?? UIScreen.main.bounds.width
    }

    private var isMedium: Bool { viewportWidth >= 768 }

    private func applyLayoutForSizeClass() {
        let isRegular = isMedium
        lastAppliedMedium = isRegular
        let measuredWidth = measuredContentWidth()
        let hPad = interfaceHorizontalPadding(for: measuredWidth)

        contentTopConstraint?.constant = isRegular ? 128 : 48
        // `gap-4 md:gap-6` between the parts of the header
        contentStack.spacing = isRegular ? 24 : 16

        updateHeaderRowInsets(isRegular: isRegular)
        updateGenresScrollInset(isRegular: isRegular)

        if isRegular {
            coverAndTextColumn.axis = .horizontal
            coverAndTextColumn.spacing = 20
            coverAndTextColumn.alignment = .bottom
        } else {
            // `flex-col md:flex-row ... gap-5`
            coverAndTextColumn.axis = .vertical
            coverAndTextColumn.spacing = 20
            coverAndTextColumn.alignment = .center
        }

        if isRegular {
            textColumn.alignment = .fill
            textColumn.spacing = 6   // gap-1.5
            textColumn.setCustomSpacing(10, after: titleLabel)       // gap-1.5 + md:pt-1
            textColumn.setCustomSpacing(14, after: badgesScrollView) // gap-1.5 + md:pt-2
        } else {
            textColumn.alignment = .fill  // items-center (labels center their text)
            textColumn.spacing = 6
            textColumn.setCustomSpacing(6, after: titleLabel)
            textColumn.setCustomSpacing(6, after: badgesScrollView)
        }

        romajiLabel.textAlignment = isRegular ? .left : .center
        titleLabel.textAlignment = isRegular ? .left : .center
        descriptionLabel.textAlignment = isRegular ? .left : .center

        romajiLabel.font = isRegular ? .nunito(ofSize: 18, weight: .light) : .nunito(ofSize: 16, weight: .light)
        titleLabel.font = isRegular ? .nunito(ofSize: 36, weight: .black) : .nunito(ofSize: 30, weight: .black)
        descriptionLabel.font = .nunito(ofSize: 14, weight: .light)
        // Rebuild attributed text so paragraph style picks up the new font size
        if let raw = rawDescription {
            setDescriptionText(raw)
        }

        badgesScrollView.isHidden = !isRegular
        descriptionLabel.isHidden = !isRegular

        textColumnWidthConstraint?.isActive = !isRegular

        contentStack.layoutMargins = UIEdgeInsets(top: isRegular ? 48 : 16, left: hPad, bottom: 0, right: hPad)

        if isRegular {
            anilistButton.isHidden = false
            malButton.isHidden = (malId == nil)
            updateFollowerProfileSpacing(isRegular: true)
            headerFollowerStack.isHidden = headerFollowerStack.isEmpty
        } else {
            anilistButton.isHidden = true
            malButton.isHidden = true
            headerFollowerStack.isHidden = true
        }
        updateActionVisibilityForCurrentWidth()
    }

    private var lastAppliedMedium: Bool?

    /// The layout changes where the window crosses `md`, which a turned phone or a resized iPad window
    /// does without its size class changing.
    private func applyLayoutIfViewportChanged() {
        guard lastAppliedMedium != isMedium else { return }
        let first = lastAppliedMedium == nil
        applyLayoutForSizeClass()
        setNeedsLayout()
        invalidateIntrinsicContentSize()
        // the banner is another image on either side of `md`
        if !first { publishBannerSource() }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyLayoutIfViewportChanged()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            applyLayoutIfViewportChanged()
        }
        updateTrailerTooltip()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyLayoutIfViewportChanged()
        updateActionVisibilityForCurrentWidth()
        positionTrailerTooltip()
        let isRegular = isMedium
        let measuredWidth = measuredContentWidth()
        let hPad = interfaceHorizontalPadding(for: measuredWidth)
        contentStack.layoutMargins = UIEdgeInsets(top: isRegular ? 48 : 16, left: hPad, bottom: 0, right: hPad)
        updateHeaderRowInsets(isRegular: isRegular)
        updateGenresScrollInset(isRegular: isRegular)
        let effectiveWidth = isRegular ? min(measuredWidth, 1600) : measuredWidth
        let maxW: CGFloat
        if isRegular {
            maxW = effectiveWidth - 2 * hPad - 180 - 20
        } else {
            maxW = effectiveWidth - 2 * hPad
        }
        if maxW > 0 {
            titleLabel.preferredMaxLayoutWidth = maxW
            romajiLabel.preferredMaxLayoutWidth = maxW
            descriptionLabel.preferredMaxLayoutWidth = maxW
        }
    }

    func updateLabelWidths(forContainerWidth width: CGFloat) {
        guard width > 1 else { return }
        let isRegular = isMedium
        let measuredWidth = measuredContentWidth(fallbackWidth: width)
        let hPad = interfaceHorizontalPadding(for: measuredWidth)
        let effectiveWidth = isRegular ? min(measuredWidth, 1600) : measuredWidth
        let maxW: CGFloat
        if isRegular {
            maxW = effectiveWidth - 2 * hPad - 180 - 20
        } else {
            maxW = effectiveWidth - 2 * hPad
        }
        guard maxW > 0 else { return }
        guard abs(maxW - lastAppliedLabelMaxWidth) > 0.5 else { return }
        lastAppliedLabelMaxWidth = maxW
        titleLabel.preferredMaxLayoutWidth = maxW
        romajiLabel.preferredMaxLayoutWidth = maxW
        descriptionLabel.preferredMaxLayoutWidth = maxW
        titleLabel.invalidateIntrinsicContentSize()
        romajiLabel.invalidateIntrinsicContentSize()
        descriptionLabel.invalidateIntrinsicContentSize()
    }

    private func updateActionVisibilityForCurrentWidth() {
        let isRegular = isMedium
        let measuredWidth = measuredContentWidth()
        let effectiveWidth = isRegular ? min(measuredWidth, 1600) : measuredWidth
        let hPad = interfaceHorizontalPadding(for: measuredWidth)
        let contentWidth = max(0, effectiveWidth - 2 * hPad)
        // `min-[380px]` is a media query: it is about the window, not about the row
        let isNarrow = viewportWidth < 380
        let targetMode: ActionLayoutMode = isRegular ? .regular : (isNarrow ? .compactNarrow : .compactWide)
        applyActionLayoutMode(targetMode)

        let fixedButtonWidth = isNarrow ? (36 * 2 + actionsRow.spacing * 2) : 0
        let targetPlayComboWidth = isNarrow ? max(0, contentWidth - fixedButtonWidth) : 180
        let targetPriority: UILayoutPriority = isNarrow ? .required : UILayoutPriority(999)
        if playComboWidthConstraint?.priority != targetPriority {
            playComboWidthConstraint?.priority = targetPriority
        }
        if abs(targetPlayComboWidth - appliedPlayComboWidth) > 0.5 {
            appliedPlayComboWidth = targetPlayComboWidth
            playComboWidthConstraint?.constant = targetPlayComboWidth
        }

        shareButton.isHidden = isNarrow
        trailerButton.isHidden = isNarrow || !hasTrailer
        updateTrailerTooltip()
        anilistButton.isHidden = !isRegular
        malButton.isHidden = !isRegular || malId == nil
        headerFollowerStack.isHidden = !isRegular || headerFollowerStack.isEmpty
        updateFollowerProfileSpacing(isRegular: isRegular)
    }

    private func applyActionLayoutMode(_ mode: ActionLayoutMode) {
        guard appliedActionLayoutMode != mode else { return }
        appliedActionLayoutMode = mode

        actionsTrailingSpacer.removeFromSuperview()
        actionsRow.arrangedSubviews.forEach {
            actionsRow.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        switch mode {
        case .regular:
            actionsRow.addArrangedSubview(playCombo)
            actionsRow.addArrangedSubview(favoriteButton)
            actionsRow.addArrangedSubview(bookmarkButton)
            actionsRow.addArrangedSubview(shareButton)
            actionsRow.addArrangedSubview(trailerButton)
            actionsRow.addArrangedSubview(anilistButton)
            actionsRow.addArrangedSubview(malButton)
            actionsRow.addArrangedSubview(headerFollowerStack)
            actionsRow.addArrangedSubview(actionsTrailingSpacer)
            actionsRow.setCustomSpacing(20, after: playCombo)
        case .compactNarrow:
            actionsRow.addArrangedSubview(playCombo)
            actionsRow.addArrangedSubview(favoriteButton)
            actionsRow.addArrangedSubview(bookmarkButton)
            actionsRow.addArrangedSubview(shareButton)
            actionsRow.addArrangedSubview(trailerButton)
            actionsRow.addArrangedSubview(anilistButton)
            actionsRow.addArrangedSubview(malButton)
            actionsRow.setCustomSpacing(actionsRow.spacing, after: playCombo)
        case .compactWide:
            actionsRow.addArrangedSubview(bookmarkButton)
            actionsRow.addArrangedSubview(favoriteButton)
            actionsRow.addArrangedSubview(playCombo)
            actionsRow.addArrangedSubview(shareButton)
            actionsRow.addArrangedSubview(trailerButton)
            actionsRow.addArrangedSubview(anilistButton)
            actionsRow.addArrangedSubview(malButton)
            actionsRow.setCustomSpacing(actionsRow.spacing, after: playCombo)
        }
    }

    private func updateFollowerProfileSpacing(isRegular: Bool) {
        guard isRegular else { return }
        actionsRow.setCustomSpacing(8, after: anilistButton)
        actionsRow.setCustomSpacing(8, after: malButton)
        actionsRow.setCustomSpacing(20, after: malButton.isHidden ? anilistButton : malButton)
    }

    private func measuredContentWidth(fallbackWidth: CGFloat? = nil) -> CGFloat {
        if contentStack.bounds.width > 0 { return contentStack.bounds.width }
        let baseWidth = fallbackWidth ?? (bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width)
        return baseWidth
    }

    private func interfaceHorizontalPadding(for measuredWidth: CGFloat) -> CGFloat {
        // +layout.svelte: 2xs:px-3 xl:px-14, which are media queries too
        AnimeDetailViewController.interfacePageSideInset(for: viewportWidth)
    }

    private func updateGenresScrollInset(isRegular: Bool) {
        // No content inset needed — contentStack.layoutMargins already
        // provides the correct horizontal padding from the view edges.
        let leftInset: CGFloat = 0
        guard abs(genresScrollView.contentInset.left - leftInset) > 0.5 else { return }
        genresScrollView.contentInset = .zero
        genresScrollView.scrollIndicatorInsets = .zero
        if genresScrollView.contentOffset.x >= -0.5 {
            resetGenresScrollPosition()
        }
    }

    private func resetGenresScrollPosition() {
        genresScrollView.setContentOffset(
            CGPoint(x: -genresScrollView.contentInset.left, y: 0),
            animated: false)
    }

    private func updateHeaderRowInsets(isRegular: Bool) {
        // contentStack.layoutMargins handles all horizontal padding.
        // No additional per-row insets needed.
        coverAndTextColumn.layoutMargins = .zero
        actionsRow.layoutMargins = .zero
    }

    // MARK: - Sidebar banner bridge

    func publishSidebarBackdrop() {
        postSidebarBackdrop(urlString: displayedBannerURL,
                            scrollOffset: 0,
                            alpha: bannerHidden ? 0.05 : 1.0)
    }

    private func currentSidebarBackdropHeight() -> CGFloat {
        // banner-image.svelte uses h-[23rem] outside /app/home.
        return 368
    }

    private func postSidebarBackdrop(urlString: String? = nil, scrollOffset: CGFloat? = nil, alpha: CGFloat? = nil) {
        var userInfo: [String: Any] = [
            hayaseAnimeBannerBackdropHeightKey: currentSidebarBackdropHeight(),
            hayaseAnimeBannerBackdropRouteKey: hayaseAnimeBannerBackdropAnimeRoute,
        ]
        // The banner belongs to a media (`bannerSrc`); the sidebar drops the old one when it changes.
        if let anilistId { userInfo[hayaseAnimeBannerBackdropMediaKey] = anilistId }
        if let urlString { userInfo[hayaseAnimeBannerBackdropURLKey] = urlString }
        if let scrollOffset { userInfo[hayaseAnimeBannerBackdropScrollOffsetKey] = scrollOffset }
        if let alpha { userInfo[hayaseAnimeBannerBackdropAlphaKey] = alpha }

        let post = {
            NotificationCenter.default.post(name: hayaseAnimeBannerBackdropDidChange, object: nil, userInfo: userInfo)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    func applyScrollFade(_ scrollOffset: CGFloat) {
        let shouldHide = scrollOffset > 100
        guard shouldHide != bannerHidden else { return }
        bannerHidden = shouldHide
        let targetAlpha: CGFloat = shouldHide ? 0.05 : 1.0
        postSidebarBackdrop(scrollOffset: scrollOffset, alpha: targetAlpha)
    }

    // MARK: - Actions

    @objc private func shareTapped() {
        shareButton.swapIcon(to: UIImage.hayaseIcon("check", pointSize: 16), hold: 0.8)
        onShare?()
    }
    @objc private func trailerTapped()     { onPlayTrailer?() }
    @objc private func playTapped()        { onWatch?() }
    @objc private func entryEditorTapped() { onEntryEditor?() }
    @objc private func favoriteTapped()    { onFavorite?() }
    @objc private func bookmarkTapped()    { onBookmark?() }
    @objc private func anilistTapped()     { onOpenAniList?() }
    @objc private func malTapped()         { onOpenMAL?() }
    @objc private func coverTapped() {
        onOpenCover?(displayedCoverURL, coverPicture.image)
    }

    @objc private func coverPressChanged(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            isCoverPressed = true
            applyCoverState(animated: true)
        case .ended, .cancelled, .failed:
            isCoverPressed = false
            applyCoverState(animated: true)
        default:
            break
        }
    }

    @objc private func coverHoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        let hovered = recognizer.state == .began || recognizer.state == .changed
        guard hovered != isCoverHovered else { return }
        isCoverHovered = hovered
        applyCoverState(animated: true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    /// The trigger is `select:scale-[1.02]` (hover, focus-visible, active), and the overlay with its icon is
    /// `group-select`: all of it is there while the pointer is over the cover or a finger is on it. app.css
    /// scales every button that is `:active` to 0.98, which wins over the 1.02 for as long as it is pressed.
    private func applyCoverState(animated: Bool) {
        stopCoverAnimator(coverScaleAnimator)
        stopCoverAnimator(coverOverlayAnimator)

        let selected = isCoverPressed || isCoverHovered
        let scale: CGFloat = isCoverPressed ? 0.98 : (isCoverHovered ? 1.02 : 1)
        let applyScale: () -> Void = { [weak self] in
            guard let self else { return }
            self.coverImageView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        let applyOverlay = { [weak self] in
            guard let self else { return }
            self.coverOverlayView.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(selected ? 0.5 : 0)
            self.coverOverlayIcon.alpha = selected ? 1 : 0
            self.coverOverlayIcon.transform = selected
                ? .identity
                : CGAffineTransform(scaleX: 0.75, y: 0.75)
        }

        guard animated else {
            applyScale()
            applyOverlay()
            return
        }

        // Into `:active` it is app.css's `transition: all 0.1s ease-in-out`; into the other states it is the
        // trigger's own `transition-transform duration-200`: Tailwind's default cubic-bezier(0.4, 0, 0.2, 1).
        let scaleAnimator = isCoverPressed
            ? UIViewPropertyAnimator(
                duration: 0.1,
                controlPoint1: CGPoint(x: 0.42, y: 0),
                controlPoint2: CGPoint(x: 0.58, y: 1),
                animations: applyScale)
            : UIViewPropertyAnimator(
                duration: 0.2,
                controlPoint1: CGPoint(x: 0.4, y: 0),
                controlPoint2: CGPoint(x: 0.2, y: 1),
                animations: applyScale)
        coverScaleAnimator = scaleAnimator
        scaleAnimator.startAnimation()

        // Overlay/icon: duration-300 transition-all ease-out.
        let overlayAnimator = UIViewPropertyAnimator(
            duration: 0.3,
            controlPoint1: CGPoint(x: 0, y: 0),
            controlPoint2: CGPoint(x: 0.2, y: 1),
            animations: applyOverlay
        )
        coverOverlayAnimator = overlayAnimator
        overlayAnimator.startAnimation()
    }

    private func stopCoverAnimator(_ animator: UIViewPropertyAnimator?) {
        guard let animator, animator.state == .active else { return }
        animator.stopAnimation(false)
        animator.finishAnimation(at: .current)
    }

    func updateButtonStates(isFavorite: Bool, isOnList: Bool) {
        // Heart and Bookmark are filled with `fill='currentColor'`; only selection turns them custom.
        favoriteButton.setImage(FavoriteButton.icon(isFavorite: isFavorite), for: .normal)

        bookmarkButton.setImage(BookmarkButton.icon(isOnList: isOnList), for: .normal)
    }

    func updatePlayButtonTitle(listStatus: String?) {
        updateScoreSpoiler(listStatus: listStatus)
        // the entry holds the progress that `of(media, eps)` counts
        updateEpisodesBadge()
        playButton.setTitle(PlayButton.title(listStatus: listStatus), for: .normal)
    }

    func applyOverscrollZoom(_ overscroll: CGFloat) {
        // BannerImage is route-owned, matching interface +layout.svelte.
    }

    // MARK: - Configure (AnimeItem from AniList)

    func configure(with item: AnimeItem) {
        anilistId = item.id
        trailerMedia = item
        malId = item.malId
        // `$: bannerSrc.value = media` in +layout.svelte: the sidebar's banner switches to this
        // media now, before its image is known.
        postSidebarBackdrop(scrollOffset: 0, alpha: bannerHidden ? 0.05 : 1.0)

        titleLabel.text = AniListUtil.title(for: item)
        romajiLabel.text = AniListUtil.alternateTitle(for: item)
        romajiLabel.isHidden = romajiLabel.text == nil

        let accent  = ExtensionSearchViewController.uiColor(fromHex: item.coverColor) ?? .white
        let contrast = ExtensionSearchViewController.luminanceContrastColor(for: accent)
        storedAccentColor = accent
        playButton.restingBackground = accent                              // bg-custom
        playButton.selectedBackground = accent.withHSLLightness(0.4)       // select:!bg-custom-600
        playButton.restingTint = contrast
        playButton.selectedTint = contrast
        entryEditorButton.restingBackground = accent.withHSLLightness(0.6)   // bg-custom-400
        entryEditorButton.selectedBackground = accent.withHSLLightness(0.3)  // select:!bg-custom-700
        entryEditorButton.restingTint = contrast
        entryEditorButton.selectedTint = contrast
        // select:!text-custom
        [favoriteButton, bookmarkButton, shareButton, trailerButton].forEach {
            $0.selectedTint = accent
        }

        refreshBadges(for: item, accent: accent, contrast: contrast)
        setGenres(item.genres.map { String($0) }, tags: item.tags)

        setDescriptionText(item.description)

        updateTrailerButton(trailerYouTubeID: item.trailerYouTubeID)

        publishBannerSource()
        // `cover(media)`
        displayedCoverURL = AniListUtil.cover(for: item)
        isCoverPressed = false
        isCoverHovered = false
        applyCoverState(animated: false)
        loadCover(displayedCoverURL, color: item.coverColor)
    }

    /// The badges under the title: what the media says, with the colors of its cover.
    private func refreshBadges(for item: AnimeItem, accent: UIColor, contrast: UIColor) {
        let seasonStr = AniListUtil.seasonText(for: item)?.capitalized

        // `search: { season: media.season, seasonYear: media.seasonYear }`, whatever the badge says
        let seasonFilter = "\(item.season ?? "")|\(item.year.map(String.init) ?? "")"

        rebuildBadges(score:    item.score,
                      status:   item.status,
                      format:   item.format,
                      season:   seasonStr,
                      seasonFilter: seasonFilter,
                      accent:   accent,
                      contrastColor: contrast)

        updateScoreSpoiler(listStatus: item.listEntry?.status)
    }

    func refreshDisplayPreferences(for item: AnimeItem) {
        titleLabel.text = AniListUtil.title(for: item)
        romajiLabel.text = AniListUtil.alternateTitle(for: item)
        romajiLabel.isHidden = romajiLabel.text == nil
        setGenres(item.genres.map { String($0) }, tags: item.tags)
        updateScoreSpoiler(listStatus: item.listEntry?.status)
    }

    /// `img/banner.svelte`: where the window is narrower than `md` the cover is the banner. From `md` on
    /// it is the backdrop of anizip, or its poster, and without them `banner(media)`: the banner of the
    /// media, the thumbnail of its trailer, the cover.
    private func publishBannerSource() {
        guard let media = trailerMedia else { return }
        let thumbnail = media.trailerYouTubeID.map { "https://i.ytimg.com/vi/\($0)/maxresdefault.jpg" }
        guard isMedium else {
            // `cover(media)`: the cover, and `banner(media)` without one
            if let url = media.coverURL ?? media.bannerURL ?? thumbnail { updateBanner(from: url) }
            return
        }
        let id = media.id
        AniListClient.fetchFanartURL(anilistID: id) { [weak self] fanartURL in
            // the window may have been made narrower, or the page may be another media's, meanwhile
            guard let self, self.trailerMedia?.id == id, self.isMedium else { return }
            let url = fanartURL ?? media.bannerURL ?? thumbnail ?? media.coverURL
            guard let url else { return }
            self.updateBanner(from: url)
        }
    }

    func updateBanner(from urlString: String) {
        displayedBannerURL = urlString
        postSidebarBackdrop(urlString: urlString,
                            scrollOffset: 0,
                            alpha: bannerHidden ? 0.05 : 1.0)
    }

    // MARK: - Badges

    private var scoreBadge: BadgeButton?
    private var episodesBadge: PaddedLabel?
    private var displayedScore: Float?

    private func updateScoreSpoiler(listStatus: String?) {
        guard let badge = scoreBadge, let score = displayedScore else { return }
        let hidden = Settings.hideSpoilers && (listStatus == "CURRENT" || listStatus == "PLANNING")
        badge.setTitle(hidden ? "50%" : String(format: "%.0f%%", score), for: .normal)
        let value = hidden ? 100 : Int(safe: Double(score))
        badge.normalBgColor = value >= 75 ? UIColor(red: 21/255, green: 128/255, blue: 61/255, alpha: 1)
            : value >= 65 ? UIColor(red: 251/255, green: 146/255, blue: 60/255, alpha: 1)
            : UIColor(red: 248/255, green: 113/255, blue: 113/255, alpha: 1)
        badge.backgroundColor = badge.normalBgColor
        badge.highlightedBgColor = value >= 75 ? UIColor(red: 22/255, green: 101/255, blue: 52/255, alpha: 1)
            : value >= 65 ? UIColor(red: 249/255, green: 115/255, blue: 22/255, alpha: 1)
            : UIColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 1)
        badge.setSpoiler(hidden)
    }

    /// `{$ofStore ?? duration(media) ?? 'N/A'}`: the episodes, with what has been watched of them, or the
    /// duration. An airing show without a count has the one its schedule and the mappings know.
    private func episodesBadgeText() -> String {
        guard let media = trailerMedia else { return "N/A" }
        // without the mappings of anizip the progress stands in for the count they know
        if let text = AniListUtil.episodesText(for: media, mappings: episodesMappingsKnown ? mappedEpisodeCount : nil) {
            return text
        }
        if let duration = media.duration, duration != 0 {
            return "\(duration) Minute\(duration > 1 ? "s" : "")"
        }
        return "N/A"
    }

    private func updateEpisodesBadge() {
        episodesBadge?.text = episodesBadgeText()
        // the badge is as wide as its text, and the ones after it follow
        badgesScrollView.setNeedsLayout()
    }

    private func rebuildBadges(score: Float?, status: String?, format: String?, season: String?,
                                seasonFilter: String,
                                accent: UIColor = .white,
                                contrastColor: UIColor = UIColor(white: 0.07, alpha: 1)) {
        var badges: [UIView] = []
        scoreBadge = nil
        displayedScore = score

        let episodes = makeBadge(text: episodesBadgeText(), accent: accent, contrast: contrastColor)
        episodesBadge = episodes as? PaddedLabel
        badges.append(episodes)

        do {
            let display: String
            if let fmt = format {
                switch fmt {
                case "TV":       display = "TV Series"
                case "TV_SHORT": display = "TV Short"
                case "MOVIE":    display = "Movie"
                case "SPECIAL":  display = "Special"
                case "OVA":      display = "OVA"
                case "ONA":      display = "ONA"
                case "MUSIC":    display = "Music"
                default:         display = fmt.replacingOccurrences(of: "_", with: " ").capitalized
                }
            } else {
                display = "N/A"
            }
            badges.append(makeBadge(text: display, accent: accent, contrast: contrastColor,
                                    filterType: format != nil ? "format" : nil,
                                    filterValue: format))
        }

        do {
            let display: String
            if let st = status {
                switch st {
                case "RELEASING":        display = "Releasing"
                case "NOT_YET_RELEASED": display = "Not Yet Released"
                case "FINISHED":         display = "Finished"
                case "CANCELLED":        display = "Cancelled"
                case "HIATUS":           display = "Hiatus"
                default:                 display = st.replacingOccurrences(of: "_", with: " ").capitalized
                }
            } else {
                display = "N/A"
            }
            badges.append(makeBadge(text: display, accent: accent, contrast: contrastColor,
                                    filterType: status != nil ? "status" : nil,
                                    filterValue: status))
        }

        if let szn = season, !szn.isEmpty {
            badges.append(makeBadge(text: szn, accent: accent, contrast: contrastColor,
                                    filterType: "season", filterValue: seasonFilter))
        }

        if let sc = score, sc > 0 {
            let scoreBG: UIColor
            let scoreInt = Int(safe: Double(sc))
            if scoreInt >= 75 {
                scoreBG = UIColor(red: 21/255.0, green: 128/255.0, blue: 61/255.0, alpha: 1)
            } else if scoreInt >= 65 {
                scoreBG = UIColor(red: 251/255.0, green: 146/255.0, blue: 60/255.0, alpha: 1)
            } else {
                scoreBG = UIColor(red: 248/255.0, green: 113/255.0, blue: 113/255.0, alpha: 1)
            }
            let badge = makeBadge(text: String(format: "%.0f%%", sc),
                                                      accent: scoreBG,
                                                      contrast: contrastColor,
                                                      filterType: "score",
                                                      filterValue: "SCORE_DESC")
            scoreBadge = badge as? BadgeButton
            badges.append(badge)
        }

        badgesScrollView.setBadges(badges)
    }

    private func makeBadge(text: String,
                            accent: UIColor = .white,
                            contrast: UIColor = UIColor(white: 0.07, alpha: 1),
                            filterType: String? = nil,
                            filterValue: String? = nil) -> UIView {
        if let filterType = filterType, let filterValue = filterValue {
            let btn = BadgeButton(type: .custom)
            btn.setTitle(text, for: .normal)
            btn.titleLabel?.font = .nunito(ofSize: 16, weight: .bold)
            btn.setTitleColor(contrast, for: .normal)
            btn.normalBgColor = accent
            btn.highlightedBgColor = accent.withHSLLightness(0.4)   // select:!bg-custom-600
            btn.backgroundColor = accent
            btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            btn.layer.cornerRadius = 4
            btn.clipsToBounds = true
            btn.filterType = filterType
            btn.filterValue = filterValue
            btn.addTarget(self, action: #selector(detailBadgeTapped(_:)), for: .touchUpInside)
            return btn
        } else {
            let l = PaddedLabel()
            l.text = text
            l.font = .nunito(ofSize: 16, weight: .bold)
            l.textColor = contrast
            l.backgroundColor = accent
            l.contentInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            l.layer.cornerRadius = 4
            l.clipsToBounds = true
            l.textAlignment = .center
            return l
        }
    }

    private class BadgeButton: UIButton {
        var normalBgColor: UIColor = .white
        var highlightedBgColor: UIColor = .gray
        var filterType: String = ""
        var filterValue: String = ""
        private let spoilerLabel = UILabel()
        private lazy var spoilerTitle = HayaseContentBlurView(content: spoilerLabel)
        private var masksScore = false

        func setSpoiler(_ hidden: Bool) {
            masksScore = hidden
            if spoilerTitle.superview == nil {
                spoilerTitle.isUserInteractionEnabled = false
                addSubview(spoilerTitle)
            }
            spoilerLabel.text = title(for: .normal)
            spoilerLabel.font = titleLabel?.font
            spoilerLabel.textColor = titleColor(for: .normal)
            spoilerTitle.radius = hidden ? 3 : 0
            spoilerTitle.isHidden = !hidden
            titleLabel?.alpha = hidden ? 0 : 1
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            spoilerTitle.frame = titleLabel?.frame ?? .zero
            titleLabel?.alpha = masksScore ? 0 : 1
        }

        private var isPointerOver = false

        func installHover() {
            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        }

        @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
            isPointerOver = recognizer.state == .began || recognizer.state == .changed
            updateBackground()
        }

        override var isHighlighted: Bool {
            didSet { updateBackground() }
        }

        /// transition-colors: 150ms
        private func updateBackground() {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.backgroundColor = self.isHighlighted || self.isPointerOver ? self.highlightedBgColor : self.normalBgColor
            }
        }
    }

    @objc private func detailBadgeTapped(_ sender: BadgeButton) {
        onBadgeTapped?(sender.filterType, sender.filterValue)
    }

    // MARK: - Description

    private func setDescriptionText(_ raw: String?) {
        rawDescription = raw
        applyDescriptionAttributedText(interfaceDescription(from: raw))
    }

    /// `desc(media)`: the description has been through `AniListUtil.stripHTML` when the media was read,
    /// which is `desc()` of the interface; what has none says so.
    private func interfaceDescription(from raw: String?) -> String {
        raw ?? "No description available."
    }

    private func applyDescriptionAttributedText(_ text: String) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let font = descriptionLabel.font ?? .nunito(ofSize: 14, weight: .light)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.HayaseTheme.mutedForeground,
            .paragraphStyle: para,
        ]
        descriptionLabel.attributedText = NSAttributedString(string: text, attributes: attrs)
    }

    // MARK: - Genres

    private func setGenres(_ genres: [String], tags: [AnimeTag] = []) {
        let showHentai = Settings.showHentai
        let sortedTags = tags
            .filter { !$0.isAdult || showHentai }
            .sorted {
                if $0.rank != $1.rank { return $0.rank > $1.rank }
                return $0.id < $1.id
            }
        let chips = genres.map { makeGenreChip(text: $0, isTag: false, isSpoiler: false) }
            + sortedTags.map { makeGenreChip(text: $0.name, isTag: true, isSpoiler: $0.isMediaSpoiler || $0.isGeneralSpoiler) }
        genresScrollView.setChips(chips)
        genresContainer.isHidden = chips.isEmpty
        resetGenresScrollPosition()
    }

    func updateGenresAndTrailer(genres: [String], tags: [AnimeTag] = [], trailerYouTubeID: String?) {
        setGenres(genres, tags: tags)
        trailerButton.isHidden = trailerYouTubeID == nil
    }

    func updateAnimePageDetails(with item: AnimeItem) {
        anilistId = item.id
        trailerMedia = item
        malId = item.malId
        titleLabel.text = AniListUtil.title(for: item)
        romajiLabel.text = AniListUtil.alternateTitle(for: item)
        romajiLabel.isHidden = romajiLabel.text == nil
        // `media = $info.data?.Media ?? $anime.Media`: everything the header shows is of the newest media
        let accent = ExtensionSearchViewController.uiColor(fromHex: item.coverColor) ?? .white
        refreshBadges(for: item, accent: accent, contrast: ExtensionSearchViewController.luminanceContrastColor(for: accent))
        setDescriptionText(item.description)
        setGenres(item.genres, tags: item.tags)
        updateTrailerButton(trailerYouTubeID: item.trailerYouTubeID)
        updateMALButtonVisibility()
    }

    func updateTrailerButton(trailerYouTubeID: String?) {
        hasTrailer = trailerYouTubeID != nil
        if trailerYouTubeID != trailerVideoID {
            // `$: trailerMinutes = minutes(trailerId)`
            trailerVideoID = trailerYouTubeID
            trailerMinutes = 0
            trailerMinutesLoader?.cancel()
            trailerMinutesLoader = trailerYouTubeID.flatMap { id in
                TrailerMinutes.load(videoID: id) { [weak self] minutes in
                    self?.trailerMinutes = minutes
                    self?.updateTrailerTooltip()
                }
            }
        }
        updateActionVisibilityForCurrentWidth()
    }

    /// `eps?.episodeCount`, what `episodes(media, eps)` counts besides the media itself. `known` is
    /// whether there is an `eps` at all.
    func setMappedEpisodeCount(_ count: Int?, known: Bool = true) {
        mappedEpisodeCount = count ?? 0
        episodesMappingsKnown = known
        updateEpisodesBadge()
        updateTrailerTooltip()
    }

    // MARK: - Also available on YouTube!

    /// `(count === 1 || !count) && media.duration && $trailerMinutes === media.duration`, with
    /// `count = episodes(media, eps)`.
    private var trailerIsMedia: Bool {
        guard let media = trailerMedia, let duration = media.duration, duration != 0 else { return false }
        let count: Int
        if let episodes = media.episodes, episodes != 0 {
            count = episodes
        } else {
            count = max(media.airedSchedule.last?.episode ?? 0, media.notYetAiredSchedule.last?.episode ?? 0, mappedEpisodeCount)
        }
        return (count == 1 || count == 0) && trailerMinutes == duration
    }

    private var enclosingTableView: UITableView? {
        var view = superview
        while let current = view, !(current is UITableView) { view = current.superview }
        return view as? UITableView
    }

    /// The tooltip is open as long as the trailer button is shown and the trailer is the media.
    private func updateTrailerTooltip() {
        guard window != nil, !trailerButton.isHidden, trailerIsMedia, let table = enclosingTableView else {
            NSLayoutConstraint.deactivate(trailerTooltipConstraints)
            trailerTooltipConstraints = []
            trailerTooltipMedium = nil
            trailerTooltip?.removeFromSuperview()
            trailerTooltip = nil
            return
        }
        if let tooltip = trailerTooltip {
            if tooltip.superview !== table {
                NSLayoutConstraint.deactivate(trailerTooltipConstraints)
                trailerTooltipConstraints = []
                table.addSubview(tooltip)
            }
            positionTrailerTooltip()
            return
        }
        let tooltip = TrailerTooltipView()
        tooltip.translatesAutoresizingMaskIntoConstraints = false
        tooltip.layer.zPosition = 1000   // z-50
        table.addSubview(tooltip)
        trailerTooltip = tooltip
        positionTrailerTooltip()
        // flyAndScale in, 150ms
        tooltip.alpha = 0
        tooltip.transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.95, y: 0.95)
        // Wait until the header's current layout pass is over before resolving
        // the portal constraints. Never animate in from an unresolved zero frame.
        DispatchQueue.main.async { [weak self, weak tooltip] in
            guard let self, let tooltip, self.trailerTooltip === tooltip else { return }
            tooltip.superview?.layoutIfNeeded()
            UIView.animate(withDuration: 0.15) {
                tooltip.alpha = 1
                tooltip.transform = .identity
            }
        }
    }

    /// Keep a live anchor like TooltipPrimitive.Content: table section reloads
    /// can move/reparent the header without calling its layoutSubviews again.
    /// A copied frame in table coordinates drifts when that happens.
    private func positionTrailerTooltip() {
        guard let tooltip = trailerTooltip, let table = enclosingTableView,
              tooltip.superview === table else { return }
        let medium = (window?.rootViewController?.view.bounds.width ?? bounds.width) >= 768
        tooltip.configure(medium: medium)
        let size = tooltip.fittingSize

        // Removing/reparenting the header/button automatically deactivates its
        // cross-hierarchy anchor. Rebuild it against the current table, not an
        // old reusable cell. Keep the tooltip outside the header's fitting size.
        if trailerTooltipConstraints.first?.isActive != true || trailerTooltipMedium != medium {
            NSLayoutConstraint.deactivate(trailerTooltipConstraints)
            let alignment = medium
                ? tooltip.leadingAnchor.constraint(equalTo: trailerButton.leadingAnchor)
                : tooltip.trailingAnchor.constraint(equalTo: trailerButton.trailingAnchor)
            alignment.priority = UILayoutPriority(998)
            let rightEdge = tooltip.trailingAnchor.constraint(lessThanOrEqualTo: table.frameLayoutGuide.trailingAnchor)
            // A temporarily zero-width table during attachment must not create
            // an unsatisfiable required constraint; normal widths still clamp.
            rightEdge.priority = UILayoutPriority(999)
            trailerTooltipConstraints = [
                tooltip.topAnchor.constraint(equalTo: trailerButton.bottomAnchor, constant: 4),
                tooltip.widthAnchor.constraint(equalToConstant: size.width),
                tooltip.heightAnchor.constraint(equalToConstant: size.height),
                tooltip.leadingAnchor.constraint(greaterThanOrEqualTo: table.frameLayoutGuide.leadingAnchor),
                rightEdge,
                alignment,
            ]
            trailerTooltipMedium = medium
            NSLayoutConstraint.activate(trailerTooltipConstraints)
        } else {
            trailerTooltipConstraints.first { $0.firstAttribute == .width }?.constant = size.width
            trailerTooltipConstraints.first { $0.firstAttribute == .height }?.constant = size.height
        }
    }

    func updateMALButtonVisibility() {
        updateActionVisibilityForCurrentWidth()
    }

    func updateFollowingAvatars(users: [AniListUserSummary]) {
        headerFollowerStack.configure(users: users,
                                      avatarSize: 32,
                                      ringWidth: 4,
                                      ringColor: UIColor.HayaseTheme.background)
        updateActionVisibilityForCurrentWidth()
    }

    func clearFollowingAvatars() {
        headerFollowerStack.reset()
    }

    private func makeGenreChip(text: String, isTag: Bool, isSpoiler: Bool) -> AnimeTagChipButton {
        let btn = AnimeTagChipButton(frame: .zero)
        btn.setTitle(text, for: .normal)
        btn.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        btn.restingTitleColor = isTag ? UIColor.HayaseTheme.mutedForeground : UIColor.HayaseTheme.secondaryForeground
        btn.selectedTitleColor = storedAccentColor   // select:!text-custom
        btn.restingBackground = UIColor.HayaseTheme.secondary.withAlphaComponent(isTag ? 0.4 : 1)
        btn.selectedBackground = UIColor.HayaseTheme.secondary.withAlphaComponent(0.6)   // select:bg-secondary/60
        btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        btn.layer.cornerRadius = 6
        // CSS filter paints beyond the text/button box; clipping here chops
        // the 6px Gaussian halo off at the top and bottom of spoiler tags.
        btn.layer.masksToBounds = false
        if isTag {
            btn.layer.shadowColor = UIColor.black.cgColor
            btn.layer.shadowOpacity = 0.05
            btn.layer.shadowOffset = CGSize(width: 0, height: 1)
            btn.layer.shadowRadius = 1
        }
        btn.dashedBorder = isTag
        btn.isTagChip = isTag
        btn.isSpoilerChip = isSpoiler
        btn.addTarget(self, action: #selector(genreChipTapped(_:)), for: .touchUpInside)
        return btn
    }

    @objc private func genreChipTapped(_ sender: UIButton) {
        guard let genre = sender.title(for: .normal) else { return }
        // `search: { genre: [genre] }` and `search: { tag: [tag.name] }`
        onGenreTapped?(genre, (sender as? AnimeTagChipButton)?.isTagChip ?? false)
    }

    // MARK: - Image loading

    /// img/load.svelte: `style:background={color ?? '#1890ff'}`
    static func coverBackground(_ hex: String?) -> UIColor {
        ExtensionSearchViewController.uiColor(fromHex: hex) ?? UIColor(red: 24 / 255, green: 144 / 255, blue: 255 / 255, alpha: 1)
    }

    /// `<Load src={cover(media)} color={media.coverImage?.color}>`: the picture fades in on the color of the
    /// cover, from 6pt blurred when it is there at once, when the page is made. Another `src` is swapped in
    /// where the old one was, without the fade: `load-in` has run by then.
    private func loadCover(_ urlString: String?, color: String?) {
        coverImageView.backgroundColor = Self.coverBackground(color)
        // the same cover is not loaded again
        guard urlString != loadedCoverURL || coverPicture.image == nil else { return }

        coverImageTask?.cancel()
        coverImageTask = nil
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return }
        loadedCoverURL = urlString
        let announcedAt = CACurrentMediaTime()

        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            showCover(cached, blurred: true)
            return
        }
        coverImageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
            DispatchQueue.main.async {
                guard let self, self.loadedCoverURL == urlString else { return }
                self.showCover(image, blurred: CACurrentMediaTime() - announcedAt < LoadIn.blurWindow)
            }
        }
        coverImageTask?.resume()
    }

    private func showCover(_ image: UIImage, blurred: Bool) {
        if coverPicture.image == nil {
            LoadIn.show(image, in: coverPicture, blurred: blurred)
        } else {
            coverPicture.image = image
        }
    }
}

// MARK: - AnimeDetailViewController

class AnimeDetailViewController: UIViewController {
    private var renderedDisplayPreferences: Settings.DisplayPreferences?

    var animeItem: AnimeItem?
    var routeAnimeID: Int? { animeItem?.id }

    var tableView: UITableView!
    private let animeBackdropView = AnimeDetailBannerBackdropView()
    private let animeBackdropCoverView: UIView = {
        let view = UIView()
        view.backgroundColor = hayasePageBackground
        view.alpha = 0
        view.isUserInteractionEnabled = false
        return view
    }()
    private var isAnimeBackdropCovered = false
    private var animeBackdropCoverTransitionID = 0
    private var pendingAnimeBannerRevealWorkItem: DispatchWorkItem?
    private let animeBannerRevealDelay: DispatchTimeInterval = .milliseconds(120)
    private var animeBackdropLeadingConstraint: NSLayoutConstraint?
    private var animeBackdropTrailingConstraint: NSLayoutConstraint?
    var headerView: AnimeInfoHeaderView!
    var isFavorite = false
    var isOnList = false
    var episodes: [AniZipEpisode] = []
    var anilistProgress: Int = 0
    var currentListStatus: String?
    var currentAnimeAccent: UIColor = .white
    var relationGraph: AnimeRelationGraph?
    var relationGraphExpanded = false

    let episodesPerPage = 16
    var currentEpisodePage: Int = 1
    private var pendingEpisodeHeightInvalidation = false
    var paginatedEpisodes: [AniZipEpisode] {
        let start = (currentEpisodePage - 1) * episodesPerPage
        let end = min(start + episodesPerPage, episodes.count)
        guard start < episodes.count else { return [] }
        return Array(episodes[start..<end])
    }

    var usesSingleEpisodeGridTrack: Bool {
        // CSS repeat(auto-fit,minmax(500px,1fr)) collapses empty tracks only
        // when the rendered page has one item. Odd rows on multi-card pages keep
        // their second grid track; one-card pages, including movies, stretch.
        episodeColumnCount >= 2 && paginatedEpisodes.count == 1
    }

    var totalEpisodePages: Int {
        max(1, Int(ceil(Double(episodes.count) / Double(episodesPerPage))))
    }

    private func interfaceEpisodePage(progress: Int, listStatus: String?) -> Int {
        let effectiveProgress = listStatus == "COMPLETED" ? 0 : max(0, progress)
        let desiredPage = effectiveProgress / episodesPerPage + 1
        return min(max(1, desiredPage), totalEpisodePages)
    }

    func syncEpisodePageToInterfaceProgress() {
        currentEpisodePage = interfaceEpisodePage(progress: anilistProgress, listStatus: currentListStatus)
    }
    lazy var paginationBar: PaginationBarView = {
        let bar = PaginationBarView()
        bar.onPageChange = { [weak self] page in
            self?.setEpisodePage(page)
        }
        return bar
    }()

    /// The threads of the page that is on show, `Threads.svelte`'s `$threads`.
    var threads: [AniListThread] = []
    /// `currentPage` of `Threads.svelte`, which is 1 whenever the tab is opened.
    var threadsPage = 1
    /// The pages of threads that were answered, with their totals: `cache-first`, a page that was seen
    /// is not asked for again.
    var threadPages: [Int: (threads: [AniListThread], total: Int)] = [:]
    /// The request of a page after the first, which the page of the media itself brings with it.
    var threadsPageLoading = false
    var threadsPageError: String?
    var themes: [AnimeThemesTheme] = []
    var recommendations: [AnimeItem] = []
    var followingEntriesByEpisode: [Int: [AniListUserSummary]] = [:]
    var activeThemeVideoURL: String?
    var recommendationsLoading = false
    var themesLoading = false
    var animePageRequestID = UUID()
    var animePageErrorDescription: String?
    var hasCompletedInitialAnimeLayout = false
    var pendingAnimePagePayloadReload = false
    var pendingAnimePagePayloadReloadIncludesHeader = false
    var hasStartedInitialAnimeLoads = false

    var activeSection: Section = .episodes
    var recommendationComponentMountGeneration: UInt = 0
    var embeddedThreadID: Int?
    var embeddedThreadTitle: String?
    var embeddedThreadViewController: ThreadDetailViewController?

    lazy var tabBar: HTabBar = {
        let bar = HTabBar(titles: ["Episodes", "Relations", "Threads", "Themes", "Recommendations"])
        bar.onChange = { [weak self] index in
            self?.tabChanged(to: index)
        }
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    var tabBarScrollView: UIScrollView?
    private var tabBarTopConstraint: NSLayoutConstraint?

    lazy var tabBarContainer: UIView = {
        let v = UIView()
        v.backgroundColor = hayasePageBackground
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        tabBarScrollView = scrollView
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(scrollView)
        scrollView.addSubview(tabBar)

        // `gap-4 md:gap-6` between the genres and the tabs
        let top = scrollView.topAnchor.constraint(equalTo: v.topAnchor, constant: isMediumViewport ? 24 : 16)
        tabBarTopConstraint = top

        NSLayoutConstraint.activate([
            top,
            scrollView.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8),

            tabBar.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            tabBar.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        return v
    }()

    func applyTabBarLayoutForSizeClass() {
        tabBar.isVertical = false
        tabBarTopConstraint?.constant = isMediumViewport ? 24 : 16
        let sideInset = Self.interfacePageSideInset(for: viewportWidth)
        tabBarScrollView?.contentInset = UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: sideInset)
        tabBarScrollView?.scrollIndicatorInsets = tabBarScrollView?.contentInset ?? .zero
    }

    enum Section: Int, CaseIterable {
        case header = 0, episodes, episodePagination, relations, threads, threadPagination, themes, recommendations
    }

    static let gridMinColWidth: CGFloat = 500
    static let episodeGap: CGFloat = 16
    static let threadGap: CGFloat = 40

    /// Interface inner wrapper: `2xs:px-3 xl:px-14`, media queries of the window (360 and 1280).
    static func interfacePageSideInset(for width: CGFloat) -> CGFloat {
        width >= 1280 ? 56 : (width >= 360 ? 12 : 0)
    }

    /// The window, which is what the media queries of the interface (`md`, `xl`) are asked.
    var viewportWidth: CGFloat {
        view.window?.bounds.width ?? UIScreen.main.bounds.width
    }

    /// `md`
    var isMediumViewport: Bool { viewportWidth >= 768 }

    /// The width of the grids of the page: the page without its padding.
    var pageGridWidth: CGFloat {
        tableView.frame.width - 2 * Self.interfacePageSideInset(for: viewportWidth)
    }

    var episodeColumnCount: Int {
        // `grid-cols-1 sm:grid-cols-[repeat(auto-fit,minmax(500px,1fr))]`
        pageGridWidth >= 2 * Self.gridMinColWidth + Self.episodeGap ? 2 : 1
    }

    /// Threads.svelte uses the episode grid's repeat(auto-fit,minmax(500px,1fr)),
    /// so a list of one thread collapses to a single full-width track.
    var threadGridColumnCount: Int {
        threads.count == 1 ? 1 : threadColumnCount
    }

    var threadColumnCount: Int {
        pageGridWidth >= 2 * Self.gridMinColWidth + Self.threadGap ? 2 : 1
    }

    // MARK: - Search navigation helpers

    func navigateToSearchTab(name: String, isTag: Bool) {
        let state = Route.SearchState(genres: isTag ? [] : [name], tags: isTag ? [name] : [])
        Router.shared.navigate(.search(state), hostTabIndex: hayaseTabIndex)
    }

    func navigateToSearchTab(filterType: String, value: String) {
        var state = Route.SearchState()
        switch filterType {
        case "format":
            state.formats = [value]
        case "status":
            state.statuses = [value]
        case "season":
            // "SEASON|YEAR" of the media, either of them empty when it has none
            let parts = value.components(separatedBy: "|")
            if let season = parts.first, !season.isEmpty { state.season = season }
            if parts.count > 1, !parts[1].isEmpty { state.year = parts[1] }
        case "score":
            state.sort = value
        default:
            break
        }
        Router.shared.navigate(.search(state), hostTabIndex: hayaseTabIndex)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = nil
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = hayasePageBackground

        setupAnimeBackdropView()
        setupTableView()
        setupHeaderView()
        observeAnimeBackdrop()
        NotificationCenter.default.addObserver(self, selector: #selector(refocusAnimePage),
                                               name: AniListRefocus.didRefocus, object: nil)
        // `$mediaListEntry` is a store: an entry saved elsewhere, the lists loading again and another
        // tracker's answer all show on the page that is open
        NotificationCenter.default.addObserver(self, selector: #selector(viewerListsChanged),
                                               name: AniListViewerState.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(viewerListsChanged),
                                               name: LocalTracking.didChange, object: nil)
        // `liveAnimeProgress` is derived from a store: the bar of the episode follows what the player writes
        NotificationCenter.default.addObserver(self, selector: #selector(watchProgressChanged),
                                               name: WatchProgressService.didChange, object: nil)
        headerView?.clearFollowingAvatars()
        applyTabBarLayoutForSizeClass()
        applyViewerStateFromRouteMedia()
        let preferences = Settings.DisplayPreferences()
        if let previous = renderedDisplayPreferences, previous != preferences {
            if let item = animeItem { headerView?.refreshDisplayPreferences(for: item) }
            headerView?.updatePlayButtonTitle(listStatus: currentListStatus)
            tableView.reloadData()
        }
        renderedDisplayPreferences = preferences
        headerView?.publishSidebarBackdrop()
    }

    deinit {
        pendingAnimeBannerRevealWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let nb = navigationController?.navigationBar
        nb?.setBackgroundImage(UIImage(), for: .default)
        nb?.shadowImage = UIImage()
        nb?.tintColor = .white

        headerView?.publishSidebarBackdrop()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        markInitialAnimeLayoutCompleteIfReady()
        startInitialAnimeLoadsIfReady()
        // `liveAnimeProgress` is a store: what was played meanwhile is on the bar of its episode
        if activeSection == .episodes, !episodes.isEmpty, embeddedThreadID == nil {
            refreshEpisodeCardsInPlace()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        markInitialAnimeLayoutCompleteIfReady()
        startInitialAnimeLoadsIfReady()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let nb = navigationController?.navigationBar
        nb?.setBackgroundImage(nil, for: .default)
        nb?.shadowImage = nil
        nb?.tintColor = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded else { return }
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            configureAnimeBackdropForCurrentSize()
            applyTabBarLayoutForSizeClass()
            tableView.reloadData()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard isViewLoaded else { return }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.configureAnimeBackdropForCurrentSize(width: size.width)
            self.tableView.reloadData()
        }, completion: { [weak self] _ in
            // the window has its new size now, and the page asks it where it crosses `md` and `xl`
            guard let self else { return }
            self.applyTabBarLayoutForSizeClass()
            self.tableView.reloadData()
        })
    }

    @discardableResult
    private func markInitialAnimeLayoutCompleteIfReady() -> Bool {
        guard !hasCompletedInitialAnimeLayout,
              tableView != nil,
              tableView.window != nil,
              tableView.bounds.width > 1,
              tableView.bounds.height > 1 else { return hasCompletedInitialAnimeLayout }
        hasCompletedInitialAnimeLayout = true
        flushPendingAnimePagePayloadReload()
        return true
    }

    private func startInitialAnimeLoadsIfReady() {
        guard !hasStartedInitialAnimeLoads,
              hasCompletedInitialAnimeLayout,
              tableView != nil,
              tableView.window != nil,
              tableView.bounds.width > 1,
              tableView.bounds.height > 1 else { return }
        hasStartedInitialAnimeLoads = true
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.tableView != nil,
                  self.tableView.window != nil else { return }
            self.fetchAnimePageData()
            self.fetchEpisodes()
        }
    }

    func canReloadAnimePagePayloadSections() -> Bool {
        tableView != nil
            && hasCompletedInitialAnimeLayout
            && tableView.window != nil
            && tableView.bounds.width > 1
            && tableView.bounds.height > 1
    }

    func flushPendingAnimePagePayloadReload() {
        guard pendingAnimePagePayloadReload,
              canReloadAnimePagePayloadSections() else { return }
        let includeHeader = pendingAnimePagePayloadReloadIncludesHeader
        pendingAnimePagePayloadReload = false
        pendingAnimePagePayloadReloadIncludesHeader = false
        reloadAnimePagePayloadSections(includeHeader: includeHeader)
    }

    // MARK: - Setup

    private func setupAnimeBackdropView() {
        animeBackdropView.translatesAutoresizingMaskIntoConstraints = false
        animeBackdropCoverView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(animeBackdropView)
        view.addSubview(animeBackdropCoverView)
        let animeBackdropLeadingConstraint = animeBackdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        self.animeBackdropLeadingConstraint = animeBackdropLeadingConstraint
        let animeBackdropTrailingConstraint = animeBackdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        self.animeBackdropTrailingConstraint = animeBackdropTrailingConstraint
        NSLayoutConstraint.activate([
            animeBackdropView.topAnchor.constraint(equalTo: view.topAnchor),
            animeBackdropLeadingConstraint,
            animeBackdropTrailingConstraint,

            animeBackdropCoverView.topAnchor.constraint(equalTo: view.topAnchor),
            animeBackdropCoverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            animeBackdropCoverView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            animeBackdropCoverView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        configureAnimeBackdropForCurrentSize()
    }

    private func configureAnimeBackdropForCurrentSize(width: CGFloat? = nil) {
        let viewportSize: CGSize
        if let width {
            viewportSize = CGSize(width: width, height: view.window?.bounds.height ?? view.bounds.height)
        } else {
            viewportSize = view.window?.bounds.size ?? view.bounds.size
        }
        let hasSidebar = Self.usesDesktopSidebar(viewportSize: viewportSize,
                                                 traits: traitCollection)
        animeBackdropLeadingConstraint?.constant = hasSidebar ? -56 : 0
        animeBackdropTrailingConstraint?.constant = 0
        animeBackdropView.configure(height: 368, compact: viewportSize.width < 768)
    }

    private static func usesDesktopSidebar(viewportSize: CGSize,
                                           traits: UITraitCollection) -> Bool {
        let isPhoneLandscape = traits.userInterfaceIdiom == .phone
            && viewportSize.width > viewportSize.height
            && viewportSize.width >= 568
        return viewportSize.width >= 768
            || traits.horizontalSizeClass == .regular
            || isPhoneLandscape
    }

    private func observeAnimeBackdrop() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(animeBackdropDidChange(_:)),
                                               name: hayaseAnimeBannerBackdropDidChange,
                                               object: nil)
    }

    func applyAnimeBannerScrollEffects(scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        if offsetY < 0 {
            cancelPendingAnimeBannerReveal()
            headerView.applyOverscrollZoom(-offsetY)
            applyAnimeBannerVisibility(hidden: false)
            return
        }

        headerView.applyOverscrollZoom(0)
        if offsetY > 100 {
            cancelPendingAnimeBannerReveal()
            applyAnimeBannerVisibility(hidden: true)
        } else if shouldRevealAnimeBannerImmediately(offsetY: offsetY, scrollView: scrollView) {
            cancelPendingAnimeBannerReveal()
            applyAnimeBannerVisibility(hidden: false)
        } else {
            scheduleAnimeBannerRevealIfNeeded()
        }
    }

    private func shouldRevealAnimeBannerImmediately(offsetY: CGFloat, scrollView: UIScrollView) -> Bool {
        guard offsetY > 0 else { return true }
        if scrollView.isDragging {
            return scrollView.panGestureRecognizer.velocity(in: scrollView).y > 0
        }
        return !scrollView.isDecelerating && !scrollView.isTracking
    }

    private func applyAnimeBannerVisibility(hidden: Bool) {
        let effectiveOffset: CGFloat = hidden ? 101 : 0
        headerView.applyScrollFade(effectiveOffset)
    }

    private func scheduleAnimeBannerRevealIfNeeded() {
        guard pendingAnimeBannerRevealWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingAnimeBannerRevealWorkItem = nil
            guard self.tableView.contentOffset.y <= 100 else { return }
            self.applyAnimeBannerVisibility(hidden: false)
        }
        pendingAnimeBannerRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + animeBannerRevealDelay, execute: workItem)
    }

    private func cancelPendingAnimeBannerReveal() {
        pendingAnimeBannerRevealWorkItem?.cancel()
        pendingAnimeBannerRevealWorkItem = nil
    }

    private func transitionAnimeBackdropCover(hidden: Bool) {
        let targetCoverAlpha: CGFloat = hidden ? 1 : 0
        guard hidden != isAnimeBackdropCovered || abs(animeBackdropCoverView.alpha - targetCoverAlpha) > 0.001 else { return }

        animeBackdropCoverTransitionID += 1
        let transitionID = animeBackdropCoverTransitionID
        isAnimeBackdropCovered = hidden

        // banner-image.svelte: `transition-opacity duration-500`
        if hidden {
            animeBackdropView.applyAlpha(1.0, animated: false)
            BannerImage.fade([animeBackdropCoverView], to: 1) { [weak self] in
                guard let self, self.animeBackdropCoverTransitionID == transitionID else { return }
                self.animeBackdropView.applyAlpha(BannerImage.hiddenAlpha, animated: false)
            }
        } else {
            animeBackdropView.applyAlpha(1.0, animated: false)
            BannerImage.fade([animeBackdropCoverView], to: 0)
        }
    }

    @objc private func animeBackdropDidChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              info[hayaseAnimeBannerBackdropRouteKey] as? String == hayaseAnimeBannerBackdropAnimeRoute else { return }
        if let height = info[hayaseAnimeBannerBackdropHeightKey] as? CGFloat {
            animeBackdropView.configure(height: height, compact: view.bounds.width < 768)
        }
        if let urlString = info[hayaseAnimeBannerBackdropURLKey] as? String {
            animeBackdropView.setImage(urlString: urlString)
        }
        if let scrollOffset = info[hayaseAnimeBannerBackdropScrollOffsetKey] as? CGFloat {
            animeBackdropView.applyScrollOffset(scrollOffset)
        }
        if let alpha = info[hayaseAnimeBannerBackdropAlphaKey] as? CGFloat {
            transitionAnimeBackdropCover(hidden: alpha <= 0.05)
        }
    }

    func setupTableView() {
        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.delegate = self
        tableView.dataSource = self
        // Browser :active begins on pointer-down. This table wraps nested card collections, so
        // its default delayed touch delivery must not postpone the inner card highlight.
        tableView.delaysContentTouches = false
        tableView.bounces = false
        tableView.alwaysBounceVertical = false
        tableView.register(EpisodeCell.self, forCellReuseIdentifier: EpisodeCell.reuseID)
        tableView.register(EpisodePairCell.self, forCellReuseIdentifier: EpisodePairCell.reuseID)
        tableView.register(ThreadPairCell.self, forCellReuseIdentifier: ThreadPairCell.reuseID)
        tableView.register(RelationGraphCell.self, forCellReuseIdentifier: RelationGraphCell.reuseID)
        tableView.register(RecommendationGridCell.self, forCellReuseIdentifier: RecommendationGridCell.reuseID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HeaderCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PaginationCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.contentInsetAdjustmentBehavior = .never
        let tabBarH: CGFloat = 83
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: tabBarH, right: 0)
        tableView.scrollIndicatorInsets = tableView.contentInset
        tableView.clipsToBounds = false
        // app/anime/[id]/+layout.svelte expands the scroll viewport left with -ml-14,
        // so selected episode cards can scale/ring without being clipped at the route edge.
        view.clipsToBounds = false
        view.addSubview(tableView)
    }

    func setupHeaderView() {
        headerView = AnimeInfoHeaderView()
        if let item = animeItem {
            headerView.configure(with: item)
            if let accent = ExtensionSearchViewController.uiColor(fromHex: item.coverColor) {
                tabBar.accentColor = accent
                currentAnimeAccent = accent
            }
        }
        headerView.onFavorite = { [weak self] in
            guard let self, let item = self.animeItem else { return }
            AniListTracking.shared.toggleFavourite(mediaID: item.id) { [weak self] success in
                guard success else { return }
                DispatchQueue.main.async {
                    self?.isFavorite.toggle()
                    self?.animeItem?.isFavourite = self?.isFavorite
                    self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false,
                                                         isOnList: self?.isOnList ?? false)
                }
            }
        }

        headerView.onBookmark = { [weak self] in
            guard let self, let item = self.animeItem else { return }
            if self.isOnList {
                guard let listID = item.listEntry?.listID else { return }
                AniListTracking.shared.deleteEntry(listID: listID, mediaID: item.id) { [weak self] deleted in
                    guard deleted else { return }
                    DispatchQueue.main.async {
                        self?.updateAnimeItemListEntry(nil)
                        self?.isOnList = false
                        self?.syncEpisodePageToInterfaceProgress()
                        self?.tableView.reloadData()
                        self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false, isOnList: false)
                        self?.headerView?.updatePlayButtonTitle(listStatus: nil)
                    }
                }
            } else {
                AniListTracking.shared.entry(mediaID: item.id, status: "PLANNING") { [weak self] entry in
                    DispatchQueue.main.async {
                        self?.updateAnimeItemListEntry(entry)
                        self?.isOnList = entry != nil
                        self?.syncEpisodePageToInterfaceProgress()
                        self?.tableView.reloadData()
                        self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false,
                                                             isOnList: self?.isOnList ?? false)
                        self?.headerView?.updatePlayButtonTitle(listStatus: entry?.status)
                    }
                }
            }
        }

        headerView.onShare = { [weak self] in
            guard let self = self, let item = self.animeItem else { return }
            // `native.share({ title: 'Watch on Hayase - …romaji', text: desc(media), url })`
            var items: [Any] = [item.description ?? "No description available."]
            if let url = URL(string: "https://hayase.watch/anime/\(item.id)") {
                items.append(url)
            }
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            activity.setValue("Watch on Hayase - \(item.titleRomaji ?? "")", forKey: "subject")
            activity.popoverPresentationController?.sourceView = self.view
            self.present(activity, animated: true)
        }
        headerView.onPlayTrailer = { [weak self] in
            guard let self = self,
                  let trailerID = self.animeItem?.trailerYouTubeID else { return }
            self.presentTrailerDialog(trailerID: trailerID)
        }
        headerView.onWatch = { [weak self] in
            // play.svelte: `$status === 'COMPLETED' ? 1 : ($progressStore ?? 0) + 1`
            guard let self else { return }
            self.openExtensionSearch(episode: PlayButton.episode(listStatus: self.currentListStatus, progress: self.anilistProgress))
        }
        headerView.onEntryEditor = { [weak self] in
            self?.showEntryEditor()
        }
        headerView.onOpenAniList = { [weak self] in
            guard let self = self else { return }
            guard let id = self.animeItem?.id, let url = URL(string: "https://anilist.co/anime/\(id)") else { return }
            let safari = SFSafariViewController(url: url)
            self.present(safari, animated: true)
        }
        headerView.onOpenMAL = { [weak self] in
            guard let self = self else { return }
            guard let malId = self.headerView?.malId,
                  let url = URL(string: "https://myanimelist.net/anime/\(malId)") else { return }
            let safari = SFSafariViewController(url: url)
            self.present(safari, animated: true)
        }

        headerView.onOpenCover = { [weak self] urlString, image in
            self?.presentCoverDialog(urlString: urlString, image: image)
        }

        headerView.onGenreTapped = { [weak self] name, isTag in
            self?.navigateToSearchTab(name: name, isTag: isTag)
        }

        headerView.onBadgeTapped = { [weak self] filterType, value in
            self?.navigateToSearchTab(filterType: filterType, value: value)
        }
    }

    /// `<Dialog.Root>` of the cover: the picture the trigger shows, at the size of the dialog.
    private func presentCoverDialog(urlString: String?, image: UIImage?) {
        guard image != nil || urlString != nil else { return }
        present(CoverDialogViewController(urlString: urlString, image: image, color: animeItem?.coverColor,
                                          title: animeItem.map { AniListUtil.title(for: $0) } ?? ""),
                animated: false)
    }

    private func presentTrailerDialog(trailerID: String) {
        let title = animeItem?.titleUserPreferred ?? ""
        present(TrailerDialogViewController(trailerID: trailerID, title: title), animated: false)
    }

    // MARK: - AniList Entry Editor

    func showEntryEditor() {
        guard let item = animeItem else { return }
        presentEntryEditorSheet(mediaID: item.id, currentEntry: item.listEntry, totalEpisodes: item.episodes)
    }

    private func presentEntryEditorSheet(mediaID: Int, currentEntry: AnimeItem.MediaListEntry?, totalEpisodes: Int?) {
        let editorVC = EntryEditorViewController()
        editorVC.mediaID = mediaID
        editorVC.totalEpisodes = totalEpisodes
        editorVC.currentEntry = currentEntry
        editorVC.animeTitle = animeItem.map { AniListUtil.title(for: $0) } ?? "Unknown"
        // `cover(media)` from `sm` on and `banner(media)` below it, on the color of the cover
        editorVC.coverURL = animeItem.flatMap { AniListUtil.cover(for: $0) }
        editorVC.bannerURL = animeItem.flatMap { AniListUtil.banner(for: $0) }
        editorVC.coverColor = animeItem?.coverColor

        editorVC.onSave = { [weak self] in
            self?.refreshViewerStateAfterMutation()
        }
        editorVC.onDelete = { [weak self] in
            self?.anilistProgress = 0
            self?.currentListStatus = nil
            self?.isOnList = false
            self?.syncEpisodePageToInterfaceProgress()
            self?.tableView.reloadData()
            self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false, isOnList: false)
            self?.headerView?.updatePlayButtonTitle(listStatus: nil)
        }

        present(editorVC, animated: false)
    }

    // MARK: - AniList progress & button state

    private func applyViewerStateFromRouteMedia() {
        guard let item = animeItem else { return }
        applyViewerState(from: item)
    }

    func applyViewerState(from item: AnimeItem) {
        // auth/client.ts `isFavourite`: AniList's own, else Kitsu's, else the local list's
        if TrackerAccountManager.shared.isLoggedIn(.anilist) {
            if let favourite = AniListViewerState.shared.isFavourite(for: item.id, fallback: item.isFavourite) {
                isFavorite = favourite
            }
        } else {
            isFavorite = TrackerAggregator.isFavourite(mediaID: item.id)
        }
        // `mediaListEntry`: AniList's entry first, then kitsu, mal, simkl and the local one
        if let entry = item.listEntry {
            isOnList = true
            currentListStatus = entry.status
            anilistProgress = entry.progress
        } else {
            isOnList = false
            currentListStatus = nil
            anilistProgress = 0
        }
        syncEpisodePageToInterfaceProgress()
        headerView?.updateButtonStates(isFavorite: isFavorite, isOnList: isOnList)
        headerView?.updatePlayButtonTitle(listStatus: currentListStatus)
    }

    /// Nothing is drawn again when the entry is the one the page already shows.
    @objc private func watchProgressChanged() {
        guard isViewLoaded, view.window != nil else { return }
        let rows = (tableView.indexPathsForVisibleRows ?? []).filter { Section(rawValue: $0.section) == .episodes }
        guard !rows.isEmpty else { return }
        UIView.performWithoutAnimation { tableView.reloadRows(at: rows, with: .none) }
    }

    @objc private func viewerListsChanged() {
        guard isViewLoaded, let item = animeItem, item.id > 0 else { return }
        let entry = item.listEntry
        guard (entry != nil) != isOnList
            || entry?.status != currentListStatus
            || (entry?.progress ?? 0) != anilistProgress else { return }
        refreshViewerStateAfterMutation()
    }

    /// What the entry editor saved is already in the viewer's lists, which is what the page reads.
    private func refreshViewerStateAfterMutation() {
        guard let item = animeItem, item.id > 0 else { return }
        let entry = item.listEntry
        updateAnimeItemListEntry(entry)
        isOnList = entry != nil
        syncEpisodePageToInterfaceProgress()
        tableView.reloadData()
        headerView?.updateButtonStates(isFavorite: isFavorite, isOnList: isOnList)
        headerView?.updatePlayButtonTitle(listStatus: entry?.status)
    }

    private func updateAnimeItemListEntry(_ entry: AnimeItem.MediaListEntry?, fallbackProgress: Int? = nil) {
        guard var item = animeItem else { return }
        if let entry {
            item.mediaListEntry = entry
            currentListStatus = entry.status
            anilistProgress = entry.progress
        } else if let fallbackProgress {
            let existing = item.mediaListEntry
            item.mediaListEntry = AnimeItem.MediaListEntry(
                listID: existing?.listID ?? 0,
                status: existing?.status,
                progress: fallbackProgress,
                score: existing?.score ?? 0,
                repeatCount: existing?.repeatCount ?? 0,
                customLists: existing?.customLists ?? [])
            currentListStatus = existing?.status
            anilistProgress = fallbackProgress
        } else {
            item.mediaListEntry = nil
            currentListStatus = nil
            anilistProgress = 0
        }
        animeItem = item
        headerView?.updateAnimePageDetails(with: item)
    }

    // MARK: - Tab bar

    func inheritPageTabState(from source: AnimeDetailViewController) {
        // The nested thread route renders a different +page.svelte, so it does not retain this tab state.
        guard source.embeddedThreadID == nil else { return }
        activeSection = source.activeSection
        relationGraphExpanded = source.relationGraphExpanded
        tabBar.selectedIndex = source.tabBar.selectedIndex
    }

    func tabChanged(to index: Int) {
        let sectionMap: [Int: Section] = [
            0: .episodes,
            1: .relations,
            2: .threads,
            3: .themes,
            4: .recommendations
        ]
        guard let sec = sectionMap[index] else { return }
        if sec == .recommendations, activeSection != .recommendations {
            // +page.svelte conditionally destroys/recreates Recommendation on every tab re-entry.
            recommendationComponentMountGeneration &+= 1
        }
        if sec == .threads, activeSection != .threads {
            // `{#if value === 'threads'}` makes Threads again, which starts on its first page
            threadsPage = 1
            applyThreadsPage()
        }
        activeSection = sec
        reloadSectionsWithoutAnimation(Section.allCases.filter { $0.rawValue >= Section.episodes.rawValue })
        if sec == .themes  && themes.isEmpty  && !themesLoading  { fetchThemes()  }
    }

    func setEpisodePage(_ page: Int) {
        let clamped = min(max(1, page), totalEpisodePages)
        guard clamped != currentEpisodePage else { return }
        currentEpisodePage = clamped
        reloadSectionsWithoutAnimation([.episodes, .episodePagination])
    }

    /// The interface swaps this page's sections without transitions, but
    /// UITableView animates reloaded rows even with `.none`. Every section reload
    /// on the anime page goes through here.
    func reloadSectionsWithoutAnimation(_ sections: [Section]) {
        // A table that is updated has to be told about every section whose rows changed, or it stops the app
        // ("invalid number of rows in section"). The page of episodes follows the list entry (`applyViewerState`), so
        // the entry that comes with the page of the media can change the rows of the episodes while only the
        // sections of that payload are reloaded.
        var reloaded = Set(sections)
        for section in Section.allCases where !reloaded.contains(section) {
            if tableView.numberOfRows(inSection: section.rawValue) != self.tableView(tableView, numberOfRowsInSection: section.rawValue) {
                reloaded.insert(section)
            }
        }
        UIView.performWithoutAnimation {
            tableView.reloadSections(IndexSet(reloaded.map(\.rawValue)), with: .none)
        }
    }

    func scheduleEpisodeHeightInvalidation() {
        guard !pendingEpisodeHeightInvalidation else { return }
        pendingEpisodeHeightInvalidation = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingEpisodeHeightInvalidation = false
            guard self.activeSection == .episodes else { return }
            UIView.performWithoutAnimation {
                self.tableView.beginUpdates()
                self.tableView.endUpdates()
            }
        }
    }

    // MARK: - Navigation

    func openExtensionSearch(episode: Int) {
        let searchVC = ExtensionSearchViewController()
        searchVC.animeItem = animeItem
        searchVC.initialEpisode = episode

        guard var presenter = view.window?.rootViewController else {
            searchVC.prepareOverlayPresentation(from: self)
            self.present(searchVC, animated: true)
            return
        }
        while let presented = presenter.presentedViewController {
            // Also reject a second activation while a search is already opening.
            if presented is ExtensionSearchViewController { return }
            presenter = presented
        }
        searchVC.prepareOverlayPresentation(from: presenter)
        presenter.present(searchVC, animated: true)
    }
}
