//
//  Layout.swift
//  Hayase
//

import UIKit
import SafariServices
import ObjectiveC

// MARK: - Color constants

// interface Default / Blackout theme tokens.
let hayasePageBackground = UIColor.HayaseTheme.background
let hayaseCardBackground = UIColor.HayaseTheme.card

private let hayaseAnimeBannerBackdropDidChange = Notification.Name("HayaseHomeBannerBackdropDidChange")
private let hayaseAnimeBannerBackdropURLKey = "url"
private let hayaseAnimeBannerBackdropAlphaKey = "alpha"

// MARK: - PaddedLabel

final class PaddedLabel: UILabel {
    var contentInsets = UIEdgeInsets.zero {
        didSet { invalidateIntrinsicContentSize() }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + contentInsets.left + contentInsets.right,
                      height: size.height + contentInsets.top + contentInsets.bottom)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let base = super.sizeThatFits(CGSize(
            width: max(0, size.width - contentInsets.left - contentInsets.right),
            height: max(0, size.height - contentInsets.top - contentInsets.bottom)))
        return CGSize(width: base.width + contentInsets.left + contentInsets.right,
                      height: base.height + contentInsets.top + contentInsets.bottom)
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let insetBounds = bounds.inset(by: contentInsets)
        return super.textRect(forBounds: insetBounds, limitedToNumberOfLines: numberOfLines)
    }
}

// MARK: - ChipWrapView

final class ChipWrapView: UIView {
    let interItemSpacing: CGFloat = 8
    let lineSpacing: CGFloat = 8
    let chipHeight: CGFloat = 28

    private var chipWidths: [CGFloat] = []

