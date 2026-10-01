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

    // Attach this noninteractive sibling behind the card's banner/body. One
    // transparent WebKit viewport renders both the trailer and its ambient copy.
    let ambientView: UIView = YoutubeAmbientView()

    private var webView: WKWebView?
    private var currentID: String?
    private var muted = true
    private var isTrailerHidden = true
    private var isSuspended = false
    private var hasPlaybackError = false

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
        isOpaque = false
        clipsToBounds = true
        isUserInteractionEnabled = true
        ambientView.alpha = 0
        addSubview(muteButton)
        NSLayoutConstraint.activate([
            muteButton.topAnchor.constraint(equalTo: topAnchor),
            muteButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            muteButton.widthAnchor.constraint(equalToConstant: 40),
            muteButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        muteButton.addTarget(self, action: #selector(toggleMute), for: .touchUpInside)
        NotificationCenter.default.addObserver(self, selector: #selector(suspendPlayback),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumePlayback),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)

        updateMuteButton()
    }

    func configure(id: String?) {
        guard let id, id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
            reset()
            return
        }
        guard currentID != id else {
            loadCurrentVideoIfVisible()
            return
        }
        removeWebView()
        currentID = id
        muted = true
        hasPlaybackError = false
        updateMuteButton()
        setHidden(true, animated: false)
        loadCurrentVideoIfVisible()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            removeWebView()
            setHidden(true, animated: false)
        } else {
            loadCurrentVideoIfVisible()
        }
    }

    private func loadCurrentVideoIfVisible() {
        // Configuration happens before a preview is attached. Avoid creating a
        // WebKit process/decoders for cards that never become visible.
        guard window != nil, !isSuspended,
              UIApplication.shared.applicationState == .active,
              !ProcessInfo.processInfo.isLowPowerModeEnabled,
              !hasPlaybackError, webView == nil, let id = currentID else { return }

        let controller = WKUserContentController()
        controller.add(WeakScriptMessageHandler(delegate: self), name: "youtube")

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController = controller
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        ambientView.addSubview(view)
        ambientView.setNeedsLayout()
        webView = view
        view.loadHTMLString(Self.html(for: id, muted: muted), baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }

    func reset() {
        currentID = nil
        muted = true
        hasPlaybackError = false
        removeWebView()
        setHidden(true, animated: false)
    }

    private func removeWebView() {
        // Pause both embeds and clear their handshake timer before discarding
        // the page; no snapshots or display-link polling are retained.
        webView?.evaluateJavaScript("ytDispose();", completionHandler: nil)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "youtube")
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    private func setHidden(_ hidden: Bool, animated: Bool = true) {
        let changed = isTrailerHidden != hidden
        isTrailerHidden = hidden
        let targetAlpha: CGFloat = hidden ? 0 : 1
        if !hidden {
            muteButton.isHidden = false
        }
        isUserInteractionEnabled = !hidden
        if !animated {
            ambientView.layer.removeAllAnimations()
            muteButton.layer.removeAllAnimations()
            ambientView.alpha = targetAlpha
            muteButton.alpha = targetAlpha
            muteButton.isHidden = hidden
            if changed { onHide?(hidden) }
            return
        }
        guard changed else { return }
        webView?.evaluateJavaScript("ytShowGlow(\(hidden ? "false" : "true"));", completionHandler: nil)
        if !hidden {
            // The native banner crossfades away above this opaque foreground.
            // Fading both layers would dim the image at the transition midpoint.
            ambientView.layer.removeAllAnimations()
            ambientView.alpha = 1
        }
        UIView.animate(withDuration: 0.3,
                       delay: 0,
                       options: [.beginFromCurrentState, .curveEaseInOut]) {
            if hidden { self.ambientView.alpha = 0 }
            self.muteButton.alpha = targetAlpha
        } completion: { [weak self] finished in
            guard let self, hidden, self.isTrailerHidden, finished else { return }
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

    @objc private func suspendPlayback() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.suspendPlayback() }
            return
        }
        isSuspended = true
        webView?.evaluateJavaScript("ytPause();", completionHandler: nil)
        setHidden(true)
    }

    @objc private func resumePlayback() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.resumePlayback() }
            return
        }
        isSuspended = false
        guard window != nil, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        if webView == nil {
            loadCurrentVideoIfVisible()
        } else {
            webView?.evaluateJavaScript("ytResume();", completionHandler: nil)
        }
    }

    @objc private func powerStateChanged() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.powerStateChanged() }
            return
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            removeWebView()
            setHidden(true)
        } else {
            loadCurrentVideoIfVisible()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // A discarded page can still have messages in flight after reuse.
        guard let currentWebView = webView, message.webView === currentWebView, window != nil, !isSuspended,
              message.name == "youtube", let text = message.body as? String else { return }
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
            hasPlaybackError = true
            setHidden(true)
            removeWebView()
            return
        }

        if event == "onError" {
            hasPlaybackError = true
            setHidden(true)
            removeWebView()
            return
        }

        if event == "infoDelivery",
           let info = json["info"] as? [String: Any],
           let state = info["playerState"] as? Int {
            if state == 1 {
                setHidden(false)
            } else if state == 0 {
                // Interface loops without YouTube's playlist overlay. Reuse
                // both existing embeds instead of rebuilding WKWebView.
                webView?.evaluateJavaScript("ytRestart();", completionHandler: nil)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        removeWebView()
    }

    private static func html(for id: String, muted: Bool) -> String {
        let params = "autoplay=1&controls=0&disablekb=1&cc_lang_pref=ja&rel=0&playsinline=1&fs=0"
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
              inset: \(Int(YoutubeAmbientView.glowPadding))px;
              overflow: hidden;
              border-radius: 4px 4px 0 0;
              opacity: 1;
              transition: opacity 0.3s;
            }
            .blurred {
              z-index: 0;
              opacity: 0;
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
            <iframe id="glow" title="trailer-background" allow="autoplay" src="https://www.youtube-nocookie.com/embed/\(id)?\(params)&mute=1&enablejsapi=1"></iframe>
          </div>
          <div class="frame">
            <iframe id="frame" title="trailer" allow="autoplay" src="https://www.youtube-nocookie.com/embed/\(id)?\(params)&mute=\(muted ? 1 : 0)&enablejsapi=1"></iframe>
          </div>
          <script>
            const frame = document.getElementById('frame');
            const glow = document.getElementById('glow');
            const ambient = document.querySelector('.blurred');
            const origin = 'https://www.youtube-nocookie.com';
            let timeout, deadline, disposed = false, suspended = false, lastPlayerState;
            function command(target, action, args = null) {
              target.contentWindow?.postMessage(JSON.stringify({ event: 'command', func: action, args }), origin);
            }
            function ytCall(action, arg = null) {
              command(frame, action, arg);
            }
            function ytShowGlow(visible) {
              ambient.style.opacity = visible ? '1' : '0';
            }
            function clearHandshake() {
              clearInterval(timeout);
              clearTimeout(deadline);
            }
            function ytPause() {
              suspended = true;
              command(frame, 'pauseVideo');
              command(glow, 'pauseVideo');
            }
            function ytResume() {
              suspended = false;
              lastPlayerState = undefined;
              command(frame, 'playVideo');
              command(glow, 'mute');
              command(glow, 'playVideo');
            }
            function ytRestart() {
              if (disposed || suspended) return;
              command(frame, 'loadVideoById', ['\(id)']);
              command(glow, 'mute');
              command(glow, 'loadVideoById', ['\(id)']);
            }
            function ytDispose() {
              disposed = true;
              clearHandshake();
              ytPause();
            }
            function initFrame() {
              if (disposed) return;
              clearHandshake();
              const listen = () => {
                frame.contentWindow?.postMessage('{"event":"listening","id":1,"channel":"widget"}', origin);
                glow.contentWindow?.postMessage('{"event":"listening","id":2,"channel":"widget"}', origin);
              };
              timeout = setInterval(function () {
                listen();
              }, 100);
              // An unavailable embed must not leave a permanent 10Hz timer.
              deadline = setTimeout(clearHandshake, 10000);
              listen();
            }
            window.addEventListener('message', function (event) {
              if (disposed || event.origin !== origin) return;
              let json;
              try { json = typeof event.data === 'string' ? JSON.parse(event.data) : event.data; }
              catch (_) { return; }
              if (!json || !json.event) return;
              if (event.source === glow.contentWindow) {
                if (json.event === 'onReady') {
                  command(glow, 'mute');
                  if (suspended) command(glow, 'pauseVideo');
                } else if (suspended && json.event === 'infoDelivery' && json.info?.playerState === 1) {
                  command(glow, 'pauseVideo');
                }
                return;
              }
              if (event.source !== frame.contentWindow) return;
              clearHandshake();
              if (json.event === 'onReady') command(frame, 'setVolume', [30]);
              if (suspended) {
                if (json.event === 'onReady' || (json.event === 'infoDelivery' && json.info?.playerState === 1)) {
                  command(frame, 'pauseVideo');
                }
                return;
              }
              // The embed delivers playback telemetry repeatedly. PreviewCard
              // only needs state changes, readiness and unplayable errors.
              if (json.event === 'infoDelivery') {
                const state = json.info?.playerState;
                if (typeof state !== 'number' || state === lastPlayerState) return;
                lastPlayerState = state;
                json = { event: 'infoDelivery', info: { playerState: state } };
              } else if (json.event === 'initialDelivery') {
                if (json.info?.videoData?.isPlayable !== false) return;
                json = { event: 'initialDelivery', info: { videoData: { isPlayable: false } } };
              } else if (json.event !== 'onReady' && json.event !== 'onError') {
                return;
              }
              window.webkit?.messageHandlers?.youtube?.postMessage(JSON.stringify(json));
            });
            frame.addEventListener('load', initFrame);
            glow.addEventListener('load', function () {
              if (disposed) return;
              glow.contentWindow?.postMessage('{"event":"listening","id":2,"channel":"widget"}', origin);
            });
            window.addEventListener('pagehide', ytDispose);
          </script>
        </body>
        </html>
        """
    }
}

private final class YoutubeAmbientView: UIView {
    // Three blur radii keep the 40px CSS Gaussian's visible falloff inside the
    // WebKit surface, rather than clipping it to the actual banner rectangle.
    static let glowPadding: CGFloat = 120

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        isUserInteractionEnabled = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The CSS inset cancels this padding for both actual video rectangles.
        // Only the glow's falloff paints into the expanded area.
        subviews.forEach { $0.frame = bounds.insetBy(dx: -Self.glowPadding, dy: -Self.glowPadding) }
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
