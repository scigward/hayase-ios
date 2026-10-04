//
//  SetupFooter.swift
//  Hayase
//
//  Mirrors: src/routes/setup/Footer.svelte
//
//    <div class='px-6 mt-auto w-full lg:max-w-4xl'>
//      <div class='border-x border-t w-full rounded-t-lg bg-muted p-4 gap-3 flex flex-col'>{checks}</div>
//    </div>
//    <div class='flex flex-row items-center justify-between w-full bg-muted border-t md:border md:rounded-lg border-border py-4 px-8'>
//      <Button variant='secondary' class='w-24' href={PREV[step]}>Prev</Button>
//      {#await settled}
//        <Tooltip.Root>… <Button class='font-semibold !pointer-events-auto cursor-wait' disabled>Waiting for checks...</Button> …
//      {:then _}
//        <Button class='font-semibold w-24' on:click={checkNext}>Next</Button>
//      {/await}
//    </div>
//
//  The two boxes are laid out one under the other by the page, which gives this view the width of its
//  container. The view's own height is the checks box and the bar.
//

import Foundation
import UIKit

final class SetupFooterView: UIView {
    /// `lg:max-w-4xl`
    static let checksMaxWidth: CGFloat = 896

    private let checksBox = UIView()
    private let checksBorder = CAShapeLayer()
    private let bar = UIView()
    private let barTopBorder = UIView()
    private let prevButton = SelectButton()
    private let nextButton = SelectButton()
    private let waitingButton = SelectButton()
    private var rows: [SetupCheckRow] = []

    /// The size class of the window, which the layout is a function of (`md`, `lg`).
    var viewportWidth: CGFloat = 0 {
        didSet { if viewportWidth != oldValue { setNeedsLayout() } }
    }

    private(set) var checks: [SetupCheck] = []
    /// `<slot />`: the page's content to put after the text of a check whose result names a slot.
    var slotProvider: ((String) -> UIView?)?
    var onPrev: (() -> Void)?
    var onNext: (() -> Void)?

