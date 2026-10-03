//
//  SetupCheckRow.swift
//  Hayase
//
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
//

import UIKit

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
            // lucide Check `M20 6 9 17l-5-5` with strokeWidth='4px', in the badge's `text-primary-foreground`.
            // The svg keeps its 24pt size, which the 8pt content box of the badge cannot shrink, so it
            // is centred on the badge and spills over its edge.
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 20, y: 6))
            path.addLine(to: CGPoint(x: 9, y: 17))
            path.addLine(to: CGPoint(x: 4, y: 12))
            show(path, offset: CGPoint(x: -4, y: -4), color: UIColor.HayaseTheme.primaryForeground, width: 4)
        case .warning:
            backgroundColor = UIColor(red: 0xea / 255.0, green: 0xb3 / 255.0, blue: 0x08 / 255.0, alpha: 1)   // #eab308
            // the 2x7 exclamation mark, drawn in black: `M1 6V3.5` and the dot `M1.00098 1H1.00848`
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 1, y: 6))
            path.addLine(to: CGPoint(x: 1, y: 3.5))
            path.move(to: CGPoint(x: 1.00098, y: 1))
            path.addLine(to: CGPoint(x: 1.00848, y: 1))
            // centred in the 8pt content box of the badge: (16 - 2) / 2 by (16 - 7) / 2
            show(path, offset: CGPoint(x: 7, y: 4.5), color: .black, width: 1.5)
        case .error:
            backgroundColor = UIColor(red: 0xbf / 255.0, green: 0x2c / 255.0, blue: 0x2c / 255.0, alpha: 1)   // #bf2c2c
            // lucide X `M18 6 6 18` and `m6 6 12 12` with strokeWidth='4px'
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 18, y: 6))
            path.addLine(to: CGPoint(x: 6, y: 18))
            path.move(to: CGPoint(x: 6, y: 6))
            path.addLine(to: CGPoint(x: 18, y: 18))
            show(path, offset: CGPoint(x: -4, y: -4), color: UIColor.HayaseTheme.primaryForeground, width: 4)
        }
    }

    private func show(_ path: UIBezierPath, offset: CGPoint, color: UIColor, width: CGFloat) {
        path.apply(CGAffineTransform(translationX: offset.x, y: offset.y))
        glyph.path = path.cgPath
        glyph.strokeColor = color.cgColor
        glyph.lineWidth = width
    }
}
