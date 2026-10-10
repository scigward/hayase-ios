//
//  Skeleton.swift
//  Hayase
//
//  Created by scigward.
//  Mirrors: interface bg-primary/5 animate-pulse skeleton blocks.
//

import UIKit

enum HayaseSkeleton {
    static let animationKey = "hayase-skeleton-pulse"
    static let color = UIColor.HayaseTheme.primary.withAlphaComponent(0.05)

    static func makeBlock(cornerRadius: CGFloat = 4) -> UIView {
        let view = UIView()
        view.backgroundColor = color
        view.layer.cornerRadius = cornerRadius
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        startPulse(on: view)
        return view
    }

    static func startPulse(on view: UIView) {
        view.layer.removeAnimation(forKey: animationKey)
        view.layer.opacity = 1

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.5
        pulse.duration = 1 // Tailwind pulse's complete forward/reverse cycle is 2s.
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.6, 1)   // cubic-bezier(0.4, 0, 0.6, 1)
        view.layer.add(pulse, forKey: animationKey)
    }

    static func stopPulse(on view: UIView) {
        view.layer.removeAnimation(forKey: animationKey)
        view.layer.opacity = 1
    }
}

/// skeleton.svelte: a `w-[9.5rem]` item in `p-4`, `aspect-ratio: 152/290`, with a cover and two bars.
/// Its bars pulse unless the card says `animate={false}`, which QueryCard does until its query has
/// started. Like every card, it runs `load-in` when it mounts.
final class SkeletonCardCell: UICollectionViewCell, InterfaceMountAnimating {
    static let reuseID = "SkeletonCardCell"

    /// `p-4` around the 290pt that the aspect ratio makes of a 152pt wide item: one point less
    /// than a card, which is 323pt.
    static let height: CGFloat = 322
    /// `aspect-ratio: 152/290` of `.item`: what its load-in turns about the middle of
    private static let itemHeight: CGFloat = 290

    private let coverPlaceholder: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.HayaseTheme.background
        view.layer.cornerRadius = 4
        view.clipsToBounds = true
        return view
    }()

    private let titlePlaceholder: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.HayaseTheme.background
        view.layer.cornerRadius = 4
        view.clipsToBounds = true
        return view
    }()

    private let metaPlaceholder: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.HayaseTheme.background
        view.layer.cornerRadius = 4
        view.clipsToBounds = true
        return view
    }()

    private let coverPulse = HayaseSkeleton.makeBlock(cornerRadius: 4)
    private let titlePulse = HayaseSkeleton.makeBlock(cornerRadius: 4)
    private let metaPulse = HayaseSkeleton.makeBlock(cornerRadius: 4)
    private lazy var pulseViews = [coverPulse, titlePulse, metaPulse]

    /// `.item`, which carries the mount animation.
    private let itemStack = UIStackView()
    private var animates = true
    /// The position of the card in its row, below zero, which keys its mount in the collection view.
    private var mountKey = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false

        coverPlaceholder.addSubview(coverPulse)
        titlePlaceholder.addSubview(titlePulse)
        metaPlaceholder.addSubview(metaPulse)

        [coverPlaceholder, titlePlaceholder, metaPlaceholder].forEach { itemStack.addArrangedSubview($0) }
        itemStack.addArrangedSubview(UIView())   // what the aspect ratio leaves under the bars
        itemStack.axis = .vertical
        itemStack.alignment = .leading
        itemStack.spacing = 0
        itemStack.setCustomSpacing(16, after: coverPlaceholder)   // mt-4
        itemStack.setCustomSpacing(8, after: titlePlaceholder)    // mt-2
        itemStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(itemStack)

        NSLayoutConstraint.activate([
            itemStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AnimeCollectionViewCell.contentPadding),
            itemStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AnimeCollectionViewCell.contentPadding),
            itemStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -AnimeCollectionViewCell.contentPadding),
            itemStack.widthAnchor.constraint(equalToConstant: AnimeCollectionViewCell.coverWidth),
            itemStack.heightAnchor.constraint(equalToConstant: Self.itemHeight),

            coverPlaceholder.widthAnchor.constraint(equalToConstant: AnimeCollectionViewCell.coverWidth),
            coverPlaceholder.heightAnchor.constraint(equalToConstant: AnimeCollectionViewCell.coverHeight),

            titlePlaceholder.widthAnchor.constraint(equalToConstant: 112),   // w-28
            titlePlaceholder.heightAnchor.constraint(equalToConstant: 8),    // h-2

            metaPlaceholder.widthAnchor.constraint(equalToConstant: 80),     // w-20
            metaPlaceholder.heightAnchor.constraint(equalToConstant: 8),

            coverPulse.topAnchor.constraint(equalTo: coverPlaceholder.topAnchor),
            coverPulse.leadingAnchor.constraint(equalTo: coverPlaceholder.leadingAnchor),
            coverPulse.trailingAnchor.constraint(equalTo: coverPlaceholder.trailingAnchor),
            coverPulse.bottomAnchor.constraint(equalTo: coverPlaceholder.bottomAnchor),

            titlePulse.topAnchor.constraint(equalTo: titlePlaceholder.topAnchor),
            titlePulse.leadingAnchor.constraint(equalTo: titlePlaceholder.leadingAnchor),
            titlePulse.trailingAnchor.constraint(equalTo: titlePlaceholder.trailingAnchor),
            titlePulse.bottomAnchor.constraint(equalTo: titlePlaceholder.bottomAnchor),

            metaPulse.topAnchor.constraint(equalTo: metaPlaceholder.topAnchor),
            metaPulse.leadingAnchor.constraint(equalTo: metaPlaceholder.leadingAnchor),
            metaPulse.trailingAnchor.constraint(equalTo: metaPlaceholder.trailingAnchor),
            metaPulse.bottomAnchor.constraint(equalTo: metaPlaceholder.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `animate`: whether the bars pulse. `index` is the card's place in its row.
    func configure(animated: Bool, index: Int) {
        animates = animated
        mountKey = -(index + 1)
        applyPulse()
        requestInterfaceMountAnimation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        applyPulse()
        requestInterfaceMountAnimation()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        CardLoadIn.cancel(on: itemStack)
        applyPulse()
    }

    private func applyPulse() {
        for view in pulseViews {
            if animates {
                HayaseSkeleton.startPulse(on: view)
            } else {
                HayaseSkeleton.stopPulse(on: view)
            }
        }
    }

    func requestInterfaceMountAnimation() {
        guard window != nil, let collectionView = CardLoadIn.enclosingCollectionView(of: self) else { return }
        collectionView.requestMountAnimation(for: self, mediaID: mountKey)
    }

    func playInterfaceLoadInAnimation(startedAt: CFTimeInterval) {
        CardLoadIn.play(on: itemStack, startedAt: startedAt)
    }
}


