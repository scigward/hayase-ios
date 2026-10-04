//
//  Query.swift
//  Hayase
//
//  Mirrors: interface components/ui/cards/query.svelte
//
//  A row of cards for a query: skeletons while it fetches (or, with no animation, before it has
//  started), the error or the empty message when it has nothing to show, and the cards otherwise.
//  The cards move to their new places when the answer changes (`animate:flip`).
//

import UIKit

enum QueryCard {
    /// `Array.from({ length: 20 })`
    static let skeletonCount = 20
    /// `animate:flip={{ duration: 400, easing: quartInOut }}`
    static let flipDuration: TimeInterval = 0.4

    static func register(in collectionView: UICollectionView) {
        collectionView.register(AnimeCollectionViewCell.self,
                                forCellWithReuseIdentifier: AnimeCollectionViewCell.reuseID)
        collectionView.register(SkeletonCardCell.self,
                                forCellWithReuseIdentifier: SkeletonCardCell.reuseID)
        collectionView.register(QueryMessageCell.self,
                                forCellWithReuseIdentifier: QueryMessageCell.reuseID)
    }

    static func itemCount(for section: HomeSectionData) -> Int {
        switch section.contentState {
        case .idle, .paused, .fetching:
            return skeletonCount
        case .empty, .failed:
            return 1
        case .loaded:
            return section.items.count
        }
    }

    /// The height of the row: a card is 323pt, a skeleton 322pt and the message `h-80`.
    static func rowHeight(for state: HomeSectionContentState) -> CGFloat {
        switch state {
        case .idle, .paused, .fetching:
            return SkeletonCardCell.height
        case .empty, .failed:
            return QueryMessageCell.height
        case .loaded:
            return AnimeCollectionViewCell.outerHeight
        }
    }

