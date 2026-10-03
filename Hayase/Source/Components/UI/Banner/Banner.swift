//
//  Banner.swift
//  Hayase
//
//  Mirrors: interface components/ui/banner/banner.svelte
//
//      <div class='w-full h-[70vh] md:h-[80vh] relative flex flex-col group/banner'>
//        {#if $query.fetching} <SkeletonBanner />
//        {#if $query.error}    "Ooops!" …
//        {#if $query.data}     <FullBanner mediaList=… />
//

import UIKit

/// What the banner's query has to show.
enum BannerState {
    case fetching
    case failed(String)
    case loaded([AnimeItem])
}

enum Banner {
    /// `h-[70vh] md:h-[80vh]`, `vh` being the height of the window the page is in.
    static func height(viewportWidth: CGFloat, viewHeight: CGFloat) -> CGFloat {
        viewHeight * (viewportWidth >= 768 ? 0.80 : 0.70)
    }

    static func register(in collectionView: UICollectionView) {
        collectionView.register(FullBannerCell.self, forCellWithReuseIdentifier: FullBannerCell.reuseID)
        collectionView.register(SkeletonBannerCell.self, forCellWithReuseIdentifier: SkeletonBannerCell.reuseID)
        collectionView.register(BannerErrorCell.self, forCellWithReuseIdentifier: BannerErrorCell.reuseID)
    }

    /// The banner takes the whole width and `height` points, with nothing around it.
    static func layoutSection(height: CGFloat) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(
            layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0)))
        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(height)),
            subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .zero
        return section
    }

    /// The cell for the state. A loaded banner is a `FullBannerCell`, which the caller then wires up.
    static func cell(for state: BannerState,
                     in collectionView: UICollectionView,
                     at indexPath: IndexPath) -> UICollectionViewCell {
        switch state {
        case .fetching:
            return collectionView.dequeueReusableCell(withReuseIdentifier: SkeletonBannerCell.reuseID, for: indexPath)
        case .failed(let message):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BannerErrorCell.reuseID, for: indexPath)
            (cell as? BannerErrorCell)?.configure(message: message)
            return cell
        case .loaded:
            return collectionView.dequeueReusableCell(withReuseIdentifier: FullBannerCell.reuseID, for: indexPath)
        }
    }
}

// MARK: - BannerErrorCell

/// `p-5 flex items-center justify-center w-full h-72`, at the top of the banner.
final class BannerErrorCell: UICollectionViewCell {
    static let reuseID = "BannerErrorCell"
    /// h-72
    static let height: CGFloat = 288

    private let message = QueryMessageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        message.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(message)
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.height / 2),
            message.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -40),   // p-5
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(message text: String) {
        message.configure(lines: ["Looks like something went wrong!", text])
    }
}
