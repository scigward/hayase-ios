//
//  Seekbar.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/player/seekbar.svelte: a progress bar of one rounded segment for each
//  chapter, with small gaps between them, which can be pressed, dragged and moved with the arrow keys.
//

import AVKit
import CoreMedia
import UIKit
import UniformTypeIdentifiers

/// A chapter-segmented progress bar matching the Hayase web interface seekbar.svelte.
/// Each chapter forms a separate rounded bar segment with small gaps between them.
/// Replaces UISlider + chapterLayer for a faithful recreation of the web player.
final class SegmentedSeekBar: UIControl, KeyboardEventListener {

    // MARK: - Public State

    /// Current playback progress 0–1.
    var value: CGFloat = 0 {
        didSet { layoutSegmentFills() }
    }
    var buffer: CGFloat = 0 {
        didSet { layoutSegmentFills() }
    }
    private var initialSeekOffset: CGFloat = 0
    var onHover: ((CGFloat?) -> Void)?

    /// `seekBarKey`: the keys of the bar while it is the focused element
    enum Key {
        case rewind
        case forward
        case playPause
    }
    var onKey: ((Key) -> Void)?

    /// `seekBarKey`: the arrows seek and nothing else gets them; Enter plays or pauses
    func keyDown(_ event: KeyboardEvent) {
        switch event.key {
        case KeyboardEvent.Key.arrowLeft, KeyboardEvent.Key.arrowRight:
            event.preventDefault()
            event.stopPropagation()
            onKey?(event.key == KeyboardEvent.Key.arrowLeft ? .rewind : .forward)
        case KeyboardEvent.Key.enter:
            onKey?(.playPause)
        default:
            break
        }
    }
    private var hoverValue: CGFloat = 0

    /// True while the user is touching/dragging the bar.
    private(set) var isSeeking = false

    // MARK: - Segments

    private struct Segment {
        let size: CGFloat   // fraction of total width (0–1)
        let offset: CGFloat // start position fraction (0–1)
    }

    private var segments: [Segment] = [Segment(size: 1.0, offset: 0.0)]

    // MARK: - UI

    /// Each element: (container view, background layer, progress fill layer).
    private var segmentViews: [(container: UIView, bg: CALayer, buffered: CALayer, hover: CALayer, fill: CALayer)] = []

    // MARK: - Constants (matching interface seekbar.svelte)

    /// Bar height when not being touched (h-0.5 = 2px in interface CSS).
    private let normalHeight: CGFloat = 2
    /// Bar height when being touched (h-1 = 4px in interface CSS).
    private let activeHeight: CGFloat = 4
    /// Gap between chapter segments (ml-0.5 = 2px in interface CSS).
    private let segmentGap: CGFloat = 2
    /// Corner radius per segment (rounded-[2px] in interface CSS).
    private let segmentRadius: CGFloat = 2
    /// Real vertical padding on each side (py-4 = 16px in interface CSS).
    /// The touch target IS the padded frame — no invisible hit-test override needed.
    private let verticalPadding: CGFloat = 16
    /// Background color: rgba(217,217,217,0.4) from interface.
    private let bgColor = UIColor(red: 217/255, green: 217/255, blue: 217/255, alpha: 0.4)
    /// Progress fill color: white from interface.
    private var fillColor: UIColor { UIColor.HayaseTheme.primary }

    private var barHeight: CGFloat = 2

    // MARK: - Intrinsic size

