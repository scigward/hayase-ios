//
//  Layout.swift
//  Hayase
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
private let hayaseAnimeBannerBackdropAnimeRoute = "anime"

// MARK: - AnimeDetailBannerBackdropView

private final class AnimeDetailBannerBackdropView: UIView {
    private final class GradientView: UIView {
        private var centerX: CGFloat = 0.5918

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

        func setCompact(_ compact: Bool) {
            let nextCenterX: CGFloat = compact ? 0.50 : 0.5918
            guard abs(nextCenterX - centerX) > 0.0001 else { return }
            centerX = nextCenterX
            setNeedsDisplay()
        }

        override func draw(_ rect: CGRect) {
            guard bounds.width > 0, bounds.height > 0,
                  let context = UIGraphicsGetCurrentContext(),
                  let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: [
                                                UIColor.black.withAlphaComponent(0.16).cgColor,
                                                UIColor.black.withAlphaComponent(0.16).cgColor,
                                                UIColor.black.cgColor,
                                            ] as CFArray,
                                            locations: [0.0, 0.3056, 1.0]) else { return }

            let center = CGPoint(x: bounds.width * centerX, y: bounds.height * 0.3497)
            context.saveGState()
            context.clip(to: bounds)
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: bounds.width * 0.75, y: bounds.height * 0.65)
            context.drawRadialGradient(gradient,
                                       startCenter: .zero,
                                       startRadius: 0,
                                       endCenter: .zero,
                                       endRadius: 1,
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
        }
    }

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .clear
        return view
    }()
    private let gradientView = GradientView()
    private var currentURLString: String?
    private var imageTask: URLSessionDataTask?
    private var heightConstraint: NSLayoutConstraint?

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

    func applyAlpha(_ alpha: CGFloat, animated: Bool) {
        let clamped = min(max(alpha, 0), 1)
        let changes = { self.alpha = clamped }
        if animated {
            UIView.animate(withDuration: 0.5, animations: changes)
        } else {
            changes()
        }
    }

    func setImage(urlString: String?) {
        guard let urlString else {
            currentURLString = nil
            imageTask?.cancel()
            imageTask = nil
            imageView.image = nil
            return
        }

        guard currentURLString != urlString else { return }
        currentURLString = urlString
        imageTask?.cancel()
        imageTask = nil

        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            imageView.image = cached
            return
        }

        guard let url = URL(string: urlString) else {
            imageView.image = nil
            return
        }

        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
            DispatchQueue.main.async {
                guard self?.currentURLString == urlString else { return }
                UIView.transition(with: self?.imageView ?? UIImageView(),
                                  duration: 0.3,
                                  options: .transitionCrossDissolve,
                                  animations: { self?.imageView.image = image })
            }
        }
        imageTask?.resume()
    }
}

// MARK: - AnimeDialogBackdropView

private final class AnimeDialogBackdropView: UIView {
    private let stripeLayer = HayaseStripePattern.customBackground.makeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.black.withAlphaComponent(0.82)
        layer.addSublayer(stripeLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stripeLayer.frame = bounds
    }
}

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

// MARK: - AnimeTagChipButton

final class AnimeTagChipButton: UIButton {
    var dashedBorder = false {
        didSet { setNeedsLayout() }
    }
    var isSpoilerChip = false {
        didSet { updateSpoilerRendering() }
    }

    private let dashLayer = CAShapeLayer()
    private static let blurContext = CIContext(options: nil)

    private let blurredTitleView = UIImageView()
    private var blurredTitleCacheKey: String?