    init() {
        super.init(frame: .zero)

        // border-x border-t rounded-t-lg bg-muted: the border is the box's own, without a bottom
        checksBox.backgroundColor = UIColor.HayaseTheme.muted
        checksBox.layer.cornerRadius = 8
        checksBox.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        checksBorder.fillColor = nil
        checksBorder.strokeColor = UIColor.HayaseTheme.border.cgColor
        checksBorder.lineWidth = 1
        checksBox.layer.addSublayer(checksBorder)
        addSubview(checksBox)

        bar.backgroundColor = UIColor.HayaseTheme.muted
        barTopBorder.backgroundColor = UIColor.HayaseTheme.border
        bar.addSubview(barTopBorder)
        addSubview(bar)

        // <Button variant='secondary' class='w-24'>: text-sm font-medium, h-9 px-4
        prevButton.applySecondaryVariant()
        prevButton.setTitle("Prev", for: .normal)
        prevButton.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        prevButton.addAction(UIAction { [weak self] _ in self?.onPrev?() }, for: .touchUpInside)
        bar.addSubview(prevButton)

        // <Button class='font-semibold w-24'>
        nextButton.applyPrimaryVariant()
        nextButton.setTitle("Next", for: .normal)
        nextButton.titleLabel?.font = .nunito(ofSize: 14, weight: .semibold)
        nextButton.addAction(UIAction { [weak self] _ in self?.onNext?() }, for: .touchUpInside)
        bar.addSubview(nextButton)

        // `disabled` with `!pointer-events-auto cursor-wait`: dimmed, but the pointer still selects it
        waitingButton.applyPrimaryVariant()
        waitingButton.setTitle("Waiting for checks...", for: .normal)
        waitingButton.titleLabel?.font = .nunito(ofSize: 14, weight: .semibold)
        waitingButton.dimsWhenDisabled = true
        waitingButton.selectsWhenDisabled = true
        waitingButton.isEnabled = false
        waitingButton.attachTooltip("Wait for all checks to settle")
        bar.addSubview(waitingButton)

        updateButtons()
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: Checks

    /// `{#each checks as { promise, title, pending } (promise)}`, and `$: settled = Promise.allSettled(…)`
    func setChecks(_ newChecks: [SetupCheck]) {
        checks = newChecks
        rows.forEach { $0.removeFromSuperview() }
        rows = newChecks.map { check in
            let row = SetupCheckRow(check: check, slot: slotProvider)
            checksBox.addSubview(row)
            check.onSettle { [weak self, weak row] in
                guard let self, let row, self.rows.contains(where: { $0 === row }) else { return }
                row.update()
                self.updateButtons()
                self.setNeedsLayout()
                self.superview?.setNeedsLayout()
            }
            return row
        }
        updateButtons()
        setNeedsLayout()
        superview?.setNeedsLayout()
    }

    private func updateButtons() {
        let settled = checks.allSatisfy { $0.isSettled }
        nextButton.isHidden = !settled
        waitingButton.isHidden = settled
        setNeedsLayout()
    }

    // MARK: Layout

    private struct Metrics {
        let wrapperWidth: CGFloat
        let rowWidth: CGFloat
        let checksHeight: CGFloat
        let barHeight: CGFloat
    }

    private func metrics(width: CGFloat) -> Metrics {
        // w-full lg:max-w-4xl, px-6, then the 1pt border and p-4 of the box
        let wrapperWidth = viewportWidth >= 1024 ? min(width, Self.checksMaxWidth) : width
        let rowWidth = max(0, wrapperWidth - 48 - 2 - 32)
        let heights = rows.map { $0.height(forWidth: rowWidth) }
        let checksHeight = rows.isEmpty ? 0 : 1 + 16 + heights.reduce(0, +) + 12 * CGFloat(max(0, heights.count - 1)) + 16
        // py-4 around the h-9 buttons, and border-t (below md) or border (md)
        let barHeight: CGFloat = 16 + 36 + 16 + (viewportWidth >= 768 ? 2 : 1)
        return Metrics(wrapperWidth: wrapperWidth, rowWidth: rowWidth, checksHeight: checksHeight, barHeight: barHeight)
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        let m = metrics(width: width)
        return m.checksHeight + m.barHeight
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = metrics(width: bounds.width)
        let medium = viewportWidth >= 768

        checksBox.isHidden = rows.isEmpty
        checksBox.frame = CGRect(x: (bounds.width - m.wrapperWidth) / 2 + 24, y: 0,
                                 width: m.wrapperWidth - 48, height: m.checksHeight)
        // border-x border-t: a path of the left, top and right edges, rounded at the top corners
        let box = checksBox.bounds
        let border = UIBezierPath()
        border.move(to: CGPoint(x: 0.5, y: box.height))
        border.addLine(to: CGPoint(x: 0.5, y: 8))
        border.addArc(withCenter: CGPoint(x: 8, y: 8), radius: 7.5, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: true)
        border.addLine(to: CGPoint(x: box.width - 8, y: 0.5))
        border.addArc(withCenter: CGPoint(x: box.width - 8, y: 8), radius: 7.5, startAngle: 1.5 * .pi, endAngle: 0, clockwise: true)
        border.addLine(to: CGPoint(x: box.width - 0.5, y: box.height))
        checksBorder.path = border.cgPath
        checksBorder.frame = box

        // p-4 inside the 1pt border, gap-3 between the rows
        var y: CGFloat = 1 + 16
        for row in rows {
            let height = row.height(forWidth: m.rowWidth)
            row.frame = CGRect(x: 1 + 16, y: y, width: m.rowWidth, height: height)
            y += height + 12
        }

        // the bar spans the whole width of the container
        bar.frame = CGRect(x: 0, y: m.checksHeight, width: bounds.width, height: m.barHeight)
        bar.layer.cornerRadius = medium ? 8 : 0
        bar.layer.borderWidth = medium ? 1 : 0
        bar.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        barTopBorder.isHidden = medium
        barTopBorder.frame = CGRect(x: 0, y: 0, width: bar.bounds.width, height: 1)

        // py-4 px-8 inside the border (a top one always, the others from md), and the buttons are h-9
        let side: CGFloat = medium ? 1 : 0
        let buttonY: CGFloat = 1 + 16
        prevButton.frame = CGRect(x: side + 32, y: buttonY, width: 96, height: 36)         // w-24
        let nextWidth: CGFloat = 96
        nextButton.frame = CGRect(x: bar.bounds.width - side - 32 - nextWidth, y: buttonY, width: nextWidth, height: 36)
        // px-4 around the text of the button that has no width of its own
        let waitingText = waitingButton.titleLabel?.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 36)).width ?? 0
        let waitingWidth = ceil(waitingText) + 32
        waitingButton.frame = CGRect(x: bar.bounds.width - side - 32 - waitingWidth, y: buttonY, width: waitingWidth, height: 36)
    }
}

// MARK: - SetupCheckRow

