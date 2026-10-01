//
//  TrailerDialog.swift
//  Hayase
//
//  Mirrors: interface routes/app/anime/[id]/+layout.svelte's trailer `Dialog.Content`
//  (`flex justify-center max-h-[80%] h-full max-w-max`) around
//  `<iframe class='h-full max-w-full aspect-video max-h-full rounded'>`.
//

import UIKit
import WebKit

final class TrailerDialogViewController: SettingsDialogViewController {
    private let webView: WKWebView
    private let webWidth: NSLayoutConstraint
    private let webHeight: NSLayoutConstraint

    /// The page is the iframe's embedder: YouTube answers an embed that arrives without a referrer
    /// (a bare `load` of the embed URL) with "Error 153", so the iframe is hosted in a document
    /// that has an https origin, like the interface's own page.
    init(trailerID: String, title: String) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        webView = view
        webWidth = view.widthAnchor.constraint(equalToConstant: 0)
        webHeight = view.heightAnchor.constraint(equalToConstant: 0)
        super.init(title: "")

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.layer.cornerRadius = 4   // rounded
        webView.layer.masksToBounds = true
        webView.accessibilityLabel = title

        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let html = """
        <!doctype html>
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:transparent}iframe{display:block;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="https://www.youtube-nocookie.com/embed/\(trailerID)?autoplay=1&cc_lang_pref=ja&rel=0" frameborder="0"
          allow="autoplay; fullscreen" allowfullscreen referrerpolicy="strict-origin-when-cross-origin" title="\(escapedTitle)"></iframe>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))

        content.alignment = .center   // justify-center
        content.addArrangedSubview(webView)
        NSLayoutConstraint.activate([webWidth, webHeight])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `h-full max-h-[80%]` of the page, 24pt padding and a 1pt border around an `aspect-video`
    /// frame that `max-w-full` may narrow, the dialog being `max-w-max` and `w-full`.
    override func viewDidLayoutSubviews() {
        let height = (view.bounds.height * 0.8).rounded()
        let inner = max(0, height - 50)
        let width = max(0, min(view.bounds.width - 50, inner * 16 / 9)).rounded()
        if webWidth.constant != width { webWidth.constant = width }
        if webHeight.constant != inner { webHeight.constant = inner }
        super.viewDidLayoutSubviews()
        panel.bounds = CGRect(x: 0, y: 0, width: width + 50, height: height)
        panel.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }
}