    /// `flex overflow-x-scroll`: the cards in a row that scrolls sideways, or the message, which is
    /// `w-full`.
    static func layoutSection(for state: HomeSectionContentState) -> NSCollectionLayoutSection {
        let height = rowHeight(for: state)
        let width = AnimeCollectionViewCell.outerWidth
        let item: NSCollectionLayoutItem
        let group: NSCollectionLayoutGroup
        if state.message != nil {
            item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                                            heightDimension: .absolute(height)))
            group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(height)),
                subitems: [item])
        } else {
            item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(width),
                                                            heightDimension: .absolute(height)))
            group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .estimated(width), heightDimension: .absolute(height)),
                subitems: [item])
        }
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        // The cards carry their own `p-4`, and the row's `-mb-5 pb-5` takes nothing from the page.
        section.contentInsets = .zero
        return section
    }

    static func cell(for section: HomeSectionData,
                     in collectionView: UICollectionView,
                     at indexPath: IndexPath,
                     host: UIViewController) -> UICollectionViewCell {
        switch section.contentState {
        case .idle, .paused, .fetching:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: SkeletonCardCell.reuseID, for: indexPath) as? SkeletonCardCell else {
                return UICollectionViewCell()
            }
            cell.layer.zPosition = 10
            // `<SkeletonCard animate={false} />` until the query has started
            var started = true
            if case .idle = section.contentState { started = false }
            if case .paused = section.contentState { started = false }
            cell.configure(animated: started, index: indexPath.item)
            return cell

        case .empty, .failed:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: QueryMessageCell.reuseID, for: indexPath) as? QueryMessageCell else {
                return UICollectionViewCell()
            }
            cell.layer.zPosition = 10
            cell.configure(lines: section.contentState.messageLines)
            return cell

        case .loaded:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: AnimeCollectionViewCell.reuseID, for: indexPath) as? AnimeCollectionViewCell else {
                return UICollectionViewCell()
            }
            cell.layer.zPosition = 10
            if indexPath.item < section.items.count {
                let item = section.items[indexPath.item]
                cell.configure(with: item)
                // `<SmallCard first={i === 0}>`
                Hover.shared.bind(to: cell,
                                  host: host,
                                  mediaProvider: { item },
                                  actions: host.hayasePreviewCardActions(),
                                  alignsToCardStart: indexPath.item == 0)
            }
            return cell
        }
    }

    /// The cards of a row only move when they were on screen and the answer changed.
    static func canFlip(from previous: HomeSectionData, to next: HomeSectionData) -> Bool {
        // `previous` is frequently mid-refetch (contentState == .fetching) while still
        // holding the last-loaded items: PageQuery.resume()/setFetching(previous:) and
        // AniListClient.fetchHomeSectionResult always emit `.fetching` between two
        // `.success` values. Non-empty `previous.items` already proves it was genuinely on screen.
        guard case .loaded = next.contentState,
              !previous.items.isEmpty,
              !next.items.isEmpty else { return false }
        return previous.items.map(\.id) != next.items.map(\.id)
    }

    // MARK: - animate:flip

    /// Where the cards of a row are, by media, before the row is reloaded.
    static func visibleFrames(in collectionView: UICollectionView,
                              section: Int,
                              items: [AnimeItem]) -> [Int: CGRect] {
        var frames: [Int: CGRect] = [:]
        for indexPath in collectionView.indexPathsForVisibleItems where indexPath.section == section {
            guard indexPath.item < items.count else { continue }
            let mediaID = items[indexPath.item].id
            let frame: CGRect?
            if let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
                frame = attributes.frame
            } else {
                frame = collectionView.cellForItem(at: indexPath)?.frame
            }
            if let frame {
                frames[mediaID] = frame
            }
        }
        return frames
    }

    /// Slides the cards that were already there from their old places to their new ones.
    static func animateFlip(in collectionView: UICollectionView,
                            section: Int,
                            items: [AnimeItem],
                            from previousFrames: [Int: CGRect]) {
        guard !previousFrames.isEmpty else { return }
        // quartInOut
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.77, y: 0.0),
                                             controlPoint2: CGPoint(x: 0.175, y: 1.0))
        for indexPath in collectionView.indexPathsForVisibleItems where indexPath.section == section {
            guard indexPath.item < items.count,
                  let cell = collectionView.cellForItem(at: indexPath),
                  let oldFrame = previousFrames[items[indexPath.item].id] else { continue }
            let newFrame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? cell.frame
            cell.transform = CGAffineTransform(translationX: oldFrame.midX - newFrame.midX,
                                               y: oldFrame.midY - newFrame.midY)
            let animator = UIViewPropertyAnimator(duration: flipDuration, timingParameters: timing)
            animator.addAnimations {
                cell.transform = .identity
            }
            animator.startAnimation()
        }
    }
}

// MARK: - QueryMessageView

/// The block of text that query.svelte and banner.svelte show when there is nothing to show:
///
///     <div class='mb-1 font-bold text-4xl text-center'>Ooops!</div>
///     <div class='text-lg text-center text-muted-foreground'>…</div>
final class QueryMessageView: UIView {
    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(lines: [String]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        // text-4xl: 2.25rem on a line of 2.5rem
        let title = Self.makeLabel("Ooops!", font: .nunito(ofSize: 36, weight: .bold),
                                   color: UIColor.HayaseTheme.foreground, lineHeight: 40)
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(4, after: title)   // mb-1
        // text-lg: 1.125rem on a line of 1.75rem
        for line in lines {
            stack.addArrangedSubview(Self.makeLabel(line, font: .nunito(ofSize: 18),
                                                    color: UIColor.HayaseTheme.mutedForeground, lineHeight: 28))
        }
    }

    private static func makeLabel(_ text: String, font: UIFont, color: UIColor, lineHeight: CGFloat) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = CSSText.string(text, font: font, color: color, lineHeight: lineHeight,
                                              alignment: .center, lineBreak: .byWordWrapping)
        return label
    }
}

// MARK: - QueryMessageCell

/// `p-5 flex items-center justify-center w-full h-80 col-span-full`
final class QueryMessageCell: UICollectionViewCell {
    static let reuseID = "QueryMessageCell"
    static let height: CGFloat = 320

    private let message = QueryMessageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        message.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(message)
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -40),   // p-5
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(lines: [String]) {
        message.configure(lines: lines)
    }
}
