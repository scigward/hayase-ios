//
//  SetupProgress.swift
//  Hayase
//
//  Mirrors: src/routes/setup/Progress.svelte
//
//    <div class='px-6 mt-14 w-full lg:max-w-4xl pb-5'>
//      <div class='w-full relative flex justify-around'>
//        <div class='absolute top-[19px] left-0 w-full h-[10px] rounded-[10px] bg-secondary shrink-0 overflow-clip'>
//          <div class='bg-foreground size-full transform-gpu' style:--tw-translate-x='-{STEP_PERCENTAGE[step]}%' />
//        </div>
//        <div class='w-20 flex flex-col items-center z-10 shrink-0'>
//          <Badge class='w-12 h-12 rounded-[50%] flex justify-center' href=…><HardDrive /></Badge>
//          <div class='mt-3 font-bold'>Storage</div>
//
//  The view is the `px-6 … pb-5` box without its `mt-14`, which the page that holds it adds.
//

import UIKit

final class SetupProgressView: UIView {
    /// `mt-14`
    static let topMargin: CGFloat = 56
    /// 48 (the badge) + `mt-3` + 24 (the label's line) + `pb-5`
    static let height: CGFloat = 48 + 12 + 24 + 20

    private static let stepPercentage: [CGFloat] = [85, 50, 15]
    private static let itemWidth: CGFloat = 80   // w-20
    private static let barTop: CGFloat = 19      // top-[19px]
    private static let barHeight: CGFloat = 10

    /// A badge was followed (`href`).
    var onNavigate: ((SetupRoute) -> Void)?

    private let step: Int
    private let track = UIView()
    private let fill = UIView()
    private let items: [Item]

    private struct Item {
        let container = UIView()
        let badge = UIView()
        let icon = UIImageView()
        let label = UILabel()
    }

    init(step: Int) {
        self.step = step
        items = [Item(), Item(), Item()]
        super.init(frame: .zero)

        // absolute top-[19px] left-0 w-full h-[10px] rounded-[10px] bg-secondary overflow-clip
        track.backgroundColor = UIColor.HayaseTheme.secondary
        track.layer.cornerRadius = Self.barHeight / 2   // a radius of 10px on a 10px bar is a pill
        track.clipsToBounds = true
        track.isUserInteractionEnabled = false
        // bg-foreground size-full, moved back by the share of the bar that is not yet filled
        fill.backgroundColor = UIColor.HayaseTheme.foreground
        track.addSubview(fill)
        addSubview(track)

        let titles = ["Storage", "Network", "Extensions"]
        let icons = ["hard-drive", "network", "puzzle"]
        for (index, item) in items.enumerated() {
            // `step > 0 ? 'default' : 'secondary'` and `step > 1 ? …` for the second and the third badge;
            // the first is always `default`
            let reached = index == 0 || step > index - 1
            item.badge.backgroundColor = reached ? UIColor.HayaseTheme.primary : UIColor.HayaseTheme.secondary
            item.badge.layer.cornerRadius = 24    // rounded-[50%]
            if reached {
                // badgeVariants default: shadow
                item.badge.layer.shadowColor = UIColor.black.cgColor
                item.badge.layer.shadowOpacity = 0.1
                item.badge.layer.shadowOffset = CGSize(width: 0, height: 1)
                item.badge.layer.shadowRadius = 1.5
            }
            item.icon.image = UIImage.hayaseIcon(icons[index], pointSize: 24)
            // text-primary-foreground (the first badge), text-background, text-muted-foreground
            item.icon.tintColor = index == 0 ? UIColor.HayaseTheme.primaryForeground
                : (reached ? UIColor.HayaseTheme.background : UIColor.HayaseTheme.mutedForeground)
            item.icon.contentMode = .center
            item.badge.addSubview(item.icon)
            item.container.addSubview(item.badge)

            // `mt-3 font-bold`, in the colour of the item
            let color = reached ? UIColor.HayaseTheme.foreground : UIColor.HayaseTheme.mutedForeground
            item.label.attributedText = CSSText.string(titles[index], font: .nunito(ofSize: 16, weight: .bold),
                                                       color: color, lineHeight: 24, alignment: .center,
                                                       lineBreak: .byClipping)
            item.container.addSubview(item.label)
            addSubview(item.container)

            item.badge.isAccessibilityElement = true
            item.badge.accessibilityLabel = titles[index]
            item.badge.accessibilityTraits = .staticText
            item.label.isAccessibilityElement = false
        }

        // href='/#/setup/storage' on the first badge; href={step > 1 ? '/#/setup/network' : undefined} on the second
        follow(items[0].badge, to: .storage)
        if step > 1 { follow(items[1].badge, to: .network) }
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func follow(_ badge: UIView, to route: SetupRoute) {
        badge.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(badgeTapped(_:))))
        badge.accessibilityTraits = .button
        badge.tag = route == .storage ? 1 : 2
    }

    @objc private func badgeTapped(_ recognizer: UITapGestureRecognizer) {
        guard let tag = recognizer.view?.tag else { return }
        onNavigate?(tag == 1 ? .storage : .network)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // px-6
        let inner = max(0, bounds.width - 48)
        let originX: CGFloat = 24
        track.frame = CGRect(x: originX, y: Self.barTop, width: inner, height: Self.barHeight)
        // transform: translateX(-85%) of the fill's own width
        fill.frame = CGRect(x: -inner * Self.stepPercentage[step] / 100, y: 0, width: inner, height: Self.barHeight)

        // justify-around: the free space is shared out so each item has an equal half either side
        let free = inner - Self.itemWidth * CGFloat(items.count)
        let gap = free / CGFloat(items.count)
        for (index, item) in items.enumerated() {
            let x = originX + gap / 2 + CGFloat(index) * (Self.itemWidth + gap)
            item.container.frame = CGRect(x: x, y: 0, width: Self.itemWidth, height: 48 + 12 + 24)
            item.badge.frame = CGRect(x: (Self.itemWidth - 48) / 2, y: 0, width: 48, height: 48)
            item.icon.frame = item.badge.bounds
            item.label.frame = CGRect(x: 0, y: 48 + 12, width: Self.itemWidth, height: 24)
        }
        // z-10: the items are over the bar
        items.forEach { bringSubviewToFront($0.container) }
    }
}
