//
//  AnimeCollectionViewCell.swift
//  TheAnimeTool
//

import UIKit

// MARK: - Image Cache

private enum ImageCache {
    static let shared = NSCache<NSString, UIImage>()
}

// MARK: - Gradient Overlay

private final class GradientOverlayView: UIView {
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.colors = [UIColor.clear.cgColor,
                           UIColor.black.withAlphaComponent(0.85).cgColor]
        gradient.locations = [0, 1]
        layer.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

// MARK: - AnimeCollectionViewCell

class AnimeCollectionViewCell: UICollectionViewCell {
    static let reuseID = "AnimeCell"

    // MARK: Views

    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor.systemGray5
        return iv
    }()

    private let gradientOverlay = GradientOverlayView()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.textColor = .white
        l.numberOfLines = 2
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.8
        return l
    }()

    private let scoreBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.backgroundColor = UIColor.systemIndigo
        l.layer.cornerRadius = 9
        l.clipsToBounds = true
        return l
    }()

    // MARK: State

    private var currentURLString: String?
    private var imageTask: URLSessionDataTask?

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: Layout

    private func setup() {
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.masksToBounds = false

        [coverImageView, gradientOverlay, titleLabel, scoreBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            // Cover fills entire cell
            coverImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            coverImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Gradient on bottom half
            gradientOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gradientOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            gradientOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            gradientOverlay.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.55),

            // Title at bottom
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            // Score badge top-right
            scoreBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            scoreBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            scoreBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            scoreBadge.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 12).cgPath
    }

    // MARK: Configuration

    func configure(with anime: Animes) {
        titleLabel.text = anime.animeTitleEnglish ?? anime.animeTitleJapanese ?? "Unknown"

        let score = anime.animeScore?.floatValue ?? 0
        if score > 0 {
            scoreBadge.text = String(format: " %.0f%% ", score)
            scoreBadge.isHidden = false
        } else {
            scoreBadge.isHidden = true
        }

        let urlString = anime.animeImgL ?? anime.animeImgM ?? ""
        currentURLString = urlString
        coverImageView.image = nil
        imageTask?.cancel()

        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }

        if let cached = ImageCache.shared.object(forKey: urlString as NSString) {
            coverImageView.image = cached
            return
        }

        let captured = urlString
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            ImageCache.shared.setObject(image, forKey: captured as NSString)
            DispatchQueue.main.async {
                guard self?.currentURLString == captured else { return }
                UIView.transition(with: self?.coverImageView ?? UIImageView(),
                                  duration: 0.3,
                                  options: .transitionCrossDissolve,
                                  animations: { self?.coverImageView.image = image })
            }
        }
        imageTask?.resume()
    }

    func configure(with item: AnimeItem) {
        titleLabel.text = item.titleEnglish ?? item.titleRomaji ?? "Unknown"

        let score = item.score ?? 0
        if score > 0 {
            scoreBadge.text = String(format: " %.0f%% ", score)
            scoreBadge.isHidden = false
        } else {
            scoreBadge.isHidden = true
        }

        let urlString = item.coverURL ?? ""
        currentURLString = urlString
        coverImageView.image = nil
        imageTask?.cancel()

        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }

        if let cached = ImageCache.shared.object(forKey: urlString as NSString) {
            coverImageView.image = cached
            return
        }

        let captured = urlString
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            ImageCache.shared.setObject(image, forKey: captured as NSString)
            DispatchQueue.main.async {
                guard self?.currentURLString == captured else { return }
                UIView.transition(with: self?.coverImageView ?? UIImageView(),
                                  duration: 0.3,
                                  options: .transitionCrossDissolve,
                                  animations: { self?.coverImageView.image = image })
            }
        }
        imageTask?.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentURLString = nil
        coverImageView.image = nil
        scoreBadge.isHidden = true
    }
}
