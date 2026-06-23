//
//  PreviewCard.swift
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
        v.backgroundColor = UIColor.HayaseTheme.background
        v.clipsToBounds = true
        v.layer.cornerRadius = 4
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        return v
    }()

    private let blurredImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.alpha = 0.85
        return iv
    }()

    private let bannerImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        return iv
    }()

    private let bannerGradient = PreviewBannerGradientView()
    private let youtubeIframe = YoutubeIframe()
    private let videoframe = Videoframe()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 18, weight: .bold)
        l.textColor = UIColor.HayaseTheme.foreground
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private let playButton = UIButton(type: .system)
    private let favoriteButton = UIButton(type: .system)
    private let bookmarkButton = UIButton(type: .system)

    private let detailsLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 11)
        l.textColor = UIColor.HayaseTheme.foreground
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private let descriptionLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 11)
        l.textColor = UIColor.HayaseTheme.mutedForeground
        l.numberOfLines = 4
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private var media: AnimeItem?
    private var actions: PreviewCardActions?
    private var imageTask: URLSessionDataTask?
    private var currentImageURL: String?
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

    private func setup() {
        backgroundColor = UIColor.HayaseTheme.muted
        layer.cornerRadius = 4
        clipsToBounds = true
        isUserInteractionEnabled = true

        bannerContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bannerContainer)

        [blurredImageView, bannerImageView, videoframe, youtubeIframe, bannerGradient].forEach {
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
        contentStack.setCustomSpacing(8, after: titleLabel)
        contentStack.setCustomSpacing(12, after: buttonRow)
        contentStack.setCustomSpacing(8, after: detailsLabel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        configureButtons()
        configureCardTap()

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size.width),
            heightAnchor.constraint(equalToConstant: Self.size.height),

            bannerContainer.topAnchor.constraint(equalTo: topAnchor),
            bannerContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerContainer.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.45),

            contentStack.topAnchor.constraint(equalTo: bannerContainer.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),

            playButton.heightAnchor.constraint(equalToConstant: 32),
            favoriteButton.widthAnchor.constraint(equalToConstant: 32),
            favoriteButton.heightAnchor.constraint(equalToConstant: 32),
            bookmarkButton.widthAnchor.constraint(equalToConstant: 32),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        [blurredImageView, bannerImageView, videoframe, youtubeIframe, bannerGradient].forEach {
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

    private func configureButtons() {
        playButton.backgroundColor = UIColor.HayaseTheme.primary
        playButton.tintColor = UIColor.HayaseTheme.primaryForeground
        playButton.setTitleColor(UIColor.HayaseTheme.primaryForeground, for: .normal)
        playButton.titleLabel?.font = .nunito(ofSize: 12, weight: .bold)
        playButton.layer.cornerRadius = 4
        playButton.setImage(UIImage.hayaseFilledIcon("play", pointSize: 12), for: .normal)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        [favoriteButton, bookmarkButton].forEach {
            $0.backgroundColor = .clear
            $0.tintColor = UIColor.HayaseTheme.foreground
            $0.layer.cornerRadius = 4
        }
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        bookmarkButton.addTarget(self, action: #selector(bookmarkTapped), for: .touchUpInside)
    }

    private func configureCardTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view, current !== self {
            if current is UIControl { return false }
            view = current.superview
        }
        return true
    }

    func configure(media: AnimeItem, actions: PreviewCardActions) {
        self.media = media
        self.actions = actions
        titleLabel.text = media.titleEnglish ?? media.titleRomaji ?? "Unknown"
        descriptionLabel.text = (media.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? media.description
            : "No description available."
        detailsLabel.text = detailsText(for: media)
        updatePlayTitle(for: media)
        isFavorite = false
        isBookmarked = media.mediaListEntry != nil
        refreshActionIcons()
        loadBanner(for: media)

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            youtubeIframe.reset()
            youtubeIframe.isHidden = true
        } else {
            youtubeIframe.isHidden = media.trailerYouTubeID == nil
            youtubeIframe.configure(id: media.trailerYouTubeID)
        }
        videoframe.reset()
        videoframe.isHidden = true

        AniListTracking.shared.checkIsFavourite(mediaID: media.id) { [weak self] favorite in
            DispatchQueue.main.async {
                guard self?.media?.id == media.id else { return }
                self?.isFavorite = favorite
                self?.refreshActionIcons()
            }
        }
        AniListTracking.shared.fetchMediaWithEntry(anilistID: media.id) { [weak self] entry, _, _, _, _ in
            DispatchQueue.main.async {
                guard self?.media?.id == media.id else { return }
                self?.isBookmarked = entry != nil
                self?.refreshActionIcons()
                if var updated = self?.media {
                    updated.mediaListEntry = entry
                    self?.media = updated
                    self?.updatePlayTitle(for: updated)
                }
            }
        }
    }

    func animateIn() {
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    private func detailsText(for media: AnimeItem) -> String {
        var details: [String] = []
        details.append(formatString(media.format))
        if let episodes = media.episodes, episodes > 0 {
            details.append(episodes == 1 ? "1 Episode" : "\(episodes) Episodes")
        } else if let duration = media.duration, duration > 0 {
            details.append("\(duration)m")
        } else {
            details.append("N/A")
        }
        if let season = media.season, let year = media.year ?? media.startYear {
            details.append("\(season.capitalized) \(year)")
        } else if let year = media.year ?? media.startYear {
            details.append("\(year)")
        }
        if let score = media.score, score > 0 {
            details.append("\(Int(score))%")
        }
        return details.joined(separator: "  ")
    }

    private func updatePlayTitle(for media: AnimeItem) {
        let status = media.mediaListEntry?.status
        let title: String
        if status == "COMPLETED" {
            title = "  Rewatch"
        } else if status == "CURRENT" || status == "REPEATING" || status == "PAUSED" {
            title = "  Continue"
        } else {
            title = "  Watch Now"
        }
        playButton.setTitle(title, for: .normal)
    }

    private func refreshActionIcons() {
        favoriteButton.setImage(isFavorite
            ? UIImage.hayaseFilledIcon("heart", pointSize: 16)
            : UIImage.hayaseIcon("heart")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)),
            for: .normal)
        bookmarkButton.setImage(isBookmarked
            ? UIImage.hayaseFilledIcon("bookmark", pointSize: 16)
            : UIImage.hayaseIcon("bookmark")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)),
            for: .normal)
    }

    private func loadBanner(for media: AnimeItem) {
        imageTask?.cancel()
        let urlString = media.bannerURL ?? media.coverURL
        currentImageURL = urlString
        bannerImageView.image = nil
        blurredImageView.image = nil
        bannerImageView.backgroundColor = UIColor(hexString: media.coverColor) ?? UIColor.HayaseTheme.background
        guard let urlString, let url = URL(string: urlString) else { return }
        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            applyImage(cached, for: urlString)
            return
        }
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
            DispatchQueue.main.async { self?.applyImage(image, for: urlString) }
        }
        imageTask?.resume()
    }

    private func applyImage(_ image: UIImage, for urlString: String) {
        guard currentImageURL == urlString else { return }
        bannerImageView.image = image
        blurredImageView.image = image
    }

    private func formatString(_ raw: String?) -> String {
        guard let raw else { return "TV Series" }
        switch raw {
        case "TV": return "TV Series"
        case "TV_SHORT": return "TV Short"
        case "OVA": return "OVA"
        case "ONA": return "ONA"
        case "MOVIE": return "Movie"
        case "SPECIAL": return "Special"
        case "MUSIC": return "Music"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
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
        imageTask?.cancel()
        youtubeIframe.reset()
        videoframe.reset()
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

private extension UIColor {
    convenience init?(hexString: String?) {
        guard let hex = hexString?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        var cleanHex = hex
        if cleanHex.hasPrefix("#") { cleanHex = String(cleanHex.dropFirst()) }
        guard cleanHex.count == 6, let rgb = UInt64(cleanHex, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
