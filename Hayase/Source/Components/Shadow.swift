

import SwiftSoup
import UIKit
import WebKit

/// Shared host for the exact parser engines used by interface/Shadow.svelte.
/// Raw user content is passed as JSON to a bundled script, never interpolated into HTML.
class AniListRichTextView: UIView, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    enum Kind { case thread, comment, profile }
    var onHeightChange: ((CGFloat) -> Void)?
    var onNavigatePath: ((String) -> Void)?
    private let webView: WKWebView
    private let kind: Kind
    private var lastHeight: CGFloat = -1
    private var documentLoaded = false
    private static let baseURL = URL(string: "https://hayase-rich-text.invalid/")!

    init(html: String?, kind: Kind) {
        self.kind = kind
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = kind == .profile
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let controller = configuration.userContentController
        controller.add(RichTextWeakMessageHandler(self), contentWorld: .defaultClient, name: "height")
        controller.add(RichTextWeakMessageHandler(self), contentWorld: .defaultClient, name: "renderError")
        let content = html ?? (kind == .profile ? "No user description" : "")
        let encoded = (try? JSONEncoder().encode(content)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let mount = """
        const root = document.getElementById('content');
        try { root.innerHTML = window.HayaseRichText.render(\(encoded)); }
        catch (error) {
          root.textContent = \(encoded);
          window.webkit.messageHandlers.renderError.postMessage(String(error));
        }
        let scheduled = false;
        const sendHeight = () => {
          if (scheduled) return;
          scheduled = true;
          requestAnimationFrame(() => {
            scheduled = false;
            const style = getComputedStyle(document.body);
            // Measure content, not body.scrollHeight (which cannot shrink below the viewport).
            const height = Math.ceil(root.getBoundingClientRect().height +
              parseFloat(style.paddingTop) + parseFloat(style.paddingBottom));
            window.webkit.messageHandlers.height.postMessage(height);
          });
        };
        new ResizeObserver(sendHeight).observe(root);
        root.addEventListener('load', sendHeight, true);
        root.addEventListener('error', sendHeight, true);
        root.addEventListener('toggle', sendHeight, true);
        window.addEventListener('resize', sendHeight);
        document.fonts.ready.then(sendHeight);
        sendHeight();
        """
        controller.addUserScript(WKUserScript(source: Self.parserScripts + "\n" + mount,
                                             injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        webView.loadHTMLString(Self.document(kind: kind), baseURL: Self.baseURL)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "height", contentWorld: .defaultClient)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "renderError", contentWorld: .defaultClient)
    }

    private static let parserScripts: String = {
        ["marked.umd", "purify.min", "AniListRichText"].map { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "RichText")
                    ?? Bundle.main.url(forResource: name, withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else {
                NSLog("[AniListRichText] Missing bundled parser resource: %@", name)
                return ""
            }
            return source
        }.joined(separator: "\n")
    }()

    private static let fontCSS: String = {
        guard let url = Bundle.main.url(forResource: "Nunito-Variable", withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: "Nunito-Variable", withExtension: "ttf"),
              let data = try? Data(contentsOf: url) else { return "" }
        return "@font-face { font-family: Nunito; src: url(data:font/ttf;base64,\(data.base64EncodedString())) format('truetype'); font-weight: 200 1000; }"
    }()

    private static func document(kind: Kind) -> String {
        let padding = kind == .profile ? 8 : (kind == .thread ? 12 : 0)
        let color = kind == .profile ? "98%" : "63.9%"
        let size = kind == .thread ? 16 : 14
        let lineHeight = kind == .thread ? 24 : 20
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; font-src data:; img-src https: http: data:; media-src https: http:; frame-src https://www.youtube-nocookie.com; base-uri 'none'; form-action 'none'">
        <style>
        \(fontCSS)
        html, body { margin:0; background:transparent; overflow-x:hidden; }
        body { padding:\(padding)px 0; color:hsl(0 0% \(color)); font-family:Nunito,-apple-system,sans-serif; font-size:\(size)px; line-height:\(lineHeight)px; }
        #content { display:flow-root; overflow-wrap:break-word; }
        p, details { margin-block-start:.5em; margin-block-end:.5em; white-space:pre-wrap; }
        img, video { max-width:100%; -webkit-user-drag:none; }
        summary { font-weight:bold; cursor:pointer; list-style:none; background:#0003; display:inline-block; padding:.4em .8em; border-radius:.5em; margin-block-end:.5em; }
        </style></head><body><div id="content"></div></body></html>
        """
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        if message.name == "renderError" {
            // Do not log user HTML/profile text.
            NSLog("[AniListRichText] Rendering failed; displaying plain text")
            return
        }
        guard message.name == "height", let value = message.body as? NSNumber else { return }
        let measured = value.doubleValue
        guard measured.isFinite, measured >= 0 else { return }
        let height = kind == .profile ? min(max(CGFloat(ceil(measured)), 20), 200) : CGFloat(ceil(measured))
        guard abs(height - lastHeight) >= 1, let onHeightChange else { return }
        lastHeight = height
        onHeightChange(height)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        documentLoaded = true
    }

    private func openLink(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if url.host == Self.baseURL.host {
            if let fragment = url.fragment, fragment.hasPrefix("/app/") {
                onNavigatePath?(fragment)
            } else if url.path.hasPrefix("/app/") {
                onNavigatePath?(url.path)
            }
            return // Includes source @mentions with href='#' (no-op in interface).
        }
        if url.host?.lowercased() == "anilist.co",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let parts = components.path.split(separator: "/")
            if parts.count >= 2, parts[0] == "anime", Int(parts[1]) != nil {
                onNavigatePath?("/app/anime/\(parts[1])")
                return
            }
        }
        guard ["https", "http", "mailto"].contains(scheme) else { return }
        UIApplication.shared.open(url)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.navigationType == .linkActivated {
            openLink(url)
            decisionHandler(.cancel)
        } else if navigationAction.targetFrame?.isMainFrame == false {
            // Only the controlled YouTube embed can navigate a child frame.
            decisionHandler(url.scheme == "https" && url.host == "www.youtube-nocookie.com" ? .allow : .cancel)
        } else {
            decisionHandler(!documentLoaded && (url == Self.baseURL || url.absoluteString == "about:blank") ? .allow : .cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url { openLink(url) }
        return nil
    }
}

private final class RichTextWeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - AniListShadowView

/// Thread/comment styling around the shared interface-compatible renderer.
final class AniListShadowView: AniListRichTextView {
    override init(html: String?, kind: Kind = .thread) { super.init(html: html, kind: kind) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - ProfileShadowView

/// Profile descriptions share parsing with forums, but scroll at the web's 200pt cap.
final class ProfileShadowView: AniListRichTextView {
    static let maxHeight: CGFloat = 200
    init(html: String?) { super.init(html: html, kind: .profile) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func estimatedHeight(for html: String?, width: CGFloat) -> CGFloat {
        let text = html ?? "No user description"
        if text.range(of: #"(?i)<|img\s|img\(|youtube|webm|~!"#, options: .regularExpression) != nil {
            return maxHeight
        }
        let plain = (try? SwiftSoup.parseBodyFragment(text).text()) ?? text
        let rect = (plain as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.nunito(ofSize: 14, weight: .regular)], context: nil)
        return min(max(ceil(rect.height), 20) + 16, maxHeight)
    }
}
