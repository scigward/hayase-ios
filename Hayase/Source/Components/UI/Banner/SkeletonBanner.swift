//
//  SkeletonBanner.swift
//  Hayase
//
//  Mirrors: interface components/ui/banner/skeleton-banner.svelte
//
//  `pl-5 pb-5 justify-end flex flex-col h-full`: placeholder bars at the bottom left of the
//  banner, each `bg-primary/5 animate-pulse rounded` and as wide as its class says, even where
//  that is wider than the screen.
//

import UIKit

final class SkeletonBannerCell: UICollectionViewCell {
    static let reuseID = "SkeletonBannerCell"

    private var pulseViews: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        // h-6 w-[500px] mb-1           the title
        // my-5 h-1.5 w-[250px]         a spacer
        // h-2.5 mb-2, w-[450px], w-[350px], w-[300px], w-[250px]   the description
        // my-3 h-1.5 w-[150px]         a spacer
        // mb-4 h-6 w-[160px]           the button
        let bars: [(height: CGFloat, width: CGFloat, spacingAfter: CGFloat)] = [
            (24, 500, 24),   // mb-1 (4) and the top margin of the spacer, my-5 (20)
            (6, 250, 20),    // the bottom margin of the spacer, my-5 (20)
            (10, 450, 8),    // mb-2
            (10, 350, 8),
            (10, 300, 8),
            (10, 250, 20),   // mb-2 (8) and the top margin of the spacer, my-3 (12)
            (6, 150, 12),    // the bottom margin of the spacer, my-3 (12)
            (24, 160, 0),
        ]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        for bar in bars {
            let barView = HayaseSkeleton.makeBlock(cornerRadius: 4)   // rounded
            stack.addArrangedSubview(barView)
            NSLayoutConstraint.activate([
                barView.heightAnchor.constraint(equalToConstant: bar.height),
                barView.widthAnchor.constraint(equalToConstant: bar.width),
            ])
            stack.setCustomSpacing(bar.spacingAfter, after: barView)
            pulseViews.append(barView)
        }

        // pl-5 pb-5, and under the button its mb-4 and the empty `mb-3` div that ends the column
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -(20 + 12 + 16)),
        ])

        startPulse()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func startPulse() {
        pulseViews.forEach { HayaseSkeleton.startPulse(on: $0) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        startPulse()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        startPulse()
    }
}
