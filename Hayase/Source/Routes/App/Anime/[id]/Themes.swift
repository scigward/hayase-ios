//
//  Themes.swift
//  Hayase
//

import UIKit
import WebKit

// MARK: - AnimeThemeEntry

struct AnimeThemeEntry {
    let version: Int
    let episodes: String
    let videoURL: String?
}

// MARK: - AnimeTheme

struct AnimeTheme {
    let type: String
    let songTitle: String
    let artists: String
    let entries: [AnimeThemeEntry]

    init?(dict: [String: Any]) {
        guard let slug = dict["slug"] as? String else { return nil }
        self.type = slug.uppercased()
        let song = dict["song"] as? [String: Any]
        self.songTitle = song?["title"] as? String ?? "Unknown"
        let artistArr = song?["artists"] as? [[String: Any]] ?? []
        self.artists = artistArr.compactMap { $0["name"] as? String }.joined(separator: ", ")
        let rawEntries = dict["animethemeentries"] as? [[String: Any]] ?? []
        self.entries = rawEntries.compactMap { e -> AnimeThemeEntry? in
            let ver = e["version"] as? Int ?? 1
            let eps = e["episodes"] as? String ?? ""
            let videos = e["videos"] as? [[String: Any]] ?? []
            let link = videos.last?["link"] as? String
            return AnimeThemeEntry(version: ver, episodes: eps, videoURL: link)
        }
    }
}

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
        closeBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
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