    /// Returns the natural height: real padding on each side + the active bar height.
    /// This makes the layout system aware of the full touch-target frame,
    /// matching interface seekbar.svelte's py-4 padded container architecture.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: verticalPadding * 2 + activeHeight)
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        rebuildSegmentViews()
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(pointerMoved(_:))))
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Chapter Updates

    func setChapters(_ chapters: [MPVChapter], duration: Double) {
        guard duration > 0 else {
            segments = [Segment(size: 1.0, offset: 0.0)]
            rebuildSegmentViews()
            return
        }

        let sorted = chapters.sorted { $0.time < $1.time }
        var newSegments: [Segment] = []

        for (i, ch) in sorted.enumerated() {
            let start = ch.time / duration
            let end = i + 1 < sorted.count ? sorted[i + 1].time / duration : 1.0
            let size = CGFloat(max(0, end - start))
            if size > 0.001 {
                newSegments.append(Segment(size: size, offset: CGFloat(start)))
            }
        }

        if newSegments.isEmpty {
            newSegments = [Segment(size: 1.0, offset: 0.0)]
        }

        segments = newSegments
        rebuildSegmentViews()
    }

    // MARK: - Build Segment Views

    private func rebuildSegmentViews() {
        segmentViews.forEach { $0.container.removeFromSuperview() }
        segmentViews = []

        for _ in segments {
            let container = UIView()
            container.clipsToBounds = true
            container.layer.cornerRadius = segmentRadius
            container.isUserInteractionEnabled = false

            let bg = CALayer()
            bg.backgroundColor = bgColor.cgColor
            container.layer.addSublayer(bg)

            let buffered = CALayer()
            buffered.backgroundColor = bgColor.cgColor
            container.layer.addSublayer(buffered)
            let hover = CALayer()
            hover.backgroundColor = bgColor.cgColor
            container.layer.addSublayer(hover)

            let fill = CALayer()
            fill.backgroundColor = fillColor.cgColor
            container.layer.addSublayer(fill)

            addSubview(container)
            segmentViews.append((container, bg, buffered, hover, fill))
        }
        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSegmentFrames()
        layoutSegmentFills()
    }

    private func layoutSegmentFrames() {
        let totalWidth = bounds.width
        // Center the thin visual bar within the real padded frame,
        // just like interface's py-4 + flex items-center.
        let cy = bounds.midY

        for (i, seg) in segments.enumerated() {
            guard i < segmentViews.count else { break }
            let gap = i > 0 ? segmentGap : 0
            let w = max(0, totalWidth * seg.size - gap)
            let seek = isSeeking ? value : hoverValue
            let h = seek > seg.offset && seek < seg.offset + seg.size ? activeHeight : normalHeight
            let (container, bg, _, _, _) = segmentViews[i]
            container.frame = CGRect(x: totalWidth * seg.offset + gap, y: cy - h / 2, width: w, height: h)
            container.layer.cornerRadius = min(segmentRadius, h / 2)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bg.frame = container.bounds
            CATransaction.commit()

        }
    }

    private func layoutSegmentFills() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, seg) in segments.enumerated() {
            guard i < segmentViews.count else { break }
            let (container, _, buffered, hover, fill) = segmentViews[i]
            buffered.frame = CGRect(x: 0, y: 0, width: container.bounds.width * localFill(buffer, offset: seg.offset, size: seg.size), height: container.bounds.height)
            hover.frame = CGRect(x: 0, y: 0, width: container.bounds.width * localFill(hoverValue, offset: seg.offset, size: seg.size), height: container.bounds.height)
            let localProgress = localFill(value, offset: seg.offset, size: seg.size)
            fill.frame = CGRect(x: 0, y: 0, width: container.bounds.width * localProgress, height: container.bounds.height)
        }
        CATransaction.commit()
    }

    /// Maps a global progress fraction to a local fill within a segment.
    private func localFill(_ global: CGFloat, offset: CGFloat, size: CGFloat) -> CGFloat {
        guard size > 0 else { return 0 }
        return min(max((global - offset) / size, 0), 1)
    }

    // MARK: - Touch Handling (UIControl)

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isSeeking = true
        // Interface touch seeking is relative: touching far from playback does
        // not jump immediately; subsequent movement adjusts the current position.
        initialSeekOffset = touch.type == .direct ? fractionForTouch(touch) - value : 0
        value = min(max(fractionForTouch(touch) - initialSeekOffset, 0), 1)
        onHover?(nil)
        animateHeight(activeHeight)
        sendActions(for: .touchDown)
        sendActions(for: .valueChanged)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        value = min(max(fractionForTouch(touch) - initialSeekOffset, 0), 1)
        layoutSegmentFrames()
        sendActions(for: .valueChanged)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let t = touch { value = min(max(fractionForTouch(t) - initialSeekOffset, 0), 1) }
        isSeeking = false
        initialSeekOffset = 0
        animateHeight(normalHeight)
        sendActions(for: .touchUpInside)
    }

    override func cancelTracking(with event: UIEvent?) {
        isSeeking = false
        initialSeekOffset = 0
        animateHeight(normalHeight)
        sendActions(for: .touchCancel)
    }

    private func fractionForTouch(_ touch: UITouch) -> CGFloat {
        let x = touch.location(in: self).x
        return min(max(x / max(bounds.width, 1), 0), 1)
    }

    @objc private func pointerMoved(_ gesture: UIHoverGestureRecognizer) {
        guard !isSeeking else { return }
        let hovering = gesture.state == .began || gesture.state == .changed
        hoverValue = hovering ? min(1, max(0, gesture.location(in: self).x / max(1, bounds.width))) : 0
        layoutSegmentFrames()
        layoutSegmentFills()
        onHover?(hovering ? hoverValue : nil)
    }

    private func animateHeight(_ h: CGFloat) {
        guard barHeight != h else { return }
        barHeight = h
        UIView.animate(withDuration: 0.075) {
            self.layoutSegmentFrames()
            self.layoutSegmentFills()
        }
    }
}