    override var isHighlighted: Bool {
        didSet { updateSpoilerRendering() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    override func setTitle(_ title: String?, for state: UIControl.State) {
        super.setTitle(title, for: state)
        blurredTitleCacheKey = nil
        updateSpoilerRendering()
    }

    private func setupLayers() {
        layer.addSublayer(dashLayer)
        dashLayer.fillColor = UIColor.clear.cgColor
        dashLayer.lineDashPattern = [6, 4]
        dashLayer.isHidden = true

        blurredTitleView.isUserInteractionEnabled = false
        blurredTitleView.contentMode = .center
        blurredTitleView.isHidden = true
        addSubview(blurredTitleView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dashLayer.isHidden = !dashedBorder
        if dashedBorder {
            dashLayer.frame = bounds
            dashLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: layer.cornerRadius).cgPath
            dashLayer.strokeColor = UIColor.HayaseTheme.secondary.cgColor
            dashLayer.lineWidth = 2
        }

        blurredTitleView.frame = titleLabel?.frame ?? bounds.insetBy(dx: contentEdgeInsets.left, dy: 0)
        updateSpoilerRendering()
    }

    private func updateSpoilerRendering() {
        guard isSpoilerChip, !isHighlighted else {
            titleLabel?.alpha = 1
            blurredTitleView.isHidden = true
            return
        }

        titleLabel?.alpha = 0
        blurredTitleView.isHidden = false
        renderBlurredTitleIfNeeded()
    }

    private func renderBlurredTitleIfNeeded() {
        guard let text = title(for: .normal), !text.isEmpty else {
            blurredTitleView.image = nil
            blurredTitleCacheKey = nil
            return
        }

        let font = titleLabel?.font ?? .systemFont(ofSize: 14)
        let color = titleColor(for: .normal) ?? UIColor.HayaseTheme.mutedForeground
        let size = text.size(withAttributes: [.font: font])
        let targetSize = CGSize(width: ceil(size.width) + 16, height: max(ceil(size.height), bounds.height))
        let key = "\(text)|\(font.pointSize)|\(bounds.height)|\(color.description)"
        guard key != blurredTitleCacheKey else { return }
        blurredTitleCacheKey = key

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let textImage = renderer.image { _ in
            let rect = CGRect(x: (targetSize.width - size.width) / 2,
                              y: (targetSize.height - size.height) / 2,
                              width: size.width,
                              height: size.height)
            text.draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
        }

        guard let cgImage = textImage.cgImage else {
            blurredTitleView.image = textImage
            return
        }

        let input = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(input, forKey: kCIInputImageKey)
        filter?.setValue(6.0, forKey: kCIInputRadiusKey)
        guard let output = filter?.outputImage?.cropped(to: input.extent),
              let rendered = Self.blurContext.createCGImage(output, from: input.extent) else {
            blurredTitleView.image = textImage
            return
        }
        blurredTitleView.image = UIImage(cgImage: rendered, scale: textImage.scale, orientation: textImage.imageOrientation)
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

    // MARK: - Cover

    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.isUserInteractionEnabled = true
        iv.layer.cornerRadius = 4   // interface Dialog.Trigger: rounded = Tailwind 0.25rem = 4pt
        iv.backgroundColor = UIColor(white: 0.16, alpha: 1)
        return iv
    }()

    private let coverOverlayView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0)
        v.isUserInteractionEnabled = false
        v.alpha = 0
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
        return button
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
        l.lineBreakMode = .byWordWrapping
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
        // interface: whitespace-pre-wrap preserves \n, word-wrap for soft wrapping
        l.lineBreakMode = .byWordWrapping
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
        b.setImage(UIImage.hayaseIcon("pencil-line")?.withConfiguration(iconCfg), for: .normal)
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
        b.backgroundColor = UIColor.HayaseTheme.secondary
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        return b
    }()

