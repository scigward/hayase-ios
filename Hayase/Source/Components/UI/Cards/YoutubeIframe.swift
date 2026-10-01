//
//  YoutubeIframe.swift
//  Hayase
//
//  Mirrors interface cards/YoutubeIframe.svelte for PreviewCard trailer embeds.
//

import UIKit
import WebKit

final class YoutubeIframe: UIView, WKScriptMessageHandler {
    var onHide: ((Bool) -> Void)?

    private var webView: WKWebView?
    private var currentID: String?
    private var muted = true
    private var isPlaying = false

    private let muteButton: UIButton = {
        let button = UIButton(type: .system)
        button.tintColor = UIColor.HayaseTheme.foreground
        button.backgroundColor = .clear
        button.alpha = 0
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.imageView?.contentMode = .scaleAspectFit
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = true
        addSubview(muteButton)
        NSLayoutConstraint.activate([
            muteButton.topAnchor.constraint(equalTo: topAnchor),
            muteButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            muteButton.widthAnchor.constraint(equalToConstant: 40),
            muteButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        muteButton.addTarget(self, action: #selector(toggleMute), for: .touchUpInside)

        updateMuteButton()
    }

    func configure(id: String?) {
        guard let id, !id.isEmpty else {
            reset()
            return
        }
        guard currentID != id else { return }
        currentID = id
        muted = true
        isPlaying = false
        updateMuteButton()
        setHidden(true)

        let controller = WKUserContentController()
        controller.add(WeakScriptMessageHandler(delegate: self), name: "youtube")

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController = controller
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }

        removeWebView()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.alpha = 0
        view.isUserInteractionEnabled = false
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(view, belowSubview: muteButton)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        webView = view
        view.loadHTMLString(Self.html(for: id, muted: muted), baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }

    func reset() {
        currentID = nil
        muted = true
        isPlaying = false
        removeWebView()
        setHidden(true)
    }

    private func removeWebView() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "youtube")
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    private func setHidden(_ hidden: Bool) {
        let targetAlpha: CGFloat = hidden ? 0 : 1
        if !hidden {
            muteButton.isHidden = false
        }
        isUserInteractionEnabled = !hidden
        UIView.animate(withDuration: 0.3,
                       delay: 0,
                       options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.webView?.alpha = targetAlpha
            self.muteButton.alpha = targetAlpha
        } completion: { [weak self] finished in
            guard let self, hidden, finished else { return }
            self.muteButton.isHidden = true
        }
        onHide?(hidden)
    }

    private func updateMuteButton() {
        let icon = muted ? "volume-x" : "volume-2"
        muteButton.setImage(UIImage.hayaseFilledIcon(icon, pointSize: 16), for: .normal)
    }

    @objc private func toggleMute() {
        if muted {
            callPlayer("unMute")
        } else {
            callPlayer("mute")
        }
        muted.toggle()
        updateMuteButton()
    }

    private func callPlayer(_ action: String, args: String = "null") {
        webView?.evaluateJavaScript("ytCall('\(action)', \(args));")
    }

    private func restartCurrentVideo() {
        guard let id = currentID else { return }
        configure(id: nil)
        configure(id: id)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "youtube", let text = message.body as? String else { return }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else { return }

        if event == "onReady" {
            callPlayer("setVolume", args: "[30]")
            return
        }

        if event == "initialDelivery",
           let info = json["info"] as? [String: Any],
           let videoData = info["videoData"] as? [String: Any],
           let isPlayable = videoData["isPlayable"] as? Bool,
           !isPlayable {
            setHidden(true)
            return
        }

        if event == "infoDelivery",
           let info = json["info"] as? [String: Any],
           let state = info["playerState"] as? Int {
            if state == 1 {
                isPlaying = true
                setHidden(false)
            } else if state == 2 {
                isPlaying = false
            } else if state == 0 {
                isPlaying = false
                restartCurrentVideo()
            }
        }
    }

    deinit {
        removeWebView()
    }

    private static func html(for id: String, muted: Bool) -> String {
        let params = "autoplay=1&controls=0&disablekb=1&cc_lang_pref=ja&rel=0&playsinline=1&fs=0&mute=\(muted ? 1 : 0)"
        let escapedID = id.replacingOccurrences(of: "'", with: "\\'")
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            html, body {
              margin: 0;
              width: 100%;
              height: 100%;
              background: transparent;
              overflow: hidden;
            }
            .frame, .blurred {
              position: absolute;
              inset: 0;
              overflow: hidden;
              border-radius: 4px 4px 0 0;
              opacity: 1;
              transition: opacity 0.3s;
            }
            .blurred {
              z-index: 0;
              filter: blur(40px) saturate(2);
              pointer-events: none;
            }
            .frame {
              z-index: 1;
            }
            iframe {
              position: absolute;
              left: 0;
              top: 50%;
              width: 100%;
              height: calc(100% + 200px);
              border: 0;
              transform: translateY(-50%);
              pointer-events: none;
            }
          </style>
        </head>
        <body>
          <div class="blurred">
            <iframe title="trailer-background" allow="autoplay" src="https://www.youtube-nocookie.com/embed/\(escapedID)?\(params)"></iframe>
          </div>
          <div class="frame">
            <iframe id="frame" title="trailer" allow="autoplay" src="https://www.youtube-nocookie.com/embed/\(escapedID)?\(params)&enablejsapi=1"></iframe>
          </div>
          <script>
            const frame = document.getElementById('frame');
            let timeout;
            function ytCall(action, arg = null) {
              frame.contentWindow?.postMessage('{"event":"command", "func":"' + action + '", "args":' + arg + '}', '*');
            }
            function initFrame() {
              clearInterval(timeout);
              timeout = setInterval(function () {
                frame.contentWindow?.postMessage('{"event":"listening","id":1,"channel":"widget"}', '*');
              }, 100);
              frame.contentWindow?.postMessage('{"event":"listening","id":1,"channel":"widget"}', '*');
            }
            window.addEventListener('message', function (event) {
              if (event.origin !== 'https://www.youtube-nocookie.com') return;
              clearInterval(timeout);
              window.webkit?.messageHandlers?.youtube?.postMessage(event.data);
            });
            frame.addEventListener('load', initFrame);
          </script>
        </body>
        </html>
        """
    }
}

final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