// MARK: - PlayerSeekPreviewView

// seekbar.svelte's pointer preview: text fallback, then a 160px thumbnail.

final class PlayerSeekPreviewView: UIView {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let timeLabel = UILabel()
    private let titleBackground = UIView()
    private let timeBackground = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor.HayaseTheme.foreground
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = UIColor.HayaseTheme.primary.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 7.5
        layer.shadowOffset = CGSize(width: 0, height: 10)
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        for (label, panel) in [(titleLabel, titleBackground), (timeLabel, timeBackground)] {
            label.font = .nunito(ofSize: 14, weight: .regular)
            label.textColor = UIColor.HayaseTheme.background
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingTail
            panel.layer.cornerRadius = 8
            panel.addSubview(label)
            addSubview(panel)
        }
        titleBackground.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        timeBackground.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(title: String, time: String, image: UIImage?) {
        titleLabel.text = title
        timeLabel.text = time
        imageView.image = image
        titleBackground.isHidden = title.isEmpty
        imageView.isHidden = image == nil
        titleBackground.backgroundColor = image == nil ? .clear : UIColor.HayaseTheme.primary
        timeBackground.backgroundColor = titleBackground.backgroundColor
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
    override var intrinsicContentSize: CGSize {
        if let image = imageView.image, image.size.width > 0 {
            return CGSize(width: 162, height: max(40, 160 * image.size.height / image.size.width) + 2)
        }
        return CGSize(width: max(min(96, titleLabel.intrinsicContentSize.width), timeLabel.intrinsicContentSize.width) + 26,
                      height: titleBackground.isHidden ? 32 : 50)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds.insetBy(dx: 1, dy: 1)
        let hasImage = imageView.image != nil
        let titleWidth = min(96, titleLabel.intrinsicContentSize.width)
        let timeWidth = timeLabel.intrinsicContentSize.width
        titleBackground.frame = CGRect(x: (bounds.width - titleWidth - (hasImage ? 16 : 0)) / 2,
                                       y: hasImage ? 1 : 9, width: titleWidth + (hasImage ? 16 : 0), height: hasImage ? 22 : 14)
        timeBackground.frame = CGRect(x: (bounds.width - timeWidth - (hasImage ? 16 : 0)) / 2,
                                      y: hasImage ? bounds.height - 23 : bounds.height - 23,
                                      width: timeWidth + (hasImage ? 16 : 0), height: hasImage ? 22 : 14)
        titleLabel.frame = titleBackground.bounds.insetBy(dx: hasImage ? 8 : 0, dy: hasImage ? 4 : 0)
        timeLabel.frame = timeBackground.bounds.insetBy(dx: hasImage ? 8 : 0, dy: hasImage ? 4 : 0)
    }
}

// MARK: - The player's side of seekbar.svelte (pressing, dragging and the preview of the frame)

extension VideoPlayerViewController {
    @objc func seekBegan() {
        guard wasPausedBeforeScrub == nil else { return }
        wasPausedBeforeScrub = isPaused
        if !isPaused { surface.mpv.pausePlayback() }
        doubleTapSeekRestoreWork?.cancel()
        doubleTapSeekRestoreWork = nil
        isSeeking = true
        hideWork?.cancel()
        updateInterfaceOverlayVisibility(animated: true)
    }

