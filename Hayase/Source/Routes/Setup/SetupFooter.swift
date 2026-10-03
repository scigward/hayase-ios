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
