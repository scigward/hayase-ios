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

final class SkeletonCardCell: UICollectionViewCell {
    static let reuseID = "SkeletonCardCell"

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

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        coverPlaceholder.addSubview(coverPulse)
        titlePlaceholder.addSubview(titlePulse)
        metaPlaceholder.addSubview(metaPulse)

        let stack = UIStackView(arrangedSubviews: [coverPlaceholder, titlePlaceholder, metaPlaceholder])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.setCustomSpacing(16, after: coverPlaceholder)
        stack.setCustomSpacing(8, after: titlePlaceholder)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AnimeCollectionViewCell.contentPadding),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AnimeCollectionViewCell.contentPadding),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -AnimeCollectionViewCell.contentPadding),
            stack.widthAnchor.constraint(equalToConstant: AnimeCollectionViewCell.coverWidth),

            coverPlaceholder.widthAnchor.constraint(equalToConstant: AnimeCollectionViewCell.coverWidth),
            coverPlaceholder.heightAnchor.constraint(equalToConstant: AnimeCollectionViewCell.coverHeight),

            titlePlaceholder.widthAnchor.constraint(equalToConstant: 112),
            titlePlaceholder.heightAnchor.constraint(equalToConstant: 8),

            metaPlaceholder.widthAnchor.constraint(equalToConstant: 80),
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        restartPulse()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        restartPulse()
    }

    private func restartPulse() {
        pulseViews.forEach { HayaseSkeleton.startPulse(on: $0) }
    }
}


/// skeletontrace.svelte: a 16rem item with a 9rem picture and two bars, in `p-4`.
final class SkeletonTraceCardCell: UICollectionViewCell {
    static let reuseID = "SkeletonTraceCardCell"

    private let picturePulse = HayaseSkeleton.makeBlock(cornerRadius: 4)
    private let titlePulse = HayaseSkeleton.makeBlock(cornerRadius: 4)
    private let metaPulse = HayaseSkeleton.makeBlock(cornerRadius: 4)
    private lazy var pulseViews = [picturePulse, titlePulse, metaPulse]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        let stack = UIStackView(arrangedSubviews: [picturePulse, titlePulse, metaPulse])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.setCustomSpacing(16, after: picturePulse)   // mt-4
        stack.setCustomSpacing(8, after: titlePulse)      // mt-2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AnimeCollectionViewCell.contentPadding),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AnimeCollectionViewCell.contentPadding),
            stack.widthAnchor.constraint(equalToConstant: AnimeCollectionViewCell.traceOuterWidth - 2 * AnimeCollectionViewCell.contentPadding),

            picturePulse.widthAnchor.constraint(equalTo: stack.widthAnchor),
            picturePulse.heightAnchor.constraint(equalToConstant: AnimeCollectionViewCell.traceCoverHeight),
            titlePulse.widthAnchor.constraint(equalToConstant: 112),
            titlePulse.heightAnchor.constraint(equalToConstant: 8),
            metaPulse.widthAnchor.constraint(equalToConstant: 80),
            metaPulse.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        pulseViews.forEach { HayaseSkeleton.startPulse(on: $0) }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pulseViews.forEach { HayaseSkeleton.startPulse(on: $0) }
    }
}