    func setChips(_ newChips: [UIView]) {
        subviews.forEach { $0.removeFromSuperview() }
        chipWidths = newChips.map { widthForChip($0) }
        newChips.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true
            addSubview($0)
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func widthForChip(_ chip: UIView) -> CGFloat {
        if let btn = chip as? UIButton {
            let text = btn.title(for: .normal) ?? btn.titleLabel?.text ?? ""
            let font = btn.titleLabel?.font ?? .systemFont(ofSize: 13)
            let textW = ceil((text as NSString).size(withAttributes: [.font: font]).width)
            let hPad = btn.contentEdgeInsets.left + btn.contentEdgeInsets.right
            return textW + (hPad > 0 ? hPad : 32)  // px-4 = 16pt each side
        }
        return chip.intrinsicContentSize.width
    }

    private func computeHeight(for width: CGFloat) -> CGFloat {
        guard !chipWidths.isEmpty, width > 0 else { return chipWidths.isEmpty ? 0 : chipHeight }
        var x: CGFloat = 0, y: CGFloat = 0
        for w in chipWidths {
            if x > 0 && x + w > width { x = 0; y += chipHeight + lineSpacing }
            x += w + interItemSpacing
        }
        return y + chipHeight
    }

    override var intrinsicContentSize: CGSize {
        let h = bounds.width > 0
            ? computeHeight(for: bounds.width)
            : (chipWidths.isEmpty ? 0 : chipHeight)
        return CGSize(width: UIView.noIntrinsicMetric, height: max(h, chipWidths.isEmpty ? 0 : chipHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let chips = subviews
        guard !chips.isEmpty, bounds.width > 0 else { return }
        var x: CGFloat = 0, y: CGFloat = 0
        for (i, chip) in chips.enumerated() {
            let w = i < chipWidths.count ? chipWidths[i] : widthForChip(chip)
            if x > 0 && x + w > bounds.width { x = 0; y += chipHeight + lineSpacing }
            chip.frame = CGRect(x: x, y: y, width: w, height: chipHeight)
            x += w + interItemSpacing
        }
        let newH = y + chipHeight
        if abs(newH - intrinsicContentSize.height) > 0.5 {
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
        }
    }
}

// MARK: - AnimeInfoHeaderView

final class AnimeInfoHeaderView: UIView {

    // MARK: - Callbacks

    var onFavorite: (() -> Void)?
    var onBookmark: (() -> Void)?
    var onShare: (() -> Void)?
    var onPlayTrailer: (() -> Void)?
    var onWatch: (() -> Void)?
    var onEntryEditor: (() -> Void)?
    var onGenreTapped: ((String) -> Void)?
    var onBadgeTapped: ((_ filterType: String, _ value: String) -> Void)?
    var onOpenAniList: (() -> Void)?
    var onOpenMAL: (() -> Void)?

    var anilistId: Int?
    var malId: Int?
    var displayedBannerURL: String?
    var storedAccentColor: UIColor = .white

    static let bannerHeight: CGFloat = 400

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

    private var contentTopConstraint: NSLayoutConstraint?
    private var contentMaxWidthConstraint: NSLayoutConstraint?

    // MARK: - Banner

    private let bannerImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.08, alpha: 1)
        return iv
    }()

    private let bannerGradientView: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        let gradient = CAGradientLayer()
        gradient.type = .axial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        let bgColor = hayasePageBackground
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.40).cgColor,
            UIColor.black.withAlphaComponent(0.16).cgColor,
            UIColor.black.withAlphaComponent(0.16).cgColor,
            UIColor.black.withAlphaComponent(0.50).cgColor,
            bgColor.cgColor,
        ]
        gradient.locations = [0.0, 0.25, 0.40, 0.65, 1.0]
        v.layer.addSublayer(gradient)
        return v
    }()

    // MARK: - Cover

    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 4   // rounded = 0.25rem = 4pt (default Tailwind)
        iv.backgroundColor = UIColor(white: 0.16, alpha: 1)
        return iv
    }()

    // MARK: - Text labels

    private let romajiLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 16, weight: .light)
        l.textColor = UIColor(white: 0.649, alpha: 1.0)
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
        l.setContentCompressionResistancePriority(.init(760), for: .vertical)
        return l
    }()

    // MARK: - Badges

    private let badgesStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        return sv
    }()
    private let badgesScrollView: UIScrollView = {
        let sv = UIScrollView()
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
        return l
    }()

    // MARK: - Action buttons

    private let playButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage.hayaseFilledIcon("play", pointSize: 13), for: .normal)
        b.setTitle("Watch Now", for: .normal)
        b.tintColor = .black
        b.setTitleColor(.black, for: .normal)
        b.backgroundColor = .white
        b.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        b.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        b.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        b.layer.cornerRadius = 6
        b.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        b.layer.masksToBounds = true
        return b
    }()

    private let entryEditorButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage.hayaseIcon("pen-line")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .black
        b.backgroundColor = UIColor(white: 0.75, alpha: 1)
        b.layer.cornerRadius = 6
        b.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        b.layer.masksToBounds = true
        return b
    }()

    private let favoriteButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage.hayaseIcon("heart")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        return b
    }()

    private let bookmarkButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage.hayaseIcon("bookmark")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        return b
    }()

    private let shareButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage.hayaseIcon("share-2")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        return b
    }()

    private let trailerButton: UIButton = {
        let b = UIButton(type: .custom)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let lucideId: String
        if #available(iOS 16.0, *) {
            lucideId = "clapperboard"
        } else {
            lucideId = "film"
        }
        let img = UIImage.hayaseIcon(lucideId, withConfiguration: iconCfg)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        b.setImage(img, for: .normal)
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        b.isHidden = true
        return b
    }()

    private let anilistButton: UIButton = {
        let b = UIButton(type: .custom)
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
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

    private let malButton: UIButton = {
        let b = UIButton(type: .custom)
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
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

    private let genresStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        return sv
    }()
    private let genresScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    private let genresContainer = UIView()
    private let chipWrapView = ChipWrapView()
    private var genresContainerHeightConstraint: NSLayoutConstraint?
    private var chipWrapBottomConstraint: NSLayoutConstraint?

    private var bannerImageTask: URLSessionDataTask?
    private var coverImageTask: URLSessionDataTask?
    private var bannerHidden = false

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
        backgroundColor = hayasePageBackground

        genresScrollView.translatesAutoresizingMaskIntoConstraints = false
        genresStack.translatesAutoresizingMaskIntoConstraints = false
        genresScrollView.addSubview(genresStack)
        NSLayoutConstraint.activate([
            genresStack.topAnchor.constraint(equalTo: genresScrollView.topAnchor),
            genresStack.bottomAnchor.constraint(equalTo: genresScrollView.bottomAnchor),
            genresStack.leadingAnchor.constraint(equalTo: genresScrollView.leadingAnchor),
            genresStack.trailingAnchor.constraint(equalTo: genresScrollView.trailingAnchor),
            genresStack.heightAnchor.constraint(equalTo: genresScrollView.heightAnchor),
        ])

        badgesScrollView.translatesAutoresizingMaskIntoConstraints = false
        badgesStack.translatesAutoresizingMaskIntoConstraints = false
        badgesScrollView.addSubview(badgesStack)
        NSLayoutConstraint.activate([
            badgesStack.topAnchor.constraint(equalTo: badgesScrollView.topAnchor),
            badgesStack.bottomAnchor.constraint(equalTo: badgesScrollView.bottomAnchor),
            badgesStack.leadingAnchor.constraint(equalTo: badgesScrollView.leadingAnchor),
            badgesStack.trailingAnchor.constraint(equalTo: badgesScrollView.trailingAnchor),
            badgesStack.heightAnchor.constraint(equalTo: badgesScrollView.heightAnchor),
        ])

        textColumn = UIStackView(arrangedSubviews: [romajiLabel, titleLabel, badgesScrollView, descriptionLabel])
        textColumn.axis = .vertical
        textColumn.spacing = 6   // gap-1.5
        textColumn.alignment = .fill

        coverAndTextColumn = UIStackView(arrangedSubviews: [coverImageView, textColumn])
        coverAndTextColumn.axis = .vertical
        coverAndTextColumn.spacing = 16
        coverAndTextColumn.alignment = .center

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

        genresContainer.addSubview(genresScrollView)
        chipWrapView.translatesAutoresizingMaskIntoConstraints = false
        genresContainer.addSubview(chipWrapView)
        NSLayoutConstraint.activate([
            genresScrollView.topAnchor.constraint(equalTo: genresContainer.topAnchor),
            genresScrollView.bottomAnchor.constraint(equalTo: genresContainer.bottomAnchor),
            genresScrollView.centerXAnchor.constraint(equalTo: genresContainer.centerXAnchor),
            genresScrollView.widthAnchor.constraint(equalTo: genresContainer.widthAnchor),
            chipWrapView.topAnchor.constraint(equalTo: genresContainer.topAnchor),
            chipWrapView.leadingAnchor.constraint(equalTo: genresContainer.leadingAnchor),
            chipWrapView.trailingAnchor.constraint(equalTo: genresContainer.trailingAnchor),
        ])
        genresContainerHeightConstraint = genresContainer.heightAnchor.constraint(equalToConstant: 28)
        chipWrapBottomConstraint = chipWrapView.bottomAnchor.constraint(equalTo: genresContainer.bottomAnchor)

        contentStack = UIStackView(arrangedSubviews: [coverAndTextColumn, actionsRow, genresContainer])
        contentStack.axis = .vertical
        contentStack.spacing = 24
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 16, left: 12, bottom: 0, right: 12)

        [bannerImageView, bannerGradientView, contentStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            bannerImageView.topAnchor.constraint(equalTo: topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: AnimeInfoHeaderView.bannerHeight),

            bannerGradientView.topAnchor.constraint(equalTo: bannerImageView.topAnchor),
            bannerGradientView.leadingAnchor.constraint(equalTo: bannerImageView.leadingAnchor),
            bannerGradientView.trailingAnchor.constraint(equalTo: bannerImageView.trailingAnchor),
            bannerGradientView.bottomAnchor.constraint(equalTo: bannerImageView.bottomAnchor),

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

            playCombo.widthAnchor.constraint(lessThanOrEqualToConstant: 180),

            badgesScrollView.heightAnchor.constraint(equalToConstant: 24),
        ])

        contentTopConstraint = contentStack.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: -200)
        contentTopConstraint?.isActive = true
        contentMaxWidthConstraint = contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: 1600)
        contentMaxWidthConstraint?.isActive = true
        let fullWidth = contentStack.widthAnchor.constraint(equalTo: widthAnchor)
        fullWidth.priority = .defaultHigh
        fullWidth.isActive = true
        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        textColumnWidthConstraint = textColumn.widthAnchor.constraint(equalTo: coverAndTextColumn.widthAnchor)
        textColumnWidthConstraint?.isActive = true

        applyLayoutForSizeClass()
    }

    private var textColumnWidthConstraint: NSLayoutConstraint?

    // MARK: - Adaptive layout

    private func applyLayoutForSizeClass() {
        let isRegular = traitCollection.horizontalSizeClass == .regular

        contentTopConstraint?.constant = isRegular ? -260 : -200

        genresScrollView.isHidden = isRegular
        chipWrapView.isHidden = !isRegular
        genresContainerHeightConstraint?.isActive = !isRegular
        chipWrapBottomConstraint?.isActive = isRegular

        if isRegular {
            coverAndTextColumn.axis = .horizontal
            coverAndTextColumn.spacing = 20
            coverAndTextColumn.alignment = .bottom
        } else {
            coverAndTextColumn.axis = .vertical
            coverAndTextColumn.spacing = 16
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
        descriptionLabel.font = isRegular ? .nunito(ofSize: 16, weight: .light) : .nunito(ofSize: 14, weight: .light)

        badgesScrollView.isHidden = !isRegular
        descriptionLabel.isHidden = !isRegular

        textColumnWidthConstraint?.isActive = !isRegular

        let hPad: CGFloat = isRegular ? 56 : 12
        contentStack.layoutMargins = UIEdgeInsets(top: isRegular ? 48 : 16, left: hPad, bottom: 0, right: hPad)

        actionsTrailingSpacer.removeFromSuperview()
        for sv in actionsRow.arrangedSubviews { actionsRow.removeArrangedSubview(sv) }

        if isRegular {
            actionsRow.addArrangedSubview(playCombo)
            actionsRow.addArrangedSubview(favoriteButton)
            actionsRow.addArrangedSubview(bookmarkButton)
            actionsRow.addArrangedSubview(shareButton)
            actionsRow.addArrangedSubview(trailerButton)
            actionsRow.addArrangedSubview(anilistButton)
            actionsRow.addArrangedSubview(malButton)
            actionsRow.addArrangedSubview(actionsTrailingSpacer)
            actionsRow.setCustomSpacing(20, after: playCombo)
            anilistButton.isHidden = false
            malButton.isHidden = (malId == nil)
        } else {
            actionsRow.addArrangedSubview(bookmarkButton)
            actionsRow.addArrangedSubview(favoriteButton)
            actionsRow.addArrangedSubview(playCombo)
            actionsRow.addArrangedSubview(shareButton)
            actionsRow.addArrangedSubview(trailerButton)
            actionsRow.addArrangedSubview(anilistButton)
            actionsRow.addArrangedSubview(malButton)
            anilistButton.isHidden = true
            malButton.isHidden = true
        }

        if let gradientLayer = bannerGradientView.layer.sublayers?.first as? CAGradientLayer {
            let bgColor = hayasePageBackground
            if isRegular {
                gradientLayer.type = .radial
                gradientLayer.startPoint = CGPoint(x: 0.59, y: 0.35)
                gradientLayer.endPoint = CGPoint(x: 1.35, y: 1.0)
                gradientLayer.colors = [
                    UIColor.black.withAlphaComponent(0.16).cgColor,
                    UIColor.black.withAlphaComponent(0.16).cgColor,
                    bgColor.cgColor,
                ]
                gradientLayer.locations = [0.0, 0.31, 1.0]
            } else {
                gradientLayer.type = .axial
                gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
                gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
                gradientLayer.colors = [
                    UIColor.black.withAlphaComponent(0.40).cgColor,
                    UIColor.black.withAlphaComponent(0.16).cgColor,
                    UIColor.black.withAlphaComponent(0.16).cgColor,
                    UIColor.black.withAlphaComponent(0.50).cgColor,
                    bgColor.cgColor,
                ]
                gradientLayer.locations = [0.0, 0.25, 0.40, 0.65, 1.0]
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let currentSC = traitCollection.horizontalSizeClass
        if previousTraitCollection?.horizontalSizeClass != currentSC {
            lastAppliedSizeClass = currentSC
            applyLayoutForSizeClass()
            setNeedsLayout()
            layoutIfNeeded()
            invalidateIntrinsicContentSize()
        }
    }

    private var lastAppliedSizeClass: UIUserInterfaceSizeClass?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            let currentSC = traitCollection.horizontalSizeClass
            if lastAppliedSizeClass != currentSC {
                lastAppliedSizeClass = currentSC
                applyLayoutForSizeClass()
                setNeedsLayout()
                layoutIfNeeded()
                invalidateIntrinsicContentSize()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let gradientLayer = bannerGradientView.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = bannerGradientView.bounds
        }

        let isRegular = traitCollection.horizontalSizeClass == .regular
        let hPad: CGFloat = isRegular ? 56 : 12
        let effectiveWidth = isRegular ? min(bounds.width, 1600) : bounds.width
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
        let isRegular = traitCollection.horizontalSizeClass == .regular
        let hPad: CGFloat = isRegular ? 56 : 12
        let effectiveWidth = isRegular ? min(width, 1600) : width
        let maxW: CGFloat
        if isRegular {
            maxW = effectiveWidth - 2 * hPad - 180 - 20
        } else {
            maxW = effectiveWidth - 2 * hPad
        }
        guard maxW > 0 else { return }
        titleLabel.preferredMaxLayoutWidth = maxW
        romajiLabel.preferredMaxLayoutWidth = maxW
        descriptionLabel.preferredMaxLayoutWidth = maxW
        titleLabel.invalidateIntrinsicContentSize()
        romajiLabel.invalidateIntrinsicContentSize()
        descriptionLabel.invalidateIntrinsicContentSize()
    }

    // MARK: - Sidebar banner bridge

    func publishSidebarBackdrop() {
        postSidebarBackdrop(urlString: displayedBannerURL)
    }

    private func postSidebarBackdrop(urlString: String?) {
        guard let urlString else { return }
        NotificationCenter.default.post(name: hayaseAnimeBannerBackdropDidChange,
                                        object: nil,
                                        userInfo: [
                                            hayaseAnimeBannerBackdropURLKey: urlString,
                                            hayaseAnimeBannerBackdropAlphaKey: bannerHidden ? CGFloat(0.05) : CGFloat(1),
                                        ])
    }

    func applyScrollFade(_ scrollOffset: CGFloat) {
        let shouldHide = scrollOffset > 100
        guard shouldHide != bannerHidden else { return }
        bannerHidden = shouldHide
        let targetAlpha: CGFloat = shouldHide ? 0.05 : 1.0
        NotificationCenter.default.post(name: hayaseAnimeBannerBackdropDidChange,
                                        object: nil,
                                        userInfo: [hayaseAnimeBannerBackdropAlphaKey: targetAlpha])
        UIView.animate(withDuration: 0.5) {
            self.bannerImageView.alpha = targetAlpha
        }
    }

    // MARK: - Actions

    private func animateTap(_ button: UIButton) {
        UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseIn], animations: {
            button.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0,
                           usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8,
                           options: [], animations: {
                button.transform = .identity
            })
        }
    }

    @objc private func shareTapped() {
        animateTap(shareButton)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        shareButton.setImage(UIImage.hayaseIcon("check")?.withConfiguration(cfg), for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.shareButton.setImage(UIImage.hayaseIcon("share-2")?.withConfiguration(cfg), for: .normal)
        }
        onShare?()
    }
    @objc private func trailerTapped()     { animateTap(trailerButton);     onPlayTrailer?() }
    @objc private func playTapped()        { onWatch?() }
    @objc private func entryEditorTapped() { animateTap(entryEditorButton); onEntryEditor?() }
    @objc private func favoriteTapped()    { animateTap(favoriteButton);    onFavorite?() }
    @objc private func bookmarkTapped()    { animateTap(bookmarkButton);    onBookmark?() }
    @objc private func anilistTapped()     { animateTap(anilistButton);     onOpenAniList?() }
    @objc private func malTapped()         { animateTap(malButton);         onOpenMAL?() }

    func updateButtonStates(isFavorite: Bool, isOnList: Bool) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        favoriteButton.setImage(isFavorite ? UIImage.hayaseFilledIcon("heart", pointSize: 16) : UIImage.hayaseIcon("heart")?.withConfiguration(cfg), for: .normal)
        favoriteButton.tintColor = isFavorite ? storedAccentColor : .white

        bookmarkButton.setImage(isOnList ? UIImage.hayaseFilledIcon("bookmark", pointSize: 16) : UIImage.hayaseIcon("bookmark")?.withConfiguration(cfg), for: .normal)
        bookmarkButton.tintColor = isOnList ? storedAccentColor : .white
    }

    func updatePlayButtonTitle(listStatus: String?) {
        let text: String
        switch listStatus {
        case "CURRENT", "REPEATING", "PAUSED": text = "Continue"
        case "COMPLETED":                       text = "Rewatch"
        default:                                text = "Watch Now"
        }
        playButton.setTitle(text, for: .normal)
    }

    func applyOverscrollZoom(_ overscroll: CGFloat) {
        guard overscroll > 0 else {
            if bannerImageView.transform != .identity {
                bannerImageView.transform = .identity
                bannerGradientView.transform = .identity
            }
            return
        }
        let scale = 1.0 + overscroll / AnimeInfoHeaderView.bannerHeight
        let yShift = -overscroll / 2.0
        bannerImageView.transform = CGAffineTransform(translationX: 0, y: yShift).scaledBy(x: scale, y: scale)
        bannerGradientView.transform = CGAffineTransform(translationX: 0, y: yShift).scaledBy(x: scale, y: scale)
    }

    // MARK: - Configure (Animes CoreData entity)

    func configure(with anime: Animes?) {
        guard let anime = anime else { return }
        anilistId = anime.animeAnilistId?.intValue

        let english = anime.animeTitleEnglish
        let romaji  = anime.animeTitleJapanese
        titleLabel.text   = english ?? romaji ?? "Unknown"
        romajiLabel.text  = (english != nil && romaji != nil && english != romaji) ? romaji : nil
        romajiLabel.isHidden = romajiLabel.text == nil

        rebuildBadges(score:   anime.animeScore?.floatValue,
                      status:  anime.animeStatus,
                      episodes: anime.animeTotalEps?.intValue,
                      nextEp:  anime.animeNextEps?.intValue,
                      format:  nil, season: nil)

        genresContainer.isHidden = true

        let desc = anime.animeDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionLabel.text = (desc?.isEmpty ?? true) ? "No description available." : desc

        trailerButton.isHidden = true

        displayedBannerURL = anime.animeImgS ?? anime.animeImgL ?? anime.animeImgM
        postSidebarBackdrop(urlString: displayedBannerURL)
        loadImage(from: displayedBannerURL,
                  into: bannerImageView, task: &bannerImageTask)
        loadImage(from: anime.animeImgL ?? anime.animeImgM,
                  into: coverImageView, task: &coverImageTask)
    }

    // MARK: - Configure (AnimeItem from AniList)

    func configure(with item: AnimeItem) {
        anilistId = item.id
        malId = item.malId

        let english = item.titleEnglish
        let romaji  = item.titleRomaji
        titleLabel.text  = english ?? romaji ?? "Unknown"
        romajiLabel.text = (english != nil && romaji != nil && english != romaji) ? romaji : nil
        romajiLabel.isHidden = romajiLabel.text == nil

        let accent  = ExtensionSearchViewController.uiColor(fromHex: item.coverColor) ?? .white
        let contrast = ExtensionSearchViewController.luminanceContrastColor(for: accent)
        storedAccentColor = accent
        playButton.backgroundColor = accent
        playButton.tintColor = contrast
        playButton.setTitleColor(contrast, for: .normal)

        var hue: CGFloat = 0, satHSB: CGFloat = 0, briHSB: CGFloat = 0
        accent.getHue(&hue, saturation: &satHSB, brightness: &briHSB, alpha: nil)
        let l = (2.0 - satHSB) * briHSB / 2.0
        let s = l == 0 || l == 1 ? 0 : satHSB * briHSB / (l < 0.5 ? 2.0 * l : 2.0 - 2.0 * l)
        let targetL: CGFloat = 0.6
        let bNew = targetL + s * min(targetL, 1.0 - targetL)
        let sNew: CGFloat = bNew > 0 ? 2.0 * (bNew - targetL) / bNew : 0
        let lighter = UIColor(hue: hue, saturation: sNew, brightness: bNew, alpha: 1)
        entryEditorButton.backgroundColor = lighter
        entryEditorButton.tintColor = contrast

        let seasonStr: String? = {
            let szn = item.season?.capitalized
            let yr = item.year ?? item.startYear
            let parts = [szn, yr.map { String($0) }].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }()

        rebuildBadges(score:    item.score,
                      status:   item.status,
                      episodes: item.episodes,
                      nextEp:   nil,
                      format:   item.format,
                      season:   seasonStr,
                      duration: item.duration,
                      progress: item.mediaListEntry?.progress,
                      accent:   accent,
                      contrastColor: contrast)

        setGenres(item.genres.prefix(8).map { String($0) })

        let desc = item.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionLabel.text = (desc?.isEmpty ?? true) ? "No description available." : desc

        trailerButton.isHidden = item.trailerYouTubeID == nil

        let bannerFallback = item.bannerURL ?? item.coverURL
        AniListClient.fetchFanartURL(anilistID: item.id) { [weak self] fanartURL in
            guard let self else { return }
            let urlStr = fanartURL ?? bannerFallback
            self.displayedBannerURL = urlStr
            self.postSidebarBackdrop(urlString: urlStr)
            self.bannerImageTask?.cancel()
            self.bannerImageTask = nil
            guard let urlStr, let url = URL(string: urlStr) else { return }
            if let cached = SharedImageCache.shared.object(forKey: urlStr as NSString) {
                self.bannerImageView.image = cached
                return
            }
            let biv = self.bannerImageView
            self.bannerImageTask = URLSession.shared.dataTask(with: url) { [weak biv] data, _, _ in
                guard let data, let img = UIImage(data: data) else { return }
                SharedImageCache.shared.setObject(img, forKey: urlStr as NSString)
                DispatchQueue.main.async {
                    UIView.transition(with: biv ?? UIImageView(), duration: 0.3,
                                      options: .transitionCrossDissolve,
                                      animations: { biv?.image = img })
                }
            }
            self.bannerImageTask?.resume()
        }
        loadImage(from: item.coverURL, into: coverImageView, task: &coverImageTask)
    }

    func updateBanner(from urlString: String) {
        displayedBannerURL = urlString
        loadImage(from: urlString, into: bannerImageView, task: &bannerImageTask)
    }

    // MARK: - Badges

    private func rebuildBadges(score: Float?, status: String?, episodes: Int?,
                                nextEp: Int?, format: String?, season: String?,
                                duration: Int? = nil, progress: Int? = nil,
                                accent: UIColor = .white,
                                contrastColor: UIColor = UIColor(white: 0.07, alpha: 1)) {
        badgesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let badge1Text: String
        if let eps = episodes, eps > 1 {
            if let prog = progress, prog > 0, prog != eps {
                badge1Text = "\(prog) / \(eps) Episodes"
            } else {
                badge1Text = "\(eps) Episodes"
            }
        } else if let dur = duration, dur > 0 {
            badge1Text = "\(dur) Minute\(dur > 1 ? "s" : "")"
        } else {
            badge1Text = "N/A"
        }
        badgesStack.addArrangedSubview(makeBadge(text: badge1Text, accent: accent, contrast: contrastColor))

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
            badgesStack.addArrangedSubview(makeBadge(text: display, accent: accent, contrast: contrastColor,
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
            badgesStack.addArrangedSubview(makeBadge(text: display, accent: accent, contrast: contrastColor,
                                                      filterType: status != nil ? "status" : nil,
                                                      filterValue: status))
        }

        if let szn = season, !szn.isEmpty {
            badgesStack.addArrangedSubview(makeBadge(text: szn, accent: accent, contrast: contrastColor,
                                                      filterType: "season", filterValue: szn))
        }

        if let sc = score, sc > 0 {
            let scoreBG: UIColor
            let scoreInt = Int(sc)
            if scoreInt >= 75 {
                scoreBG = UIColor(red: 21/255.0, green: 128/255.0, blue: 61/255.0, alpha: 1)
            } else if scoreInt >= 65 {
                scoreBG = UIColor(red: 251/255.0, green: 146/255.0, blue: 60/255.0, alpha: 1)
            } else {
                scoreBG = UIColor(red: 248/255.0, green: 113/255.0, blue: 113/255.0, alpha: 1)
            }
            badgesStack.addArrangedSubview(makeBadge(text: String(format: "%.0f%%", sc),
                                                      accent: scoreBG,
                                                      contrast: contrastColor,
                                                      filterType: "score",
                                                      filterValue: "SCORE_DESC"))
        }
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
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            accent.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            btn.highlightedBgColor = UIColor(hue: h, saturation: min(s * 1.1, 1), brightness: max(b * 0.75, 0), alpha: a)
            btn.backgroundColor = accent
            btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            btn.layer.cornerRadius = 4
            btn.clipsToBounds = true
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
            btn.setContentHuggingPriority(.required, for: .horizontal)
            btn.setContentCompressionResistancePriority(.required, for: .horizontal)
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
            l.setContentHuggingPriority(.required, for: .horizontal)
            l.setContentCompressionResistancePriority(.required, for: .horizontal)
            l.translatesAutoresizingMaskIntoConstraints = false
            l.heightAnchor.constraint(equalToConstant: 24).isActive = true
            return l
        }
    }

    private class BadgeButton: UIButton {
        var normalBgColor: UIColor = .white
        var highlightedBgColor: UIColor = .gray
        var filterType: String = ""
        var filterValue: String = ""

        override var isHighlighted: Bool {
            didSet {
                UIView.animate(withDuration: 0.15) {
                    self.backgroundColor = self.isHighlighted ? self.highlightedBgColor : self.normalBgColor
                }
            }
        }
    }

    @objc private func detailBadgeTapped(_ sender: BadgeButton) {
        onBadgeTapped?(sender.filterType, sender.filterValue)
    }

    // MARK: - Genres

    private func setGenres(_ genres: [String]) {
        genresStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let wrapChips: [UIView] = genres.map { genre in
            let btn = UIButton(type: .custom)
            btn.setTitle(genre, for: .normal)
            btn.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
            btn.setTitleColor(.white, for: .normal)
            btn.setTitleColor(storedAccentColor, for: .highlighted)
            btn.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
            btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
            btn.layer.cornerRadius = 6
            btn.layer.masksToBounds = true
            btn.addTarget(self, action: #selector(genreChipTapped(_:)), for: .touchUpInside)
            return btn
        }
        for genre in genres {
            genresStack.addArrangedSubview(makeGenreChip(text: genre))
        }
        chipWrapView.setChips(wrapChips)
        genresContainer.isHidden = genres.isEmpty
    }

    func updateGenresAndTrailer(genres: [String], trailerYouTubeID: String?) {
        setGenres(genres)
        trailerButton.isHidden = trailerYouTubeID == nil
    }

    func updateTrailerButton(trailerYouTubeID: String?) {
        trailerButton.isHidden = trailerYouTubeID == nil
    }

    func updateMALButtonVisibility() {
        if traitCollection.horizontalSizeClass == .regular {
            malButton.isHidden = (malId == nil)
        } else {
            malButton.isHidden = true
        }
    }

    private func makeGenreChip(text: String) -> UIView {
        let btn = UIButton(type: .custom)
        btn.setTitle(text, for: .normal)
        btn.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        btn.setTitleColor(.white, for: .normal)
        btn.setTitleColor(storedAccentColor, for: .highlighted)
        btn.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        btn.layer.cornerRadius = 6
        btn.layer.masksToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.addTarget(self, action: #selector(genreChipTapped(_:)), for: .touchUpInside)
        return btn
    }

    @objc private func genreChipTapped(_ sender: UIButton) {
        guard let genre = sender.title(for: .normal) else { return }
        onGenreTapped?(genre)
    }

    // MARK: - Image loading

    private func loadImage(from urlString: String?,
                           into imageView: UIImageView,
                           task: inout URLSessionDataTask?) {
        task?.cancel()
        task = nil
        imageView.image = nil
        guard let urlString = urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return }
        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            imageView.image = cached
            return
        }
        let captured = urlString
        task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(img, forKey: captured as NSString)
            DispatchQueue.main.async {
                UIView.transition(with: imageView, duration: 0.3,
                                  options: .transitionCrossDissolve,
                                  animations: { imageView.image = img })
            }
        }
        task?.resume()
    }
}