/// skeletontrace.svelte: a 16rem item with a 9rem picture and two bars, in `p-4`. Its bars pulse and, like
/// every card, it runs `load-in` when it mounts.
final class SkeletonTraceCardCell: UICollectionViewCell, InterfaceMountAnimating {
    static let reuseID = "SkeletonTraceCardCell"

    private let picturePulse = HayaseSkeleton.makeBlock(cornerRadius: 4)
    private let titlePulse = HayaseSkeleton.makeBlock(cornerRadius: 4)
    private let metaPulse = HayaseSkeleton.makeBlock(cornerRadius: 4)
    private lazy var pulseViews = [picturePulse, titlePulse, metaPulse]

    /// `.item`, which carries the mount animation.
    private let itemStack = UIStackView()
    /// The position of the card in its row, below zero, which keys its mount in the collection view.
    private var mountKey = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        [picturePulse, titlePulse, metaPulse].forEach { itemStack.addArrangedSubview($0) }
        itemStack.axis = .vertical
        itemStack.alignment = .leading
        itemStack.spacing = 0
        itemStack.setCustomSpacing(16, after: picturePulse)   // mt-4
        itemStack.setCustomSpacing(8, after: titlePulse)      // mt-2
        itemStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(itemStack)

        NSLayoutConstraint.activate([
            itemStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AnimeCollectionViewCell.contentPadding),
            itemStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AnimeCollectionViewCell.contentPadding),
            itemStack.widthAnchor.constraint(equalToConstant: AnimeCollectionViewCell.traceOuterWidth - 2 * AnimeCollectionViewCell.contentPadding),

            picturePulse.widthAnchor.constraint(equalTo: itemStack.widthAnchor),
            picturePulse.heightAnchor.constraint(equalToConstant: AnimeCollectionViewCell.traceCoverHeight),
            titlePulse.widthAnchor.constraint(equalToConstant: 112),
            titlePulse.heightAnchor.constraint(equalToConstant: 8),
            metaPulse.widthAnchor.constraint(equalToConstant: 80),
            metaPulse.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `index` is the card's place in its row.
    func configure(index: Int) {
        mountKey = -(index + 1)
        pulseViews.forEach { HayaseSkeleton.startPulse(on: $0) }
        requestInterfaceMountAnimation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        pulseViews.forEach { HayaseSkeleton.startPulse(on: $0) }
        requestInterfaceMountAnimation()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        CardLoadIn.cancel(on: itemStack)
        pulseViews.forEach { HayaseSkeleton.startPulse(on: $0) }
    }

    func requestInterfaceMountAnimation() {
        guard window != nil, let collectionView = CardLoadIn.enclosingCollectionView(of: self) else { return }
        collectionView.requestMountAnimation(for: self, mediaID: mountKey)
    }

    func playInterfaceLoadInAnimation(startedAt: CFTimeInterval) {
        CardLoadIn.play(on: itemStack, startedAt: startedAt)
    }
}
