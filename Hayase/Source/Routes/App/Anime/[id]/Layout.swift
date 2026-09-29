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
        let changes = { self.alpha = clamped }
        if animated {
            UIView.animate(withDuration: 0.3,
                           delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: changes,
                           completion: completion)
        } else {
            layer.removeAllAnimations()
            changes()
            completion?(true)
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
    private var lastLaidOutHeight: CGFloat = 0

    func setChips(_ newChips: [UIView]) {
        subviews.forEach { $0.removeFromSuperview() }
        chipWidths = newChips.map { widthForChip($0) }
        lastLaidOutHeight = 0
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
        if abs(newH - lastLaidOutHeight) > 0.5 {
            lastLaidOutHeight = newH
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

    private let dashedOutline = CAShapeLayer()
    private let mirroredOutline = CAShapeLayer()
    private let dashedRuns = CAShapeLayer()
    private let leftBorderMask = CALayer()
    private let rightBorderMask = CALayer()
    private static let blurContext = CIContext(options: nil)

    private let blurredTitleView = UIImageView()
    private var blurredTitleCacheKey: String?
    private var spoilerFrames: [Int: UIImage] = [:]
    private var lastRevealed: Bool?
    private var isPointerOverTitle = false

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
        for outline in [dashedOutline, mirroredOutline, dashedRuns] {
            outline.fillColor = UIColor.clear.cgColor
            outline.isHidden = true
            layer.addSublayer(outline)
        }
        leftBorderMask.backgroundColor = UIColor.black.cgColor
        rightBorderMask.backgroundColor = UIColor.black.cgColor
        dashedOutline.mask = leftBorderMask
        mirroredOutline.mask = rightBorderMask

        blurredTitleView.isUserInteractionEnabled = false
        blurredTitleView.contentMode = .center
        blurredTitleView.isHidden = true
        addSubview(blurredTitleView)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(spoilerHover(_:))))
    }

    @objc private func spoilerHover(_ gesture: UIHoverGestureRecognizer) {
        isPointerOverTitle = (gesture.state == .began || gesture.state == .changed)
            && (titleLabel?.frame.contains(gesture.location(in: self)) ?? false)
        updateSpoilerRendering()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        updateSpoilerRendering()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        updateDashedBorderPath()
        blurredTitleView.frame = titleLabel?.frame ?? bounds.insetBy(dx: contentEdgeInsets.left, dy: 0)
        updateSpoilerRendering()
    }

    private func updateDashedBorderPath() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let hidden = !dashedBorder || bounds.isEmpty
        for outline in [dashedOutline, mirroredOutline, dashedRuns] {
            outline.isHidden = hidden
        }
        guard !hidden else { return }

        let lineWidth: CGFloat = 2
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let rect = pixelAligned(bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), scale: scale)

        // Interface: border-2 border-dashed border-secondary rounded-md.
        // Follow the rounded border, rather than clipping four square edges.
        // Inset the centerline so the full 2pt stroke stays inside the chip.
        let radius = max(0, min(layer.cornerRadius - lineWidth / 2, min(rect.width, rect.height) / 2))
        let perimeter = 2 * (rect.width + rect.height - 4 * radius) + 2 * CGFloat.pi * radius
        // Preserve the approved full-perimeter spacing, start point and phase.
        // Mirror AFTER dashing: restarting the pattern on a half-path changes
        // its appearance even when both sides are mathematically symmetric.
        let pairCount = max(1, (perimeter / (6 * lineWidth)).rounded())
        let dashLength = perimeter / (2 * pairCount)
        let original = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
            .copy(dashingWithPhase: 0, lengths: [dashLength, dashLength])
        var reflection = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2 * rect.midX, ty: 0)
        dashedOutline.path = original
        mirroredOutline.path = original.copy(using: &reflection)

        // Corners and vertical sides keep the mirrored original dashes. Mirroring
        // cuts the straight top and bottom edges at an arbitrary point of the
        // pattern, leaving slivers or merged dashes at the centre, so those two
        // edges are laid out separately and end on half a dash at the mirror axis.
        let cornerX = rect.minX + radius
        let segments = horizontalSegments(of: original)
        var splitX = rect.midX
        var runPath: CGPath?
        if let top = stretchedDashes(in: segments, y: rect.minY, from: cornerX, to: rect.midX, dashLength: dashLength),
           let bottom = stretchedDashes(in: segments, y: rect.maxY, from: cornerX, to: rect.midX, dashLength: dashLength) {
            splitX = cornerX
            let path = CGMutablePath()
            for (y, dashes) in [(rect.minY, top), (rect.maxY, bottom)] {
                for dash in dashes {
                    let mirroredStart = 2 * rect.midX - dash.x1
                    let mirroredEnd = 2 * rect.midX - dash.x0
                    // A dash touching the axis is one stroke, not two abutting ones.
                    let touchesAxis = dash.x1 >= rect.midX
                    path.move(to: CGPoint(x: dash.x0, y: y))
                    path.addLine(to: CGPoint(x: touchesAxis ? mirroredEnd : dash.x1, y: y))
                    if !touchesAxis {
                        path.move(to: CGPoint(x: mirroredStart, y: y))
                        path.addLine(to: CGPoint(x: mirroredEnd, y: y))
                    }
                }
            }
            runPath = path
        }
        dashedRuns.path = runPath
        dashedRuns.isHidden = runPath == nil

        for outline in [dashedOutline, mirroredOutline, dashedRuns] {
            outline.frame = bounds
            outline.strokeColor = UIColor.HayaseTheme.secondary.cgColor
            outline.lineWidth = lineWidth
            outline.lineCap = .butt
            outline.lineDashPattern = nil
            outline.contentsScale = scale
        }
        let mirroredSplitX = 2 * rect.midX - splitX
        leftBorderMask.frame = CGRect(x: 0, y: 0, width: splitX, height: bounds.height)
        rightBorderMask.frame = CGRect(x: mirroredSplitX, y: 0, width: bounds.width - mirroredSplitX, height: bounds.height)
    }

    private typealias HorizontalSegment = (y: CGFloat, x0: CGFloat, x1: CGFloat)

    private func horizontalSegments(of path: CGPath) -> [HorizontalSegment] {
        var segments: [HorizontalSegment] = []
        var current = CGPoint.zero
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                current = element.points[0]
            case .addLineToPoint:
                let next = element.points[0]
                if abs(next.y - current.y) < 0.01 {
                    segments.append((y: next.y, x0: min(current.x, next.x), x1: max(current.x, next.x)))
                }
                current = next
            case .addQuadCurveToPoint:
                current = element.points[1]
            case .addCurveToPoint:
                current = element.points[2]
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        return segments
    }

    /// The original dashes of one straight edge between `start` (where the corner
    /// arc ends) and `end` (the mirror axis), with the pattern stretched so its last
    /// piece is half a dash long. The piece nearest the corner is left as it was,
    /// so the corners keep their approved phase. Returns nil when the dashed
    /// outline does not have the expected shape.
    private func stretchedDashes(in segments: [HorizontalSegment],
                                 y: CGFloat,
                                 from start: CGFloat,
                                 to end: CGFloat,
                                 dashLength: CGFloat) -> [(x0: CGFloat, x1: CGFloat)]? {
        let tolerance: CGFloat = 0.01
        let dashes = segments
            .filter { abs($0.y - y) < tolerance && $0.x1 - $0.x0 > tolerance && $0.x1 > start + tolerance && $0.x0 < end - tolerance }
            .map { (x0: max($0.x0, start), x1: min($0.x1, end)) }
            .sorted { $0.x0 < $1.x0 }
        guard let first = dashes.first else { return nil }

        var boundaries: [CGFloat] = []
        for dash in dashes {
            if dash.x0 > start + tolerance { boundaries.append(dash.x0) }
            if dash.x1 < end - tolerance { boundaries.append(dash.x1) }
        }
        guard boundaries.count >= 2, let last = boundaries.last else { return nil }

        let anchor = boundaries.count >= 3 ? boundaries[0] : start
        let factor = (end - dashLength / 2 - anchor) / (last - anchor)
        guard factor > 0 else { return nil }

        var result: [(x0: CGFloat, x1: CGFloat)] = []
        var lower = start
        var isDash = first.x0 <= start + tolerance
        for boundary in boundaries.map({ anchor + ($0 - anchor) * factor }) + [end] {
            if isDash { result.append((x0: lower, x1: boundary)) }
            lower = boundary
            isDash.toggle()
        }
        return result
    }

    private func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = (rect.minX * scale).rounded() / scale
        let minY = (rect.minY * scale).rounded() / scale
        let maxX = (rect.maxX * scale).rounded() / scale
        let maxY = (rect.maxY * scale).rounded() / scale
        return CGRect(x: minX,
                      y: minY,
                      width: max(0, maxX - minX),
                      height: max(0, maxY - minY))
    }

    private func updateSpoilerRendering() {
        guard isSpoilerChip else {
            titleLabel?.alpha = 1
            blurredTitleView.isHidden = true
            blurredTitleView.layer.removeAnimation(forKey: "spoilerFilter")
            lastRevealed = nil
            return
        }
        // Tailwind select = hover, focus-visible, active. Blur only the text,
        // never the button's background or dashed border.
        let revealed = isHighlighted || isFocused || isPointerOverTitle
        let shouldAnimate = lastRevealed != nil && lastRevealed != revealed
            && window != nil && !UIAccessibility.isReduceMotionEnabled
        titleLabel?.alpha = 0
        blurredTitleView.isHidden = false
        renderBlurredTitleIfNeeded(animated: shouldAnimate)
        guard let clear = spoilerFrames[0], let blurred = spoilerFrames[12] else { return }
        lastRevealed = revealed
        blurredTitleView.image = revealed ? clear : blurred
        guard shouldAnimate, spoilerFrames.count == 13 else { return }

        // transition-[filter]: 150ms, Tailwind's cubic-bezier(0.4,0,0.2,1).
        // Cached Gaussian samples animate the filter itself, not two cross-fading texts.
        let indices = revealed ? Array((0...12).reversed()) : Array(0...12)
        let frames = indices.compactMap { spoilerFrames[$0] }
        var values: [Any] = frames.compactMap { $0.cgImage }
        if let current = blurredTitleView.layer.presentation()?.contents, !values.isEmpty {
            values[0] = current
        }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = values
        animation.keyTimes = (0..<values.count).map { NSNumber(value: Double($0) / Double(values.count - 1)) }
        animation.calculationMode = .discrete
        animation.duration = 0.15
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        blurredTitleView.layer.add(animation, forKey: "spoilerFilter")
    }

    private func renderBlurredTitleIfNeeded(animated: Bool) {
        guard let text = title(for: .normal), !text.isEmpty, bounds.height > 0 else { return }
        let font = titleLabel?.font ?? .systemFont(ofSize: 14)
        let color = currentTitleColor
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let size = text.size(withAttributes: [.font: font])
        let targetSize = CGSize(width: ceil(size.width) + 36, height: ceil(size.height) + 36)
        let key = "\(text)|\(font.fontName)|\(font.pointSize)|\(scale)|\(color.description)"
        if key != blurredTitleCacheKey {
            blurredTitleCacheKey = key
            spoilerFrames.removeAll()
        }
        // Render just the endpoints on initial layout. Intermediate radii are
        // generated once, only when this particular tag is interacted with.
        let steps = animated ? Array(0...12) : [0, 12]
        guard steps.contains(where: { spoilerFrames[$0] == nil }) else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let textImage = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            text.draw(at: CGPoint(x: (targetSize.width - size.width) / 2,
                                 y: (targetSize.height - size.height) / 2),
                      withAttributes: [.font: font, .foregroundColor: color])
        }
        guard let cgImage = textImage.cgImage else { return }
        let input = CIImage(cgImage: cgImage)
        for step in steps where spoilerFrames[step] == nil {
            if step == 0 { spoilerFrames[step] = textImage; continue }
            let output = input.applyingFilter("CIGaussianBlur",
                parameters: [kCIInputRadiusKey: CGFloat(step) / 2 * scale])
            guard let rendered = Self.blurContext.createCGImage(output, from: input.extent) else {
                spoilerFrames.removeAll()
                blurredTitleView.image = nil
                return
            }
            spoilerFrames[step] = UIImage(cgImage: rendered, scale: scale, orientation: .up)
        }
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
    private enum ActionLayoutMode {
        case regular
        case compactNarrow
        case compactWide
    }
    private var appliedActionLayoutMode: ActionLayoutMode?
    private var appliedPlayComboWidth: CGFloat = -1

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
        b.setImage(UIImage.hayaseIcon("pencil-line", pointSize: 16), for: .normal)
        b.tintColor = .black
        b.backgroundColor = UIColor(white: 0.75, alpha: 1)
        b.layer.cornerRadius = 6
        b.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        b.layer.masksToBounds = true
        return b
    }()

    private let favoriteButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage.hayaseIcon("heart", pointSize: 16), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor.HayaseTheme.secondary
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        return b
    }()

    private let bookmarkButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage.hayaseIcon("bookmark", pointSize: 16), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor.HayaseTheme.secondary
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        return b
    }()

    private let shareButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage.hayaseIcon("share-2", pointSize: 16), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor.HayaseTheme.secondary
        b.layer.cornerRadius = 6
        b.layer.masksToBounds = true
        return b
    }()

    private let trailerButton: UIButton = {
        let b = UIButton(type: .custom)
        let lucideId: String
        if #available(iOS 16.0, *) {
            lucideId = "clapperboard"
        } else {
            lucideId = "film"
        }
        b.setImage(UIImage.hayaseIcon(lucideId, pointSize: 16), for: .normal)
        b.tintColor = .white
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
    private var coverScaleAnimator: UIViewPropertyAnimator?
    private var coverOverlayAnimator: UIViewPropertyAnimator?
    private var bannerHidden = false
    private var hasTrailer = false
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
        let coverPress = UILongPressGestureRecognizer(target: self, action: #selector(coverPressChanged(_:)))
        coverPress.minimumPressDuration = 0
        coverPress.cancelsTouchesInView = false
        coverPress.delegate = self
        coverButton.addGestureRecognizer(coverPress)
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
        lastAppliedSizeClass = traitCollection.horizontalSizeClass
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

        if isRegular {
            anilistButton.isHidden = false
            malButton.isHidden = (malId == nil)
            updateFollowerProfileSpacing(isRegular: true)
            headerFollowerStack.isHidden = headerFollowerStack.arrangedSubviews.isEmpty
        } else {
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
        guard width > 1 else { return }
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
        let isRegular = traitCollection.horizontalSizeClass == .regular
        let measuredWidth = measuredContentWidth()
        let effectiveWidth = isRegular ? min(measuredWidth, 1600) : measuredWidth
        let hPad = interfaceHorizontalPadding(for: measuredWidth)
        let contentWidth = max(0, effectiveWidth - 2 * hPad)
        let isNarrow = contentWidth < 380
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
        anilistButton.isHidden = !isRegular
        malButton.isHidden = !isRegular || malId == nil
        headerFollowerStack.isHidden = !isRegular || headerFollowerStack.arrangedSubviews.isEmpty
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
        guard shouldHide != bannerHidden else { return }
        bannerHidden = shouldHide
        let targetAlpha: CGFloat = shouldHide ? 0.05 : 1.0
        postSidebarBackdrop(scrollOffset: scrollOffset, alpha: targetAlpha)
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
        shareButton.setImage(UIImage.hayaseIcon("check", pointSize: 16), for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.shareButton.setImage(UIImage.hayaseIcon("share-2", pointSize: 16), for: .normal)
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
        onOpenCover?(displayedCoverURL, coverImageView.image)
    }

    @objc private func coverPressChanged(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            setCoverSelected(true, animated: true)
        case .ended, .cancelled, .failed:
            setCoverSelected(false, animated: true)
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    private func setCoverSelected(_ selected: Bool, animated: Bool) {
        stopCoverAnimator(coverScaleAnimator)
        stopCoverAnimator(coverOverlayAnimator)

        let applyScale: () -> Void = { [weak self] in
            guard let self else { return }
            self.coverImageView.transform = selected
                ? CGAffineTransform(scaleX: 1.02, y: 1.02)
                : .identity
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

        // transition-transform duration-200: Tailwind's default cubic-bezier(0.4, 0, 0.2, 1).
        let scaleAnimator = UIViewPropertyAnimator(
            duration: 0.2,
            controlPoint1: CGPoint(x: 0.4, y: 0),
            controlPoint2: CGPoint(x: 0.2, y: 1),
            animations: applyScale
        )
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
        favoriteButton.setImage(isFavorite ? UIImage.hayaseFilledIcon("heart", pointSize: 16) : UIImage.hayaseIcon("heart", pointSize: 16), for: .normal)
        favoriteButton.tintColor = isFavorite ? storedAccentColor : .white

        bookmarkButton.setImage(isOnList ? UIImage.hayaseFilledIcon("bookmark", pointSize: 16) : UIImage.hayaseIcon("bookmark", pointSize: 16), for: .normal)
        bookmarkButton.tintColor = isOnList ? storedAccentColor : .white
    }

    func updatePlayButtonTitle(listStatus: String?) {
        updateScoreSpoiler(listStatus: listStatus)
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

        updateScoreSpoiler(listStatus: item.mediaListEntry?.status)
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

    func refreshDisplayPreferences(for item: AnimeItem) {
        titleLabel.text = AniListUtil.title(for: item)
        romajiLabel.text = AniListUtil.alternateTitle(for: item)
        romajiLabel.isHidden = romajiLabel.text == nil
        setGenres(item.genres.map { String($0) }, tags: item.tags)
        updateScoreSpoiler(listStatus: item.mediaListEntry?.status)
    }

    func updateBanner(from urlString: String) {
        displayedBannerURL = urlString
        postSidebarBackdrop(urlString: urlString,
                            scrollOffset: 0,
                            alpha: bannerHidden ? 0.05 : 1.0)
    }

    // MARK: - Badges

    private var scoreBadge: BadgeButton?
    private var displayedScore: Float?

    private func updateScoreSpoiler(listStatus: String?) {
        guard let badge = scoreBadge, let score = displayedScore else { return }
        let hidden = Settings.hideSpoilers && (listStatus == "CURRENT" || listStatus == "PLANNING")
        badge.setTitle(hidden ? "50%" : String(format: "%.0f%%", score), for: .normal)
        let value = hidden ? 100 : Int(score)
        badge.normalBgColor = value >= 75 ? UIColor(red: 21/255, green: 128/255, blue: 61/255, alpha: 1)
            : value >= 65 ? UIColor(red: 251/255, green: 146/255, blue: 60/255, alpha: 1)
            : UIColor(red: 248/255, green: 113/255, blue: 113/255, alpha: 1)
        badge.backgroundColor = badge.normalBgColor
        badge.highlightedBgColor = value >= 75 ? UIColor(red: 22/255, green: 101/255, blue: 52/255, alpha: 1)
            : value >= 65 ? UIColor(red: 249/255, green: 115/255, blue: 22/255, alpha: 1)
            : UIColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 1)
        badge.setSpoiler(hidden)
    }

    private func rebuildBadges(score: Float?, status: String?, episodes: Int?,
                                nextEp: Int?, format: String?, season: String?,
                                duration: Int? = nil, progress: Int? = nil,
                                accent: UIColor = .white,
                                contrastColor: UIColor = UIColor(white: 0.07, alpha: 1)) {
        badgesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        scoreBadge = nil
        displayedScore = score

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
            let badge = makeBadge(text: String(format: "%.0f%%", sc),
                                                      accent: scoreBG,
                                                      contrast: contrastColor,
                                                      filterType: "score",
                                                      filterValue: "SCORE_DESC")
            scoreBadge = badge as? BadgeButton
            badgesStack.addArrangedSubview(badge)
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
        let showHentai = Settings.showHentai
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
    private var renderedDisplayPreferences: Settings.DisplayPreferences?

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
    private var animeBackdropCoverTransitionID = 0
    private var pendingAnimeBannerRevealWorkItem: DispatchWorkItem?
    private let animeBannerRevealDelay: DispatchTimeInterval = .milliseconds(120)
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

    var threads: [AniListThread] = []
    var themes: [AnimeThemesTheme] = []
    var recommendations: [AnimeItem] = []
    var followingEntriesByEpisode: [Int: [AniListUserSummary]] = [:]
    var threadTotalCount: Int = 0
    var activeThemeVideoURL: String?
    var recommendationsLoading = false
    var threadsLoading = false
    var themesLoading = false
    var animePageRequestID = UUID()
    var animePageErrorDescription: String?
    var hasCompletedInitialAnimeLayout = false
    var pendingAnimePagePayloadReload = false
    var pendingAnimePagePayloadReloadIncludesHeader = false
    private var hasStartedInitialAnimeLoads = false

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
        animeBackdropCoverView.layer.removeAllAnimations()

        if hidden {
            animeBackdropView.applyAlpha(1.0, animated: false)
            UIView.animate(withDuration: 0.3,
                           delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: {
                self.animeBackdropCoverView.alpha = 1
            }, completion: { [weak self] _ in
                guard let self, self.animeBackdropCoverTransitionID == transitionID else { return }
                self.animeBackdropView.applyAlpha(0.05, animated: false)
            })
        } else {
            animeBackdropView.applyAlpha(1.0, animated: false)
            UIView.animate(withDuration: 0.3,
                           delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.animeBackdropCoverView.alpha = 0
            }
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

        let backdropView = HayaseStripedBackdropView()
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

        let closeButton = HayaseCloseButton()
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
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
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

        present(editorVC, animated: false)
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
