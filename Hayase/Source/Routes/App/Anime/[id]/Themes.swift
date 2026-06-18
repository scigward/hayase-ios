//
//  Themes.swift
//  Hayase
//

import UIKit
import WebKit

var themeURLKey = "themeURL"

// MARK: - ThemePlayerViewController

final class ThemePlayerViewController: UIViewController {

    private let videoURL: URL
    private var webView: WKWebView!

    init(videoURL: URL) {
        self.videoURL = videoURL
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage.hayaseIcon("x"), for: .normal)
        closeBtn.tintColor = .white
        closeBtn.contentVerticalAlignment = .fill
        closeBtn.contentHorizontalAlignment = .fill
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeBtn.widthAnchor.constraint(equalToConstant: 32),
            closeBtn.heightAnchor.constraint(equalToConstant: 32),
        ])

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(webView, belowSubview: closeBtn)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 52),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

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
        <video controls autoplay playsinline
               src="\(escapedURL)">
          Your browser does not support this video format.
        </video>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://animethemes.moe"))
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

// MARK: - Theme fetching

extension AnimeDetailViewController {

    func fetchThemes() {
        guard let id = animeItem?.id else { return }
        themesLoading = true
        tableView.reloadSections(IndexSet(integer: Section.themes.rawValue), with: .none)

        AnimeThemesService.shared.themes(anilistID: id) { [weak self] response in
            guard let self else { return }
            let parsed = response?.anime?.first?.animethemes ?? []
            DispatchQueue.main.async {
                self.themes = parsed
                self.themesLoading = false
                if self.activeSection == .themes {
                    self.tableView.reloadSections(IndexSet(integer: Section.themes.rawValue), with: .fade)
                }
            }
        }
    }

    func makeThemeCell(for indexPath: IndexPath) -> UITableViewCell {
        if themesLoading || themes.isEmpty {
            return makeEmptyStateCell(
                text: "No themes found.",
                loading: themesLoading)
        }
        let theme = themes[indexPath.row]
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
        typeLabel.text = theme.slug?.uppercased() ?? theme.type?.uppercased() ?? ""
        typeLabel.font = .nunito(ofSize: 12, weight: .bold)
        typeLabel.textColor = UIColor(white: 0.7, alpha: 1)
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(typeLabel)

        let songTitle = NSMutableAttributedString(
            string: theme.song?.title ?? "Unknown",
            attributes: [.font: UIFont.nunito(ofSize: 16, weight: .bold), .foregroundColor: UIColor.white])
        let artistNames = theme.song?.artists?.compactMap { $0.name }.joined(separator: ", ") ?? ""
        if !artistNames.isEmpty {
            songTitle.append(NSAttributedString(
                string: " by ",
                attributes: [.font: UIFont.nunito(ofSize: 12, weight: .medium), .foregroundColor: UIColor(white: 0.5, alpha: 1)]))
            songTitle.append(NSAttributedString(
                string: artistNames,
                attributes: [.font: UIFont.nunito(ofSize: 16, weight: .bold), .foregroundColor: UIColor.white]))
        }
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
            let eps = entry.episodes ?? ""
            epLabel.text = eps.isEmpty ? "" : "Episodes \(eps)"
            epLabel.font = .nunito(ofSize: 12)
            epLabel.textColor = UIColor(white: 0.5, alpha: 1)
            epLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(epLabel)

            let playBtn = UIButton(type: .system)
            playBtn.setImage(UIImage.hayaseFilledIcon("play", pointSize: 9), for: .normal)
            playBtn.tintColor = ExtensionSearchViewController.luminanceContrastColor(for: accentColor)
            playBtn.backgroundColor = accentColor
            playBtn.layer.cornerRadius = 13
            playBtn.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(playBtn)

            let videoLink = entry.videos?.last?.link
            if let urlStr = videoLink {
                playBtn.addTarget(self, action: #selector(themePlayTapped(_:)), for: .touchUpInside)
                objc_setAssociatedObject(playBtn, &themeURLKey, urlStr, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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
        }

        let themeSidePad: CGFloat = traitCollection.horizontalSizeClass == .regular ? 56 : 16

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 4),
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

    @objc private func themePlayTapped(_ sender: UIButton) {
        guard let urlStr = objc_getAssociatedObject(sender, &themeURLKey) as? String,
              let url = URL(string: urlStr) else { return }
        let player = ThemePlayerViewController(videoURL: url)
        present(player, animated: true)
    }
}
