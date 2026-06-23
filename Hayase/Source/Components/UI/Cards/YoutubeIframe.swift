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

        var components = URLComponents(string: "https://www.youtube-nocookie.com/embed/\(id)")
        components?.queryItems = [
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "controls", value: "0"),
            URLQueryItem(name: "disablekb", value: "1"),
            URLQueryItem(name: "cc_lang_pref", value: "ja"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "fs", value: "0"),
            URLQueryItem(name: "mute", value: "1"),
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "origin", value: "https://www.youtube-nocookie.com")
        ]
        guard let url = components?.url else {
            reset()
            return
        }

        var request = URLRequest(url: url)
        request.setValue("https://www.youtube-nocookie.com", forHTTPHeaderField: "Referer")
        view.load(request)
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