// MARK: - AnimeDetailViewController

class AnimeDetailViewController: UIViewController {

    var animeEntity: Animes?
    var animeItem: AnimeItem?

    var tableView: UITableView!
    var headerView: AnimeInfoHeaderView!
    var isFavorite = false
    var isOnList = false
    var episodes: [AniZipEpisode] = []
    var anilistProgress: Int = 0
    var currentListStatus: String?
    var currentAnimeAccent: UIColor = .white
    var relations: [AnimeRelation] = []
    var staff: [AnimeStaffMember] = []
    var scoreDistribution: [AnimeScorePoint] = []
    var statusDistribution: [AnimeStatusCount] = []

    let episodesPerPage = 16
    var currentEpisodePage: Int = 1
    var paginatedEpisodes: [AniZipEpisode] {
        let start = (currentEpisodePage - 1) * episodesPerPage
        let end = min(start + episodesPerPage, episodes.count)
        guard start < episodes.count else { return [] }
        return Array(episodes[start..<end])
    }
    var totalEpisodePages: Int {
        max(1, Int(ceil(Double(episodes.count) / Double(episodesPerPage))))
    }
    lazy var paginationBar: PaginationBarView = {
        let bar = PaginationBarView()
        bar.onPageChange = { [weak self] page in
            self?.setEpisodePage(page)
        }
        return bar
    }()