    private let bookmarkButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage.hayaseIcon("bookmark")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor.HayaseTheme.secondary
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        return b
    }()

    private let shareButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage.hayaseIcon("share-2")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor.HayaseTheme.secondary
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
        b.backgroundColor = UIColor.HayaseTheme.secondary
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        b.isHidden = true
        return b
    }()

    private let anilistButton: UIButton = {
        let b = UIButton(type: .custom)
        b.backgroundColor = UIColor.HayaseTheme.secondary
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
        b.backgroundColor = UIColor.HayaseTheme.secondary
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

    private var coverImageTask: URLSessionDataTask?
    private var displayedCoverURL: String?
    private var bannerHidden = false
    private var hasTrailer = false
    private var rawDescription: String?

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
        coverAndTextColumn.isLayoutMarginsRelativeArrangement = true

        coverOverlayView.translatesAutoresizingMaskIntoConstraints = false
        coverOverlayIcon.translatesAutoresizingMaskIntoConstraints = false
        coverButton.translatesAutoresizingMaskIntoConstraints = false
        coverImageView.addSubview(coverOverlayView)
        coverOverlayView.addSubview(coverOverlayIcon)
        coverImageView.addSubview(coverButton)
        NSLayoutConstraint.activate([
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
        coverButton.addTarget(self, action: #selector(coverTouchDown), for: [.touchDown, .touchDragEnter])
        coverButton.addTarget(self, action: #selector(coverTouchEnded), for: [.touchCancel, .touchDragExit, .touchUpOutside])
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

    private func applyLayoutForSizeClass() {
        let isRegular = traitCollection.horizontalSizeClass == .regular
        let measuredWidth = measuredContentWidth()
        let hPad = interfaceHorizontalPadding(for: measuredWidth)

        contentTopConstraint?.constant = isRegular ? 128 : 48

        updateHeaderRowInsets(isRegular: isRegular)
        updateGenresScrollInset(isRegular: isRegular)
        genresScrollView.isHidden = false
        chipWrapView.isHidden = true
        genresContainerHeightConstraint?.isActive = true
        chipWrapBottomConstraint?.isActive = false

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
        descriptionLabel.font = .nunito(ofSize: 14, weight: .light)
        // Rebuild attributed text so paragraph style picks up the new font size
        if let raw = rawDescription {
            setDescriptionText(raw)
        }

        badgesScrollView.isHidden = !isRegular
        descriptionLabel.isHidden = !isRegular

        textColumnWidthConstraint?.isActive = !isRegular

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
            actionsRow.addArrangedSubview(headerFollowerStack)
            actionsRow.addArrangedSubview(actionsTrailingSpacer)
            actionsRow.setCustomSpacing(20, after: playCombo)
            anilistButton.isHidden = false
            malButton.isHidden = (malId == nil)
            updateFollowerProfileSpacing(isRegular: true)
            headerFollowerStack.isHidden = headerFollowerStack.arrangedSubviews.isEmpty
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
            headerFollowerStack.isHidden = true
        }
        updateActionVisibilityForCurrentWidth()
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
        updateActionVisibilityForCurrentWidth()
        let isRegular = traitCollection.horizontalSizeClass == .regular
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
        let isRegular = traitCollection.horizontalSizeClass == .regular
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
        titleLabel.preferredMaxLayoutWidth = maxW
        romajiLabel.preferredMaxLayoutWidth = maxW
        descriptionLabel.preferredMaxLayoutWidth = maxW
        titleLabel.invalidateIntrinsicContentSize()
        romajiLabel.invalidateIntrinsicContentSize()
        descriptionLabel.invalidateIntrinsicContentSize()
    }

    private func updateActionVisibilityForCurrentWidth() {
        let isRegular = traitCollection.horizontalSizeClass == .regular
        let measuredWidth = measuredContentWidth()
        let effectiveWidth = isRegular ? min(measuredWidth, 1600) : measuredWidth
        let hPad = interfaceHorizontalPadding(for: measuredWidth)
        let contentWidth = max(0, effectiveWidth - 2 * hPad)
        let isNarrow = contentWidth < 380

        if isNarrow {
            playComboWidthConstraint?.priority = .required
            playComboWidthConstraint?.constant = contentWidth
        } else {
            playComboWidthConstraint?.priority = UILayoutPriority(999)
            playComboWidthConstraint?.constant = 180
        }

        shareButton.isHidden = isNarrow
        trailerButton.isHidden = isNarrow || !hasTrailer
        anilistButton.isHidden = !isRegular
        malButton.isHidden = !isRegular || malId == nil
        headerFollowerStack.isHidden = !isRegular || headerFollowerStack.arrangedSubviews.isEmpty
        updateFollowerProfileSpacing(isRegular: isRegular)
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
        // +layout.svelte: 2xs:px-3 xl:px-14. iPads use 12pt; 56pt starts at xl.
        measuredWidth >= 1280 ? 56 : 12
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
        let targetAlpha: CGFloat = shouldHide ? 0.05 : 1.0
        postSidebarBackdrop(scrollOffset: scrollOffset, alpha: targetAlpha)
        bannerHidden = shouldHide
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
    @objc private func coverTapped() {
        setCoverSelected(false, animated: true)
        onOpenCover?(displayedCoverURL, coverImageView.image)
    }

    @objc private func coverTouchDown() {
        setCoverSelected(true, animated: true)
    }

    @objc private func coverTouchEnded() {
        setCoverSelected(false, animated: true)
    }

    private func setCoverSelected(_ selected: Bool, animated: Bool) {
        let changes = {
            self.coverImageView.transform = selected ? CGAffineTransform(scaleX: 1.02, y: 1.02) : .identity
            self.coverOverlayView.alpha = selected ? 1 : 0
            self.coverOverlayView.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(selected ? 0.5 : 0)
            self.coverOverlayIcon.alpha = selected ? 1 : 0
            self.coverOverlayIcon.transform = selected ? .identity : CGAffineTransform(scaleX: 0.75, y: 0.75)
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            changes()
        }
    }

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
        // BannerImage is route-owned, matching interface +layout.svelte.
    }

    // MARK: - Configure (Animes CoreData entity)

    func configure(with anime: Animes?) {
        guard let anime = anime else { return }
        anilistId = anime.animeAnilistId?.intValue

        let item = AniListUtil.animeItem(from: anime)
        titleLabel.text = AniListUtil.title(for: item)
        romajiLabel.text = AniListUtil.alternateTitle(for: item)
        romajiLabel.isHidden = romajiLabel.text == nil

        rebuildBadges(score:   anime.animeScore?.floatValue,
                      status:  anime.animeStatus,
                      episodes: anime.animeTotalEps?.intValue,
                      nextEp:  anime.animeNextEps?.intValue,
                      format:  nil, season: nil)

        genresContainer.isHidden = true

        setDescriptionText(anime.animeDescription)

        trailerButton.isHidden = true

        displayedBannerURL = anime.animeImgS ?? anime.animeImgL ?? anime.animeImgM
        postSidebarBackdrop(urlString: displayedBannerURL,
                            scrollOffset: 0,
                            alpha: bannerHidden ? 0.05 : 1.0)
        displayedCoverURL = anime.animeImgL ?? anime.animeImgM
        setCoverSelected(false, animated: false)
        loadImage(from: displayedCoverURL,
                  into: coverImageView, task: &coverImageTask)
    }

    // MARK: - Configure (AnimeItem from AniList)

    func configure(with item: AnimeItem) {
        anilistId = item.id
        malId = item.malId

        titleLabel.text = AniListUtil.title(for: item)
        romajiLabel.text = AniListUtil.alternateTitle(for: item)
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

        setGenres(item.genres.map { String($0) }, tags: item.tags)

        setDescriptionText(item.description)

        updateTrailerButton(trailerYouTubeID: item.trailerYouTubeID)

        let bannerFallback = item.bannerURL ?? item.coverURL
        AniListClient.fetchFanartURL(anilistID: item.id) { [weak self] fanartURL in
            guard let self else { return }
            let urlStr = fanartURL ?? bannerFallback
            self.displayedBannerURL = urlStr
            self.postSidebarBackdrop(urlString: urlStr,
                                     scrollOffset: 0,
                                     alpha: self.bannerHidden ? 0.05 : 1.0)
        }
        displayedCoverURL = item.coverURL
        setCoverSelected(false, animated: false)
        loadImage(from: displayedCoverURL, into: coverImageView, task: &coverImageTask)
    }

    func updateBanner(from urlString: String) {
        displayedBannerURL = urlString
        postSidebarBackdrop(urlString: urlString,
                            scrollOffset: 0,
                            alpha: bannerHidden ? 0.05 : 1.0)
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
            if let progress, progress > 0, progress != eps {
                badge1Text = "\(progress) / \(eps) Episodes"
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

    // MARK: - Description

    private func setDescriptionText(_ raw: String?) {
        rawDescription = raw
        applyDescriptionAttributedText(interfaceDescription(from: raw))
    }

    private func interfaceDescription(from raw: String?) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "No description available."
        }
        let text = raw
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n+", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\n?\\(?Source: [^)]+\\)?\n?", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n?Notes?:[ |\n][^\n]+\n?", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No description available." : text
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
        genresStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let showHentai = UserDefaults.standard.object(forKey: "pref_showHentai") as? Bool ?? false
        let sortedTags = tags
            .filter { !$0.isAdult || showHentai }
            .sorted {
                if $0.rank != $1.rank { return $0.rank > $1.rank }
                return $0.id < $1.id
            }
        let chips = genres.map { makeGenreChip(text: $0, isTag: false, isSpoiler: false) }
            + sortedTags.map { makeGenreChip(text: $0.name, isTag: true, isSpoiler: $0.isMediaSpoiler || $0.isGeneralSpoiler) }
        chips.forEach { genresStack.addArrangedSubview($0) }
        chipWrapView.setChips(chips.map { chip in
            guard let button = chip as? AnimeTagChipButton else { return chip }
            return makeGenreChip(text: button.title(for: .normal) ?? "",
                                 isTag: button.dashedBorder,
                                 isSpoiler: button.isSpoilerChip)
        })
        genresContainer.isHidden = chips.isEmpty
        resetGenresScrollPosition()
    }

    func updateGenresAndTrailer(genres: [String], tags: [AnimeTag] = [], trailerYouTubeID: String?) {
        setGenres(genres, tags: tags)
        trailerButton.isHidden = trailerYouTubeID == nil
    }

    func updateAnimePageDetails(with item: AnimeItem) {
        anilistId = item.id
        malId = item.malId
        titleLabel.text = AniListUtil.title(for: item)
        romajiLabel.text = AniListUtil.alternateTitle(for: item)
        romajiLabel.isHidden = romajiLabel.text == nil
        setDescriptionText(item.description)
        setGenres(item.genres, tags: item.tags)
        updateTrailerButton(trailerYouTubeID: item.trailerYouTubeID)
        updateMALButtonVisibility()
    }

    func updateTrailerButton(trailerYouTubeID: String?) {
        hasTrailer = trailerYouTubeID != nil
        updateActionVisibilityForCurrentWidth()
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
        btn.setTitleColor(isTag ? UIColor.HayaseTheme.mutedForeground : .white, for: .normal)
        btn.setTitleColor(storedAccentColor, for: .highlighted)
        btn.backgroundColor = UIColor.HayaseTheme.secondary.withAlphaComponent(isTag ? 0.4 : 1)
        btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        btn.layer.cornerRadius = 6
        btn.layer.masksToBounds = true
        btn.dashedBorder = isTag
        btn.isSpoilerChip = isSpoiler
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
    var routeAnimeID: Int? { animeItem?.id ?? animeEntity?.animeAnilistId?.intValue }

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
    private var animeBackdropLeadingConstraint: NSLayoutConstraint?
    private var animeBackdropTrailingConstraint: NSLayoutConstraint?
    var headerView: AnimeInfoHeaderView!
    private var coverDialogImageTask: URLSessionDataTask?
    var isFavorite = false
    var isOnList = false
    var episodes: [AniZipEpisode] = []
    var anilistProgress: Int = 0
    var currentListStatus: String?
    var currentAnimeAccent: UIColor = .white
    var relations: [AnimeRelation] = []
    var relationGraph: AnimeRelationGraph?
    var relationGraphExpanded = false
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

    var threads: [AniListThread] = []
    var themes: [AnimeThemesTheme] = []
    var recommendations: [AnimeItem] = []
    var followingEntriesByEpisode: [Int: [AniListUserSummary]] = [:]
    var threadTotalCount: Int = 0
    var activeThemeVideoURL: String?
    var threadsLoading = false
    var themesLoading = false
    var animePageRequestID = UUID()
    var animePageErrorDescription: String?

    var activeSection: Section = .episodes

    lazy var tabBar: HTabBar = {
        let bar = HTabBar(titles: ["Episodes", "Relations", "Threads", "Themes", "Recommendations"])
        bar.onChange = { [weak self] index in
            self?.tabChanged(to: index)
        }
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    var tabBarScrollView: UIScrollView?

    lazy var tabBarContainer: UIView = {
        let v = UIView()
        v.backgroundColor = hayasePageBackground
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        tabBarScrollView = scrollView
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(scrollView)
        scrollView.addSubview(tabBar)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: v.topAnchor, constant: 24),
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
        let sideInset = Self.interfacePageSideInset(for: view.bounds.width)
        tabBarScrollView?.contentInset = UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: sideInset)
        tabBarScrollView?.scrollIndicatorInsets = tabBarScrollView?.contentInset ?? .zero
    }

    enum Section: Int, CaseIterable {
        case header = 0, episodes, episodePagination, relations, threads, themes, recommendations
    }

    static let gridMinColWidth: CGFloat = 500
    static let episodeGap: CGFloat = 16
    static let threadGap: CGFloat = 40

    static func interfacePageSideInset(for width: CGFloat) -> CGFloat {
        // Interface inner wrapper: 2xs:px-3 xl:px-14.
        width >= 1280 ? 56 : 12
    }

    var episodeColumnCount: Int {
        let sideInset = Self.interfacePageSideInset(for: tableView.frame.width)
        let gridWidth = tableView.frame.width - 2 * sideInset
        if traitCollection.horizontalSizeClass == .regular
            && gridWidth >= 2 * Self.gridMinColWidth + Self.episodeGap {
            return 2
        }
        return 1
    }

    var threadColumnCount: Int {
        let sideInset = Self.interfacePageSideInset(for: tableView.frame.width)
        let gridWidth = tableView.frame.width - 2 * sideInset
        if traitCollection.horizontalSizeClass == .regular
            && gridWidth >= 2 * Self.gridMinColWidth + Self.threadGap {
            return 2
        }
        return 1
    }

    // MARK: - Search navigation helpers

    func navigateToSearchTab(genre: String) {
        let state = Route.SearchState(
            genres: SearchValues.genreSet.contains(genre) ? [genre] : [],
            tags: SearchValues.genreSet.contains(genre) ? [] : [genre])
        Router.shared.navigate(.search(state), hostTabIndex: tabBarController?.selectedIndex)
    }

    func navigateToSearchTab(filterType: String, value: String) {
        var state = Route.SearchState()
        switch filterType {
        case "format":
            state.formats = [value]
        case "status":
            state.statuses = [value]
        case "season":
            let parts = value.components(separatedBy: " ")
            if parts.count == 2, let year = Int(parts[1]) {
                state.season = parts[0].uppercased()
                state.year = String(year)
            } else {
                state.season = value.uppercased()
            }
        case "score":
            state.sort = value
        default:
            break
        }
        Router.shared.navigate(.search(state), hostTabIndex: tabBarController?.selectedIndex)
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
        headerView?.clearFollowingAvatars()
        applyTabBarLayoutForSizeClass()
        fetchAnimePageData()
        fetchEpisodes()
        applyViewerStateFromRouteMedia()
        headerView?.publishSidebarBackdrop()
    }

    deinit {
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
            configureAnimeBackdropForCurrentSize()
            applyTabBarLayoutForSizeClass()
            tableView.reloadData()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.configureAnimeBackdropForCurrentSize(width: size.width)
            self.tableView.reloadData()
        })
    }

    // MARK: - Setup

    private func setupAnimeBackdropView() {
        animeBackdropView.translatesAutoresizingMaskIntoConstraints = false
        animeBackdropCoverView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(animeBackdropView)
        view.addSubview(animeBackdropCoverView)
        animeBackdropLeadingConstraint = animeBackdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        animeBackdropTrailingConstraint = animeBackdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        NSLayoutConstraint.activate([
            animeBackdropView.topAnchor.constraint(equalTo: view.topAnchor),
            animeBackdropLeadingConstraint!,
            animeBackdropTrailingConstraint!,

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

    func setAnimeBackdropCovered(_ covered: Bool) {
        guard covered != isAnimeBackdropCovered else { return }
        isAnimeBackdropCovered = covered
        UIView.animate(withDuration: 0.5, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.animeBackdropCoverView.alpha = covered ? 1 : 0
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
            animeBackdropView.applyAlpha(alpha, animated: true)
        }
    }

    func setupTableView() {
        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.delegate = self
        tableView.dataSource = self
        tableView.bounces = false
        tableView.alwaysBounceVertical = false
        tableView.register(EpisodeCell.self, forCellReuseIdentifier: EpisodeCell.reuseID)
        tableView.register(EpisodePairCell.self, forCellReuseIdentifier: EpisodePairCell.reuseID)
        tableView.register(ThreadPairCell.self, forCellReuseIdentifier: ThreadPairCell.reuseID)
        tableView.register(HorizontalCardsCell.self, forCellReuseIdentifier: HorizontalCardsCell.relationsReuseID)
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
            relations = item.relations
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
                guard let listID = item.mediaListEntry?.listID else { return }
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
            guard let self = self else { return }
            let title = self.animeItem.map { AniListUtil.title(for: $0) }
                ?? self.animeEntity.map { AniListUtil.title(for: $0) }
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
                  let trailerID = self.animeItem?.trailerYouTubeID else { return }
            self.presentTrailerDialog(trailerID: trailerID)
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

        headerView.onOpenCover = { [weak self] urlString, image in
            self?.presentCoverDialog(urlString: urlString, image: image)
        }

        headerView.onGenreTapped = { [weak self] genre in
            self?.navigateToSearchTab(genre: genre)
        }

        headerView.onBadgeTapped = { [weak self] filterType, value in
            self?.navigateToSearchTab(filterType: filterType, value: value)
        }
    }

    private func presentCoverDialog(urlString: String?, image: UIImage?) {
        guard image != nil || urlString != nil else { return }
        coverDialogImageTask?.cancel()

        let dialog = UIViewController()
        dialog.modalPresentationStyle = .overFullScreen
        dialog.modalTransitionStyle = .crossDissolve
        dialog.view.backgroundColor = .clear

        let backdropView = AnimeDialogBackdropView()
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        dialog.view.addSubview(backdropView)

        let imageContainer = UIView()
        imageContainer.backgroundColor = UIColor.HayaseTheme.muted
        imageContainer.layer.cornerRadius = 8
        imageContainer.layer.masksToBounds = true
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        dialog.view.addSubview(imageContainer)

        // interface Dialog.Content for cover: `flex justify-center p-0 overflow-clip`
        // + default dialog-content sm:rounded-lg = 8pt corner radius
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.HayaseTheme.muted
        imageView.layer.cornerRadius = 8  // sm:rounded-lg
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(imageView)

        let closeButton = UIButton(type: .system)
        closeButton.backgroundColor = .clear
        closeButton.tintColor = UIColor.HayaseTheme.foreground.withAlphaComponent(0.7)
        closeButton.layer.cornerRadius = 2
        closeButton.layer.masksToBounds = true
        closeButton.setImage(UIImage.hayaseIcon("x", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)), for: .normal)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(dismissPresentedCoverDialog), for: .touchUpInside)
        dialog.view.addSubview(closeButton)

        let imageSize = image?.size ?? CGSize(width: 180, height: 256)
        let aspect = imageSize.width / max(imageSize.height, 1)
        let widthLimit = imageContainer.widthAnchor.constraint(lessThanOrEqualTo: dialog.view.widthAnchor, multiplier: 0.92)
        let heightLimit = imageContainer.heightAnchor.constraint(lessThanOrEqualTo: dialog.view.heightAnchor, multiplier: 0.84)
        let preferredHeight = imageContainer.heightAnchor.constraint(equalTo: dialog.view.heightAnchor, multiplier: 0.84)
        widthLimit.priority = .required
        heightLimit.priority = .required
        preferredHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: dialog.view.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: dialog.view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: dialog.view.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: dialog.view.bottomAnchor),

            imageContainer.centerXAnchor.constraint(equalTo: dialog.view.centerXAnchor),
            imageContainer.centerYAnchor.constraint(equalTo: dialog.view.centerYAnchor),
            widthLimit,
            heightLimit,
            preferredHeight,
            imageContainer.widthAnchor.constraint(equalTo: imageContainer.heightAnchor, multiplier: aspect),

            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            closeButton.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Tap outside image to dismiss
        let closeTap = UITapGestureRecognizer(target: self, action: #selector(dismissPresentedCoverDialog))
        backdropView.addGestureRecognizer(closeTap)
        loadCoverDialogImageIfNeeded(urlString: urlString, imageView: imageView)
        present(dialog, animated: true)
    }

    @objc private func dismissPresentedCoverDialog() {
        coverDialogImageTask?.cancel()
        coverDialogImageTask = nil
        presentedViewController?.dismiss(animated: true)
    }

    private func loadCoverDialogImageIfNeeded(urlString: String?, imageView: UIImageView) {
        guard imageView.image == nil,
              let urlString,
              let url = URL(string: urlString) else { return }
        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            imageView.image = cached
            return
        }

        coverDialogImageTask = URLSession.shared.dataTask(with: url) { [weak imageView] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
            DispatchQueue.main.async {
                UIView.transition(with: imageView ?? UIImageView(),
                                  duration: 0.2,
                                  options: .transitionCrossDissolve,
                                  animations: { imageView?.image = image })
            }
        }
        coverDialogImageTask?.resume()
    }

    private func presentTrailerDialog(trailerID: String) {
        guard let url = URL(string: "https://www.youtube-nocookie.com/embed/\(trailerID)?autoplay=1&rel=0&cc_lang_pref=ja") else { return }

        let dialog = UIViewController()
        dialog.modalPresentationStyle = .overFullScreen
        dialog.modalTransitionStyle = .crossDissolve
        dialog.view.backgroundColor = UIColor.black.withAlphaComponent(0.82)

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        }

        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.layer.cornerRadius = 8
        webView.layer.masksToBounds = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        dialog.view.addSubview(webView)

        let width = webView.widthAnchor.constraint(equalTo: dialog.view.widthAnchor, constant: -32)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            webView.centerXAnchor.constraint(equalTo: dialog.view.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: dialog.view.centerYAnchor),
            webView.widthAnchor.constraint(lessThanOrEqualTo: dialog.view.widthAnchor, constant: -32),
            webView.heightAnchor.constraint(lessThanOrEqualTo: dialog.view.heightAnchor, multiplier: 0.8),
            webView.heightAnchor.constraint(equalTo: webView.widthAnchor, multiplier: 9.0 / 16.0),
            width,
        ])

        let closeTap = UITapGestureRecognizer(target: self, action: #selector(dismissPresentedCoverDialog))
        closeTap.cancelsTouchesInView = false
        dialog.view.addGestureRecognizer(closeTap)
        webView.load(URLRequest(url: url))
        present(dialog, animated: true)
    }

    // MARK: - AniList Entry Editor

    func showEntryEditor() {
        guard let item = animeItem else { return }
        presentEntryEditorSheet(mediaID: item.id, currentEntry: item.mediaListEntry, totalEpisodes: item.episodes)
    }

    private func presentEntryEditorSheet(mediaID: Int, currentEntry: AnimeItem.MediaListEntry?, totalEpisodes: Int?) {
        let editorVC = EntryEditorViewController()
        editorVC.mediaID = mediaID
        editorVC.totalEpisodes = totalEpisodes
        editorVC.currentEntry = currentEntry
        editorVC.animeTitle = animeItem.map { AniListUtil.title(for: $0) } ?? "Unknown"
        editorVC.coverURL = animeItem?.coverURL
        editorVC.bannerURL = animeItem?.bannerURL

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

        editorVC.modalPresentationStyle = .custom
        editorVC.transitioningDelegate = editorVC
        present(editorVC, animated: true)
    }

    // MARK: - AniList progress & button state

    private func applyViewerStateFromRouteMedia() {
        guard let item = animeItem else { return }
        applyViewerState(from: item)
    }

    func applyViewerState(from item: AnimeItem) {
        if let favourite = item.isFavourite {
            isFavorite = favourite
        }
        if let entry = item.mediaListEntry {
            isOnList = true
            currentListStatus = entry.status
            anilistProgress = entry.progress
        } else if TrackerAccountManager.shared.isLoggedIn(.anilist) {
            isOnList = false
            currentListStatus = nil
            anilistProgress = 0
        }
        syncEpisodePageToInterfaceProgress()
        headerView?.updateButtonStates(isFavorite: isFavorite, isOnList: isOnList)
        headerView?.updatePlayButtonTitle(listStatus: currentListStatus)
    }

    private func refreshViewerStateAfterMutation() {
        guard let id = animeItem?.id ?? animeEntity?.animeAnilistId?.intValue, id > 0 else { return }
        AniListTracking.shared.fetchMediaWithEntry(anilistID: id) { [weak self] entry, _, _, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateAnimeItemListEntry(entry)
                self.isOnList = entry != nil
                self.syncEpisodePageToInterfaceProgress()
                self.tableView.reloadData()
                self.headerView?.updateButtonStates(isFavorite: self.isFavorite, isOnList: self.isOnList)
                self.headerView?.updatePlayButtonTitle(listStatus: entry?.status)
            }
        }
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

    func tabChanged(to index: Int) {
        let sectionMap: [Int: Section] = [
            0: .episodes,
            1: .relations,
            2: .threads,
            3: .themes,
            4: .recommendations
        ]
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