//  Mirrors: the `{#each checks}` row of src/routes/setup/Footer.svelte
//
//    <div class='flex items-center leading-none text-sm text-nowrap'>
//      {#await promise}
//        <div class='w-4 h-4 relative animate-spin mr-2.5'>
//          <div class='w-4 h-4 border-2 rounded-[50%] border-border border-b-border' />
//        </div>
//        {title} -&nbsp;<span class='text-muted-foreground text-xs text-wrap'>{pending}</span>
//      {:then { status, text, slot }}
//        <Badge variant={status} class='w-4 h-4 rounded-[50%] p-[3px] justify-center items-center mr-2.5'>…</Badge>
//        {title} -&nbsp;<span class='text-muted-foreground text-xs text-wrap flex'>{text}{#if slot}<slot />{/if}</span>
//      {/await}
//    </div>

final class SetupCheckRow: UIView {
    private static let iconSide: CGFloat = 16
    private static let iconGap: CGFloat = 10      // mr-2.5
    private static let slotGap: CGFloat = 8       // ml-2 of the slot's icon

    let check: SetupCheck
    private let statusView = SetupStatusView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private var slotView: UIView?

    private var slotBuilder: ((String) -> UIView?)?

    init(check: SetupCheck, slot: ((String) -> UIView?)?) {
        self.check = check
        slotBuilder = slot
        super.init(frame: .zero)
        addSubview(statusView)

        // `leading-none text-sm text-nowrap`, with the no-break space after the dash
        titleLabel.numberOfLines = 1
        titleLabel.attributedText = CSSText.string("\(check.title) -\u{00A0}", font: .nunito(ofSize: 14),
                                                   color: UIColor.HayaseTheme.foreground, lineHeight: 14,
                                                   lineBreak: .byClipping)
        addSubview(titleLabel)

        // `text-muted-foreground text-xs text-wrap`
        textLabel.numberOfLines = 0
        addSubview(textLabel)
        isAccessibilityElement = true
        update()
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// The row as the check stands: pending until it has settled.
    func update() {
        let result = check.result
        statusView.apply(status: result?.status)
        let text = result?.text ?? check.pending
        textLabel.attributedText = CSSText.string(text, font: .nunito(ofSize: 12),
                                                  color: UIColor.HayaseTheme.mutedForeground, lineHeight: 16,
                                                  lineBreak: .byWordWrapping)
        slotView?.removeFromSuperview()
        slotView = nil
        if let slot = result?.slot, let view = slotBuilder?(slot) {
            addSubview(view)
            slotView = view
        }
        accessibilityLabel = "\(check.title) - \(text)"
        setNeedsLayout()
    }

    private struct Metrics {
        let titleWidth: CGFloat
        let textWidth: CGFloat
        let textHeight: CGFloat
        let height: CGFloat
    }

    private func metrics(width: CGFloat) -> Metrics {
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let titleWidth = ceil(titleLabel.sizeThatFits(unbounded).width)
        let slotWidth = slotView == nil ? 0 : Self.slotGap + Self.iconSide
        let available = max(0, width - Self.iconSide - Self.iconGap - titleWidth - slotWidth)
        // The span is a flex item: it takes the width of its text, down to what is left, and wraps there.
        let natural = ceil(textLabel.sizeThatFits(unbounded).width)
        let textWidth = min(natural + 0.5, available)
        let textHeight = ceil(textLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
        let slotHeight: CGFloat = slotView == nil ? 0 : Self.iconSide   // size-4, its `border-b` inside it
        let height = max(Self.iconSide, 14, textHeight, slotHeight)
        return Metrics(titleWidth: titleWidth, textWidth: textWidth, textHeight: textHeight, height: height)
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        metrics(width: width).height
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = metrics(width: bounds.width)
        // items-center
        statusView.frame = CGRect(x: 0, y: (bounds.height - Self.iconSide) / 2, width: Self.iconSide, height: Self.iconSide)
        let titleX = Self.iconSide + Self.iconGap
        titleLabel.frame = CGRect(x: titleX, y: (bounds.height - 14) / 2, width: m.titleWidth, height: 14)
        let textX = titleX + m.titleWidth
        textLabel.frame = CGRect(x: textX, y: (bounds.height - m.textHeight) / 2, width: m.textWidth, height: m.textHeight)
        if let slotView {
            slotView.frame = CGRect(x: textX + m.textWidth + Self.slotGap, y: (bounds.height - Self.iconSide) / 2,
                                    width: Self.iconSide, height: Self.iconSide)
        }
    }
}

/// The 16pt mark in front of a check: a ring while it is pending, and the `Badge` of its status once it has settled.
final class SetupStatusView: UIView {
    private let glyph = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(glyph)
        glyph.fillColor = nil
        glyph.lineCap = .round
        glyph.lineJoin = .round
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(status: SetupCheck.Status?) {
        guard let status else {
            // w-4 h-4 border-2 rounded-[50%] border-border border-b-border: all four sides are the one
            // colour, so the ring that `animate-spin` turns looks the same at every angle
            backgroundColor = .clear
            layer.cornerRadius = 8
            layer.borderWidth = 2
            layer.borderColor = UIColor.HayaseTheme.border.cgColor
            layer.shadowOpacity = 0
            glyph.path = nil
            return
        }
        // rounded-[50%] with `border border-transparent … shadow`
        layer.cornerRadius = 8
        layer.borderWidth = 0
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 1.5
        switch status {
        case .success:
            backgroundColor = UIColor(red: 0x21 / 255.0, green: 0xb9 / 255.0, blue: 0x59 / 255.0, alpha: 1)   // #21b959
            // lucide Check `M20 6 9 17l-5-5` with strokeWidth='4px', in the badge's `text-primary-foreground`
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 20, y: 6))
            path.addLine(to: CGPoint(x: 9, y: 17))
            path.addLine(to: CGPoint(x: 4, y: 12))
            showLucide(path, color: UIColor.HayaseTheme.primaryForeground)
        case .warning:
            backgroundColor = UIColor(red: 0xea / 255.0, green: 0xb3 / 255.0, blue: 0x08 / 255.0, alpha: 1)   // #eab308
            // the 2x7 exclamation mark, drawn in black: `M1 6V3.5` and the dot `M1.00098 1H1.00848`
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 1, y: 6))
            path.addLine(to: CGPoint(x: 1, y: 3.5))
            path.move(to: CGPoint(x: 1.00098, y: 1))
            path.addLine(to: CGPoint(x: 1.00848, y: 1))
            // centred in the 8pt content box of the badge: (16 - 2) / 2 by (16 - 7) / 2
            show(path, scale: 1, offset: CGPoint(x: 7, y: 4.5), color: .black, width: 1.5)
        case .error:
            backgroundColor = UIColor(red: 0xbf / 255.0, green: 0x2c / 255.0, blue: 0x2c / 255.0, alpha: 1)   // #bf2c2c
            // lucide X `M18 6 6 18` and `m6 6 12 12` with strokeWidth='4px'
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 18, y: 6))
            path.addLine(to: CGPoint(x: 6, y: 18))
            path.move(to: CGPoint(x: 6, y: 6))
            path.addLine(to: CGPoint(x: 18, y: 18))
            showLucide(path, color: UIColor.HayaseTheme.primaryForeground)
        }
    }

    /// A lucide icon (a 24 unit view box, `strokeWidth='4px'`) in the 8pt box inside the badge's border and
    /// `p-[3px]`: the svg is a flex item that gives way to the box, so it is drawn at a third of its size,
    /// with the stroke at a third of 4.
    private func showLucide(_ path: UIBezierPath, color: UIColor) {
        let scale: CGFloat = 8 / 24
        show(path, scale: scale, offset: CGPoint(x: 4, y: 4), color: color, width: 4 * scale)
    }

    private func show(_ path: UIBezierPath, scale: CGFloat, offset: CGPoint, color: UIColor, width: CGFloat) {
        path.apply(CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: offset.x, y: offset.y)))
        glyph.path = path.cgPath
        glyph.strokeColor = color.cgColor
        glyph.lineWidth = width
    }
}