    var threads: [AniListThread] = []
    var themes: [AnimeThemesTheme] = []
    var threadsLoading = false
    var themesLoading = false

    var activeSection: Section = .episodes

    lazy var tabBar: HTabBar = {
        let bar = HTabBar(titles: ["Episodes", "Relations", "Threads", "Themes"])
        bar.onChange = { [weak self] index in
            self?.tabChanged(to: index)
        }
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    var tabBarCenterXConstraint: NSLayoutConstraint?
    var tabBarLeadingConstraint: NSLayoutConstraint?
    var tabBarMaxWidthConstraint: NSLayoutConstraint?
    var tabBarWidthFillConstraint: NSLayoutConstraint?
    var tabBarTrailingConstraint: NSLayoutConstraint?

    lazy var tabBarContainer: UIView = {
        let v = UIView()
        v.backgroundColor = hayasePageBackground
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(tabBar)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: v.topAnchor, constant: 24),
            tabBar.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8),
        ])

        tabBarCenterXConstraint = tabBar.centerXAnchor.constraint(equalTo: v.centerXAnchor)
        tabBarMaxWidthConstraint = tabBar.widthAnchor.constraint(lessThanOrEqualToConstant: 288)
        tabBarWidthFillConstraint = tabBar.widthAnchor.constraint(equalTo: v.widthAnchor, constant: -32)
        tabBarWidthFillConstraint?.priority = .defaultHigh

        tabBarLeadingConstraint = tabBar.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 56)
        tabBarTrailingConstraint = tabBar.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -56)

        return v
    }()

    func applyTabBarLayoutForSizeClass() {
        let isRegular = traitCollection.horizontalSizeClass == .regular

        tabBar.isVertical = !isRegular

        if isRegular {
            tabBarCenterXConstraint?.isActive = false
            tabBarMaxWidthConstraint?.isActive = false
            tabBarWidthFillConstraint?.isActive = false
            tabBarLeadingConstraint?.isActive = true
            tabBarTrailingConstraint?.isActive = true
        } else {
            tabBarLeadingConstraint?.isActive = false
            tabBarTrailingConstraint?.isActive = false
            tabBarCenterXConstraint?.isActive = true
            tabBarMaxWidthConstraint?.isActive = true
            tabBarWidthFillConstraint?.isActive = true
        }
    }

    enum Section: Int, CaseIterable {
        case header = 0, episodes, episodePagination, relations, threads, themes
    }

    static let gridOuterPad: CGFloat = 56
    static let gridMinColWidth: CGFloat = 500
    static let episodeGap: CGFloat = 16
    static let threadGap: CGFloat = 40

    var episodeColumnCount: Int {
        let gridWidth = tableView.frame.width - 2 * Self.gridOuterPad
        if traitCollection.horizontalSizeClass == .regular
            && gridWidth >= 2 * Self.gridMinColWidth + Self.episodeGap {
            return 2
        }
        return 1
    }

    var threadColumnCount: Int {
        let gridWidth = tableView.frame.width - 2 * Self.gridOuterPad
        if traitCollection.horizontalSizeClass == .regular
            && gridWidth >= 2 * Self.gridMinColWidth + Self.threadGap {
            return 2
        }
        return 1
    }

    // MARK: - Search navigation helpers

    func navigateToSearchTab(genre: String) {
        let tbc = tabBarController
        guard let tbc,
              let controllers = tbc.viewControllers,
              controllers.count > 1,
              let navController = controllers[1] as? UINavigationController,
              let searchVC = navController.viewControllers.first as? SearchViewController else {
            tbc?.selectedIndex = 1
            return
        }
        let nav = navigationController
        searchVC.prefillSearchExtended(genre: genre)
        nav?.popToRootViewController(animated: false)
        tbc.selectedIndex = 1
    }

    func navigateToSearchTab(filterType: String, value: String) {
        let tbc = tabBarController
        guard let tbc,
              let controllers = tbc.viewControllers,
              controllers.count > 1,
              let navController = controllers[1] as? UINavigationController,
              let searchVC = navController.viewControllers.first as? SearchViewController else {
            tbc?.selectedIndex = 1
            return
        }
        let nav = navigationController
        switch filterType {
        case "format":
            searchVC.prefillSearchExtended(format: value)
        case "status":
            searchVC.prefillSearchExtended(status: value)
        case "season":
            let parts = value.components(separatedBy: " ")
            if parts.count == 2, let year = Int(parts[1]) {
                searchVC.prefillSearchExtended(season: parts[0].uppercased(), seasonYear: year)
            } else {
                searchVC.prefillSearchExtended(season: value.uppercased())
            }
        case "score":
            searchVC.prefillSearchExtended(sort: value)
        default:
            break
        }
        nav?.popToRootViewController(animated: false)
        tbc.selectedIndex = 1
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = nil
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = hayasePageBackground

        setupTableView()
        setupHeaderView()
        applyTabBarLayoutForSizeClass()
        fetchEpisodes()
        fetchRelationsAndCharacters()
        fetchAniListProgress()
        refreshButtonStates()
        headerView?.publishSidebarBackdrop()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let nb = navigationController?.navigationBar
        nb?.setBackgroundImage(UIImage(), for: .default)
        nb?.shadowImage = UIImage()
        nb?.tintColor = .white

        fetchAniListProgress()
        refreshButtonStates()
        headerView?.publishSidebarBackdrop()
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
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            applyTabBarLayoutForSizeClass()
            tableView.reloadData()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.tableView.reloadData()
        })
    }

    // MARK: - Setup

    func setupTableView() {
        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(EpisodeCell.self, forCellReuseIdentifier: EpisodeCell.reuseID)
        tableView.register(EpisodePairCell.self, forCellReuseIdentifier: EpisodePairCell.reuseID)
        tableView.register(ThreadPairCell.self, forCellReuseIdentifier: ThreadPairCell.reuseID)
        tableView.register(HorizontalCardsCell.self, forCellReuseIdentifier: HorizontalCardsCell.relationsReuseID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HeaderCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PaginationCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.separatorStyle = .none
        tableView.backgroundColor = hayasePageBackground
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.contentInsetAdjustmentBehavior = .never
        let tabBarH = tabBarController?.tabBar.frame.height ?? 83
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: tabBarH, right: 0)
        tableView.scrollIndicatorInsets = tableView.contentInset
        tableView.clipsToBounds = false
        view.clipsToBounds = true
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
        } else {
            headerView.configure(with: animeEntity)
        }
        headerView.onFavorite = { [weak self] in
            guard let self, let item = self.animeItem else { return }
            AniListTracking.shared.toggleFavourite(mediaID: item.id) { [weak self] _ in
                self?.refreshButtonStates()
            }
        }

        headerView.onBookmark = { [weak self] in
            guard let self, let item = self.animeItem else { return }
            if self.isOnList {
                AniListTracking.shared.fetchMediaWithEntry(anilistID: item.id) { [weak self] entry, _, _, _, _ in
                    if let listID = entry?.listID {
                        AniListTracking.shared.deleteEntry(listID: listID, mediaID: item.id) { [weak self] _ in
                            self?.refreshButtonStates()
                        }
                    }
                }
            } else {
                AniListTracking.shared.entry(mediaID: item.id, status: "PLANNING") { [weak self] _ in
                    self?.refreshButtonStates()
                }
            }
        }

        headerView.onShare = { [weak self] in
            guard let self = self else { return }
            let title = self.animeItem?.titleEnglish ?? self.animeItem?.titleRomaji
                ?? self.animeEntity?.animeTitleEnglish ?? self.animeEntity?.animeTitleJapanese
                ?? "Anime"
            let id = self.animeItem?.id ?? self.animeEntity?.animeAnilistId?.intValue
            var items: [Any] = [title]
            if let id = id, let url = URL(string: "https://anilist.co/anime/\(id)") {
                items.append(url)
            }
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = self.view
            self.present(activity, animated: true)
        }
        headerView.onPlayTrailer = { [weak self] in
            guard let self = self,
                  let trailerID = self.animeItem?.trailerYouTubeID,
                  let url = URL(string: "https://www.youtube.com/watch?v=\(trailerID)") else { return }
            let safari = SFSafariViewController(url: url)
            self.present(safari, animated: true)
        }
        headerView.onWatch = { [weak self] in
            self?.openExtensionSearch(episode: 1)
        }
        headerView.onEntryEditor = { [weak self] in
            self?.showEntryEditor()
        }
        headerView.onOpenAniList = { [weak self] in
            guard let self = self else { return }
            let id = self.animeItem?.id ?? self.animeEntity?.animeAnilistId?.intValue
            guard let id, let url = URL(string: "https://anilist.co/anime/\(id)") else { return }
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

        headerView.onGenreTapped = { [weak self] genre in
            self?.navigateToSearchTab(genre: genre)
        }

        headerView.onBadgeTapped = { [weak self] filterType, value in
            self?.navigateToSearchTab(filterType: filterType, value: value)
        }
    }

    // MARK: - AniList Entry Editor

    func showEntryEditor() {
        guard let item = animeItem else { return }

        AniListTracking.shared.fetchMediaWithEntry(anilistID: item.id) { [weak self] entry, _, _, _, _ in
            DispatchQueue.main.async {
                self?.presentEntryEditorSheet(mediaID: item.id, currentEntry: entry, totalEpisodes: item.episodes)
            }
        }
    }

    private func presentEntryEditorSheet(mediaID: Int, currentEntry: AnimeItem.MediaListEntry?, totalEpisodes: Int?) {
        let editorVC = EntryEditorViewController()
        editorVC.mediaID = mediaID
        editorVC.totalEpisodes = totalEpisodes
        editorVC.currentEntry = currentEntry
        editorVC.animeTitle = animeItem?.titleEnglish ?? animeItem?.titleRomaji ?? "Unknown"
        editorVC.coverURL = animeItem?.coverURL
        editorVC.bannerURL = animeItem?.bannerURL

        editorVC.onSave = { [weak self] in
            self?.fetchAniListProgress()
            self?.refreshButtonStates()
        }
        editorVC.onDelete = { [weak self] in
            self?.anilistProgress = 0
            self?.currentListStatus = nil
            self?.isOnList = false
            self?.tableView.reloadData()
            self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false, isOnList: false)
            self?.headerView?.updatePlayButtonTitle(listStatus: nil)
        }

        editorVC.modalPresentationStyle = .custom
        editorVC.transitioningDelegate = editorVC
        present(editorVC, animated: true)
    }

    // MARK: - AniList progress & button state

    func fetchAniListProgress() {
        guard let id = animeItem?.id ?? animeEntity?.animeAnilistId?.intValue, id > 0 else { return }
        AniListTracking.shared.fetchProgress(anilistID: id) { [weak self] progress in
            guard let self = self else { return }
            let newProgress = progress ?? 0
            DispatchQueue.main.async {
                guard self.anilistProgress != newProgress else { return }
                self.anilistProgress = newProgress
                if newProgress > 0 {
                    let desiredPage = newProgress / self.episodesPerPage + 1
                    self.currentEpisodePage = min(max(1, desiredPage), self.totalEpisodePages)
                }
                self.tableView.reloadData()
            }
        }
    }

    func refreshButtonStates() {
        guard let id = animeItem?.id ?? animeEntity?.animeAnilistId?.intValue, id > 0 else { return }
        AniListTracking.shared.checkIsFavourite(mediaID: id) { [weak self] isFav in
            DispatchQueue.main.async {
                self?.isFavorite = isFav
                self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false,
                                                     isOnList: self?.isOnList ?? false)
            }
        }
        AniListTracking.shared.fetchMediaWithEntry(anilistID: id) { [weak self] entry, _, _, _, _ in
            DispatchQueue.main.async {
                self?.isOnList = entry != nil
                self?.currentListStatus = entry?.status
                self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false,
                                                     isOnList: self?.isOnList ?? false)
                self?.headerView?.updatePlayButtonTitle(listStatus: entry?.status)
            }
        }
    }

    // MARK: - Tab bar

    func tabChanged(to index: Int) {
        let sectionMap: [Int: Section] = [0: .episodes, 1: .relations, 2: .threads, 3: .themes]
        guard let sec = sectionMap[index] else { return }
        activeSection = sec
        let contentRange = Section.episodes.rawValue..<Section.allCases.count
        tableView.reloadSections(IndexSet(integersIn: contentRange), with: .automatic)
        if sec == .threads && threads.isEmpty && !threadsLoading { fetchThreads() }
        if sec == .themes  && themes.isEmpty  && !themesLoading  { fetchThemes()  }
    }

    func setEpisodePage(_ page: Int) {
        let clamped = min(max(1, page), totalEpisodePages)
        guard clamped != currentEpisodePage else { return }
        currentEpisodePage = clamped
        let sectionsToReload = IndexSet([Section.episodes.rawValue, Section.episodePagination.rawValue])
        tableView.reloadSections(sectionsToReload, with: .automatic)
    }

    // MARK: - Navigation

    func openExtensionSearch(episode: Int) {
        let searchVC = ExtensionSearchViewController()
        searchVC.animeItem = animeItem
        searchVC.initialEpisode = episode

        if traitCollection.horizontalSizeClass == .regular {
            searchVC.modalPresentationStyle = .custom
            searchVC.transitioningDelegate = searchVC
        } else {
            searchVC.modalPresentationStyle = .fullScreen
        }

        guard var presenter = view.window?.rootViewController else {
            self.present(searchVC, animated: true)
            return
        }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(searchVC, animated: true)
    }
}
