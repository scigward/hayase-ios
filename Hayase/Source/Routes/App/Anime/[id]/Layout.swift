//
//  Layout.swift
//  Hayase
//

import UIKit

// MARK: - Color constants

let hayasePageBackground = UIColor(red: 0.047, green: 0.047, blue: 0.055, alpha: 1.0)
let hayaseCardBackground = UIColor(red: 0.031, green: 0.031, blue: 0.039, alpha: 1.0)

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
}

// MARK: - ChipWrapView

final class ChipWrapView: UIView {

    private var chipViews: [UIView] = []
    var chipHeight: CGFloat = 28
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func setChips(_ views: [UIView]) {
        chipViews.forEach { $0.removeFromSuperview() }
        chipViews = views
        for v in views { addSubview(v) }
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 0
        var y: CGFloat = 0
        for chip in chipViews {
            let size = chip.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: chipHeight))
            let w = size.width
            if x + w > bounds.width && x > 0 {
                x = 0
                y += chipHeight + verticalSpacing
            }
            chip.frame = CGRect(x: x, y: y, width: w, height: chipHeight)
            x += w + horizontalSpacing
        }
    }

    override var intrinsicContentSize: CGSize {
        guard !chipViews.isEmpty else { return CGSize(width: UIView.noIntrinsicMetric, height: 0) }
        let maxW = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        for chip in chipViews {
            let size = chip.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: chipHeight))
            let w = size.width
            if x + w > maxW && x > 0 {
                x = 0
                y += chipHeight + verticalSpacing
            }
            x += w + horizontalSpacing
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: y + chipHeight)
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

    static let bannerHeight: CGFloat = 350

    // MARK: - Stacks

    private var contentStack: UIStackView!
    private var coverAndTextColumn: UIStackView!
    private var textColumn: UIStackView!
    private var actionsRow: UIStackView!
    private var playCombo: UIStackView!
    private let actionsTrailingSpacer: UIView = {
        let v = UIView()
        v.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
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
        let bgColor = UIColor(red: 0.047, green: 0.047, blue: 0.055, alpha: 1.0)
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
        iv.layer.cornerRadius = 6
        iv.backgroundColor = UIColor(white: 0.08, alpha: 1)
        return iv
    }()

    // MARK: - Text labels

    private let romajiLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 16, weight: .light)
        l.textColor = UIColor(white: 0.649, alpha: 1.0)
        l.numberOfLines = 0
        l.textAlignment = .center
        l.isHidden = true
        return l
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 30, weight: .black)
        l.textColor = .white
        l.numberOfLines = 0
        l.textAlignment = .center
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
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        b.setImage(UIImage(systemName: "play.fill")?.withConfiguration(iconCfg), for: .normal)
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
        b.setImage(UIImage(systemName: "pencil.line")?.withConfiguration(iconCfg), for: .normal)
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
        b.setImage(UIImage(systemName: "heart")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        return b
    }()

    private let bookmarkButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage(systemName: "bookmark")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        return b
    }()

    private let shareButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage(systemName: "arrowshape.turn.up.right")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        return b
    }()

    private let trailerButton: UIButton = {
        let b = UIButton(type: .custom)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let symName: String
        if #available(iOS 16.0, *) {
            symName = "clapperboard.fill"
        } else {
            symName = "film"
        }
        let img = UIImage(systemName: symName, withConfiguration: iconCfg)?
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
        textColumn.spacing = 6

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
            textColumn.spacing = 8
            textColumn.setCustomSpacing(8, after: titleLabel)
            textColumn.setCustomSpacing(8, after: badgesScrollView)
        } else {
            textColumn.alignment = .center
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
        shareButton.setImage(UIImage(systemName: "checkmark")?.withConfiguration(cfg), for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.shareButton.setImage(UIImage(systemName: "arrowshape.turn.up.right")?.withConfiguration(cfg), for: .normal)
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
        let heartName = isFavorite ? "heart.fill" : "heart"
        favoriteButton.setImage(UIImage(systemName: heartName)?.withConfiguration(cfg), for: .normal)
        favoriteButton.tintColor = isFavorite ? storedAccentColor : .white

        let bookmarkName = isOnList ? "bookmark.fill" : "bookmark"
        bookmarkButton.setImage(UIImage(systemName: bookmarkName)?.withConfiguration(cfg), for: .normal)
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
        AnimeService.fetchFanartURL(anilistID: item.id) { [weak self] fanartURL in
            guard let self else { return }
            let urlStr = fanartURL ?? bannerFallback
            self.displayedBannerURL = urlStr
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
