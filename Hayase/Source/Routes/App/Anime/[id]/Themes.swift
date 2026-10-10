//
//  Themes.swift
//  Hayase
//

import UIKit
import WebKit

var themeURLKey = "themeURL"

// MARK: - ThemeInlineVideoView

final class ThemeInlineVideoView: UIView {

    private let webView: WKWebView
    private var currentURL: URL?

    override init(frame: CGRect) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .black
        layer.cornerRadius = 6
        clipsToBounds = true

        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 256),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func configure(videoURL: URL) {
        guard currentURL != videoURL else { return }
        currentURL = videoURL

        let escapedURL = videoURL.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name='viewport' content='width=device-width, initial-scale=1'>
        <style>
          * { margin:0; padding:0; box-sizing:border-box; }
          html, body { background:#000; height:100%; }
          video {
            width:100%; height:100%; object-fit:contain;
            display:block; background:#000;
          }
        </style>
        </head>
        <body>
        <video id="theme-video" controls autoplay playsinline
               src="\(escapedURL)">
          Your browser does not support this video format.
        </video>
        <script>
          const video = document.getElementById('theme-video');
          video.volume = 0.2;
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://animethemes.moe"))
    }
}

// MARK: - Theme fetching

extension AnimeDetailViewController {

    func fetchThemes() {
        guard let id = animeItem?.id else { return }
        themesLoading = true
        reloadSectionsWithoutAnimation([.themes])

        AnimeThemesService.shared.themes(anilistID: id) { [weak self] response in
            guard let self else { return }
            let parsed = response?.anime?.first?.animethemes ?? []
            DispatchQueue.main.async {
                self.themes = parsed
                self.themesLoading = false
                if self.activeSection == .themes {
                    self.reloadSectionsWithoutAnimation([.themes])
                }
            }
        }
    }

    func makeThemeCell(for indexPath: IndexPath) -> UITableViewCell {
        if themesLoading {
            return makeThemesSkeletonCell()
        }

        if themes.isEmpty {
            // `{#if themes?.anime?.[0]?.animethemes?.length}`: with none there is nothing, only the `pt-3`
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            let height = cell.contentView.heightAnchor.constraint(equalToConstant: 12)
            height.priority = UILayoutPriority(999)
            height.isActive = true
            return cell
        }
        guard let theme = themes[safe: indexPath.row] else { return UITableViewCell() }
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none

        let card = UIView()
        card.backgroundColor = hayaseCardBackground
        card.layer.cornerRadius = 6
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(card)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let headerRow = UIView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        let typeLabel = UILabel()
        typeLabel.text = theme.type ?? ""
        typeLabel.font = .nunito(ofSize: 12, weight: .bold)
        typeLabel.textColor = UIColor(white: 0.7, alpha: 1)
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(typeLabel)

        let songTitle = NSMutableAttributedString(
            string: (theme.song?.title ?? "") + " ",
            attributes: [.font: UIFont.nunito(ofSize: 16, weight: .bold), .foregroundColor: UIColor.white])
        let artistNames = theme.song?.artists?.compactMap { $0.name }.joined(separator: ", ") ?? ""
        songTitle.append(NSAttributedString(
            string: "by",
            attributes: [.font: UIFont.nunito(ofSize: 12, weight: .medium), .foregroundColor: UIColor(white: 0.5, alpha: 1)]))
        songTitle.append(NSAttributedString(
            string: " " + artistNames,
            attributes: [.font: UIFont.nunito(ofSize: 16, weight: .bold), .foregroundColor: UIColor.white]))
        let songLabel = UILabel()
        songLabel.attributedText = songTitle
        songLabel.numberOfLines = 1
        songLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(songLabel)

        NSLayoutConstraint.activate([
            headerRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            typeLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            typeLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            typeLabel.widthAnchor.constraint(equalToConstant: 48),
            songLabel.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor),
            songLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            songLabel.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
        ])
        stack.addArrangedSubview(headerRow)

        let accentColor = currentAnimeAccent