    @objc func seekChanged() {
        let t = Double(seekBar.value) * duration
        if showRemainingTime {
            timeLabel.content = "-\(fmtTime(max(0, duration - t))) / \(fmtTime(duration))"
        } else {
            timeLabel.content = "\(fmtTime(t)) / \(fmtTime(duration))"
        }
        chapterLabel.content = chapterTitle(at: t)
        previewRequest = UUID()
        let request = previewRequest
        thumbnailer.thumbnail(at: t) { [weak self] image in
            guard let self, self.previewRequest == request, self.seekBar.isSeeking else { return }
            self.seekingImage.image = image
            self.seekingImage.contentMode = self.surface.displayLayer.videoGravity == .resizeAspectFill ? .scaleAspectFill : .scaleAspectFit
            self.seekingImage.isHidden = image == nil
        }
        updateInterfaceOverlayVisibility(animated: true)
    }

    @objc func seekEnded() {
        guard let wasPaused = wasPausedBeforeScrub else { return }
        wasPausedBeforeScrub = nil
        previewRequest = UUID()
        seekingImage.isHidden = true
        let seekFraction = Double(seekBar.value)
        let targetTime = seekFraction * duration
        pendingSeekDisplayTime = targetTime
        lastSeekTime = Date()

        surface.mpv.seek(to: targetTime)
        showPlayerAnimation(icon: targetTime > currentTime ? "fast-forward" : "rewind")
        if !wasPaused { surface.mpv.play() }
        updateInterfaceOverlayVisibility(animated: true)
        scheduleHide()

        doubleTapSeekRestoreWork?.cancel()
        let restoreWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.doubleTapSeekRestoreWork = nil
            self.isSeeking = false
            self.pendingSeekDisplayTime = nil
            self.updateTimeUI()
        }
        doubleTapSeekRestoreWork = restoreWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: restoreWork)
    }

    func showSeekPreview(at fraction: CGFloat?) {
        previewRequest = UUID()
        guard let fraction, fraction > 0, duration > 0 else { seekPreview.isHidden = true; return }
        let request = previewRequest
        let time = Double(fraction) * duration
        let title = chapterTitle(at: time)
        seekPreview.configure(title: title, time: fmtTime(time), image: nil)
        seekPreview.isHidden = false
        positionSeekPreview(fraction: fraction)
        thumbnailer.thumbnail(at: time) { [weak self] image in
            guard let self, self.previewRequest == request else { return }
            self.seekPreview.configure(title: title, time: self.fmtTime(time), image: image)
            self.positionSeekPreview(fraction: fraction)
        }
    }

    func positionSeekPreview(fraction: CGFloat) {
        let bar = seekBar.convert(seekBar.bounds, to: overlay)
        let centerX = bar.minX + min(max(70, bar.width * fraction), max(70, bar.width - 70))
        let size = seekPreview.intrinsicContentSize
        seekPreview.frame = CGRect(x: centerX - size.width / 2, y: bar.maxY - 36 - size.height,
                                   width: size.width, height: size.height)
    }

    func renderSeekTargetUI(time: Double) {
        seekBar.value = duration > 0 ? CGFloat(time / duration) : 0
        if showRemainingTime {
            timeLabel.content = "-\(fmtTime(max(0, duration - time))) / \(fmtTime(duration))"
        } else {
            timeLabel.content = "\(fmtTime(time)) / \(fmtTime(duration))"
        }
        chapterLabel.content = chapterTitle(at: time)
    }
}
