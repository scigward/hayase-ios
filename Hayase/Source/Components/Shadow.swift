

import SwiftSoup
import UIKit
import WebKit

/// Shared host for the exact parser engines used by interface/Shadow.svelte.
///
/// A body is drawn by a web view of its own (it scrolls, selects, plays and folds like a page), and a thread has
/// tens of them. They all share one process pool and one data store, so they are one web content process, and
/// none of them carries the parser: `RichTextRenderer` is the one web view that has marked and DOMPurify, and a
/// body view is given what it made of the text: plain, sanitised HTML.
class AniListRichTextView: UIView, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    enum Kind { case thread, comment, profile }
    var onHeightChange: ((CGFloat) -> Void)?
    var onNavigatePath: ((String) -> Void)?
    private let webView: WKWebView
    private let kind: Kind
    private var lastHeight: CGFloat = -1
    private var documentLoaded = false
    private var loadedDocument = ""
    fileprivate static let baseURL = URL(string: "https://hayase-rich-text.invalid/")!
    /// One process for every body of the app, instead of one for each.
    fileprivate static let processPool = WKProcessPool()
    fileprivate static let dataStore = WKWebsiteDataStore.nonPersistent()

    init(html: String?, kind: Kind) {
        self.kind = kind
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.processPool = AniListRichTextView.processPool
        configuration.websiteDataStore = AniListRichTextView.dataStore
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
        controller.addUserScript(WKUserScript(source: Self.measureScript, injectionTime: .atDocumentEnd,
                                             forMainFrameOnly: true, in: .defaultClient))
        let content = html ?? (kind == .profile ? "No user description" : "")
        RichTextRenderer.shared.render(content) { [weak self] sanitized in
            guard let self else { return }
            // a parser that did not run leaves the text as it is
            loadedDocument = Self.document(kind: kind, body: sanitized ?? Self.plainText(content))
            webView.loadHTMLString(loadedDocument, baseURL: Self.baseURL)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "height", contentWorld: .defaultClient)
    }

    /// The height of the content, which the host needs: measured on the content, not on `body.scrollHeight` (which
    /// cannot shrink below the viewport), and again when an image, the font or a spoiler changes it.
    private static let measureScript = """
    const root = document.getElementById('content');
    let scheduled = false;
    const sendHeight = () => {
      if (scheduled) return;
      scheduled = true;
      requestAnimationFrame(() => {
        scheduled = false;
        const style = getComputedStyle(document.body);
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

    fileprivate static let parserScripts: String = {
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

    /// Nunito, the variable font of the interface, as WOFF2 (101 KB of 277: the same glyphs and the same weights).
    private static let fontCSS: String = {
        func data(_ name: String, _ ext: String, _ folder: String) -> Data? {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: folder)
                    ?? Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
            return try? Data(contentsOf: url)
        }
        if let woff = data("Nunito-Variable", "woff2", "RichText") {
            return "@font-face { font-family: Nunito; src: url(data:font/woff2;base64,\(woff.base64EncodedString())) format('woff2'); font-weight: 200 1000; }"
        }
        guard let ttf = data("Nunito-Variable", "ttf", "Fonts") else { return "" }
        return "@font-face { font-family: Nunito; src: url(data:font/ttf;base64,\(ttf.base64EncodedString())) format('truetype'); font-weight: 200 1000; }"
    }()

    private static func plainText(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<p>\(escaped)</p>"
    }

    private static func document(kind: Kind, body: String) -> String {
        let padding = kind == .profile ? 8 : (kind == .thread ? 12 : 0)
        let color = kind == .profile ? "98%" : "50%"   // text-muted-foreground
        let size = kind == .thread ? 16 : 14
        let lineHeight = kind == .thread ? 24 : 20
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; font-src data:; img-src https: http: data:; media-src https: http:; frame-src https://www.youtube-nocookie.com; base-uri 'none'; form-action 'none'">
        <style>
        \(fontCSS)
        html { color-scheme:dark; }
        html, body { margin:0; background:transparent; overflow-x:hidden; }
        body { padding:\(padding)px 0; color:hsl(0 0% \(color)); font-family:Nunito,-apple-system,sans-serif; font-size:\(size)px; line-height:\(lineHeight)px; }
        #content { display:flow-root; }
        p, details { margin-block-start:.5em; margin-block-end:.5em; white-space:pre-wrap; }
        img, video { max-width:100%; -webkit-user-drag:none; }
        summary { font-weight:bold; cursor:pointer; list-style:none; background:#0003; display:inline-block; padding:.4em .8em; border-radius:.5em; margin-block-end:.5em; }
        </style></head><body><div id="content">\(body)</div></body></html>
        """
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
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

    /// All the bodies share one web content process: when the system ends it, every one of them is blank, and each
    /// draws its page again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !loadedDocument.isEmpty else { return }
        documentLoaded = false
        lastHeight = -1
        webView.loadHTMLString(loadedDocument, baseURL: Self.baseURL)
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

/// The one web view that parses and sanitises: marked, DOMPurify and the AniList syntax of `AniListRichText.js` are
/// loaded here and nowhere else. It is never shown. Raw user content goes in as an argument, never into a script's
/// text, and what comes out is DOMPurify's output.
final class RichTextRenderer: NSObject, WKNavigationDelegate {
    static let shared = RichTextRenderer()
    private let webView: WKWebView
    private var ready = false
    private var failed = false
    private var pending: [(content: String, completion: (String?) -> Void)] = []

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = AniListRichTextView.processPool
        configuration.websiteDataStore = AniListRichTextView.dataStore
        configuration.userContentController.addUserScript(WKUserScript(source: AniListRichTextView.parserScripts,
                                                                       injectionTime: .atDocumentEnd,
                                                                       forMainFrameOnly: true, in: .defaultClient))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        load()
    }

    private func load() {
        ready = false
        webView.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: AniListRichTextView.baseURL)
    }

    /// The sanitised HTML of `content`, or nil when the parser could not run.
    func render(_ content: String, completion: @escaping (String?) -> Void) {
        if failed {
            completion(nil)
        } else if ready {
            evaluate(content, completion)
        } else {
            pending.append((content, completion))
        }
    }

    private func evaluate(_ content: String, _ completion: @escaping (String?) -> Void) {
        webView.callAsyncJavaScript("return window.HayaseRichText.render(content)", arguments: ["content": content],
                                    in: nil, in: .defaultClient) { result in
            switch result {
            case .success(let value):
                completion(value as? String)
            case .failure:
                NSLog("[AniListRichText] Rendering failed; displaying plain text")   // never the text itself
                completion(nil)
            }
        }
    }

    private func flush(failing: Bool) {
        let waiting = pending
        pending = []
        for item in waiting {
            if failing { item.completion(nil) } else { evaluate(item.content, item.completion) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        flush(failing: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed = true
        flush(failing: true)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed = true
        flush(failing: true)
    }

    /// The process is shared with the bodies: when it ends, the parser is loaded again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        load()
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