        for entry in (theme.animethemeentries ?? []) {
            let row = UIView()
            row.translatesAutoresizingMaskIntoConstraints = false

            let verLabel = UILabel()
            verLabel.text = "v\(entry.version ?? 1)"
            verLabel.font = .nunito(ofSize: 12)
            verLabel.textColor = UIColor(white: 0.5, alpha: 1)
            verLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(verLabel)

            let epLabel = UILabel()
            epLabel.text = "Episodes \(entry.episodes ?? "")"
            epLabel.font = .nunito(ofSize: 12)
            epLabel.textColor = UIColor(white: 0.5, alpha: 1)
            epLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(epLabel)

            // bg-custom select:!bg-custom-600 text-contrast rounded-full
            let playBtn = SelectButton()
            playBtn.setImage(UIImage.hayaseFilledIcon("play", pointSize: 9), for: .normal)
            let contrast = ExtensionSearchViewController.luminanceContrastColor(for: accentColor)
            playBtn.restingTint = contrast
            playBtn.selectedTint = contrast
            playBtn.restingBackground = accentColor
            playBtn.selectedBackground = accentColor.withHSLLightness(0.4)
            playBtn.layer.cornerRadius = 13
            playBtn.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(playBtn)

            let videoLink = entry.videos?.last?.link
            if let urlStr = videoLink {
                playBtn.addTarget(self, action: #selector(themePlayTapped(_:)), for: .touchUpInside)
                objc_setAssociatedObject(playBtn, &themeURLKey, urlStr, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                playBtn.alpha = activeThemeVideoURL == urlStr ? 0.85 : 1.0
            } else {
                playBtn.isHidden = true
            }

            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
                verLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                verLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                verLabel.widthAnchor.constraint(equalToConstant: 48),
                epLabel.leadingAnchor.constraint(equalTo: verLabel.trailingAnchor),
                epLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                playBtn.leadingAnchor.constraint(greaterThanOrEqualTo: epLabel.trailingAnchor, constant: 8),
                playBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                playBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                playBtn.widthAnchor.constraint(equalToConstant: 26),
                playBtn.heightAnchor.constraint(equalToConstant: 26),
            ])
            stack.addArrangedSubview(row)

            if let urlStr = videoLink,
               activeThemeVideoURL == urlStr,
               let url = URL(string: urlStr) {
                let inlineVideo = ThemeInlineVideoView()
                inlineVideo.translatesAutoresizingMaskIntoConstraints = false
                inlineVideo.configure(videoURL: url)
                stack.addArrangedSubview(inlineVideo)
            }
        }

        let themeSidePad = Self.interfacePageSideInset(for: viewportWidth)

        NSLayoutConstraint.activate([
            // `pt-3` over the first card, `gap-2` between the others
            card.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: indexPath.row == 0 ? 12 : 4),
            card.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -4),
            card.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: themeSidePad),
            card.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -themeSidePad),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
        ])
        return cell
    }

    private func makeThemesSkeletonCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)

        for _ in 0..<2 {
            stack.addArrangedSubview(makeThemeSkeletonCard())
        }

        let themeSidePad = Self.interfacePageSideInset(for: viewportWidth)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: themeSidePad),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -themeSidePad),
        ])

        return cell
    }

    private func makeThemeSkeletonCard() -> UIView {
        let card = UIView()
        card.backgroundColor = hayaseCardBackground
        card.layer.cornerRadius = 6
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let typeHeader = HayaseSkeleton.makeBlock(cornerRadius: 4)
        let title = HayaseSkeleton.makeBlock(cornerRadius: 4)
        let artist = HayaseSkeleton.makeBlock(cornerRadius: 4)
        let version = HayaseSkeleton.makeBlock(cornerRadius: 4)
        let episodes = HayaseSkeleton.makeBlock(cornerRadius: 4)

        [typeHeader, title, artist, version, episodes].forEach { card.addSubview($0) }

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 112),

            typeHeader.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            typeHeader.topAnchor.constraint(equalTo: card.topAnchor, constant: 27),
            typeHeader.widthAnchor.constraint(equalToConstant: 16),
            typeHeader.heightAnchor.constraint(equalToConstant: 10),

            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 76),
            title.centerYAnchor.constraint(equalTo: typeHeader.centerYAnchor),
            title.widthAnchor.constraint(equalToConstant: 128),
            title.heightAnchor.constraint(equalToConstant: 10),

            artist.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            artist.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            artist.widthAnchor.constraint(equalToConstant: 80),
            artist.heightAnchor.constraint(equalToConstant: 10),

            version.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            version.topAnchor.constraint(equalTo: card.topAnchor, constant: 76),   // `h-8 items-center` row at 64
            version.widthAnchor.constraint(equalToConstant: 16),
            version.heightAnchor.constraint(equalToConstant: 8),

            episodes.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 76),
            episodes.centerYAnchor.constraint(equalTo: version.centerYAnchor),
            episodes.widthAnchor.constraint(equalToConstant: 80),
            episodes.heightAnchor.constraint(equalToConstant: 8),
        ])

        return card
    }

    @objc private func themePlayTapped(_ sender: UIButton) {
        guard let urlStr = objc_getAssociatedObject(sender, &themeURLKey) as? String else { return }
        activeThemeVideoURL = activeThemeVideoURL == urlStr ? nil : urlStr
        reloadSectionsWithoutAnimation([.themes])
    }
}