// MARK: - SetupChecks

//  Mirrors: the `Checks` of src/routes/setup/Footer.svelte
//
//    promise: Promise<{ status: 'warning' | 'success' | 'error', text: string, slot?: string }>
//    title: string
//    pending: string

/// A check of the footer, which is pending until it is resolved. Like a promise it settles once:
/// the first result is the one it keeps.
final class SetupCheck {
    enum Status {
        case warning
        case success
        case error
    }

    struct Result {
        let status: Status
        let text: String
        /// The page's own content shown after the text (`slot`).
        var slot: String?

        init(status: Status, text: String, slot: String? = nil) {
            self.status = status
            self.text = text
            self.slot = slot
        }
    }

    let title: String
    let pending: String
    private(set) var result: Result?
    private var observers: [() -> Void] = []

    init(title: String, pending: String) {
        self.title = title
        self.pending = pending
    }

    var isSettled: Bool { result != nil }

    /// `resolve(...)`; callable from any thread. Observers hear of it on the main one.
    func resolve(_ result: Result) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.resolve(result) }
            return
        }
        guard self.result == nil else { return }
        self.result = result
        let observers = self.observers
        self.observers = []
        observers.forEach { $0() }
    }

    /// `promise.then(...)`: runs at once, on the main thread, when the check has settled already.
    func onSettle(_ observer: @escaping () -> Void) {
        if result != nil {
            observer()
        } else {
            observers.append(observer)
        }
    }
}
