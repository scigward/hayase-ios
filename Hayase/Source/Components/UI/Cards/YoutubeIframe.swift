//
//  YoutubeIframe.swift
//  Hayase
//
//  Mirrors interface cards/YoutubeIframe.svelte for PreviewCard trailer embeds.
//

import UIKit
import WebKit

final class YoutubeIframe: UIView {
    var onHide: ((Bool) -> Void)?

    private var webView: WKWebView?
    private var currentID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    func configure(id: String?) {
        guard let id, !id.isEmpty else {
            reset()
            return
        }
        guard currentID != id else { return }
        currentID = id

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }

        webView?.removeFromSuperview()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.scrollView.isScrollEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        webView = view

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>html,body,iframe{margin:0;width:100%;height:100%;background:transparent;overflow:hidden;}</style>
        </head>
        <body>
          <iframe src="https://www.youtube.com/embed/\(id)?autoplay=1&mute=1&controls=0&playsinline=1&loop=1&playlist=\(id)"
            frameborder="0" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>
        </body>
        </html>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        onHide?(false)
    }

    func reset() {
        currentID = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        onHide?(true)
    }
}
