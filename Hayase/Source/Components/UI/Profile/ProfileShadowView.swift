//
//  ProfileShadowView.swift
//  Hayase
//
//  Mirrors: lib/components/Shadow.svelte for AniList profile descriptions.
//

import UIKit
import WebKit

final class ProfileShadowView: UIView {
    static let maxHeight: CGFloat = 200

    var onHeightChange: ((CGFloat) -> Void)?
    var onNavigatePath: ((String) -> Void)?

    private let webView: WKWebView
    private var lastHeight: CGFloat = 0

    init(html: String?) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        setup()
        webView.configuration.userContentController.add(WeakScriptMessageHandler(self), name: "height")
        webView.loadHTMLString(Self.documentHTML(for: html), baseURL: Self.fontBaseURL)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "height")
    }

    private func setup() {
        backgroundColor = .clear
        clipsToBounds = true

        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    static func estimatedHeight(for html: String?, width: CGFloat) -> CGFloat {
        let fallback = "No user description"
        let text = html?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? html! : fallback
        if containsRichContent(text) { return maxHeight }

        let plain = plainText(from: text)
        let font = UIFont.nunito(ofSize: 14, weight: .regular)
        let rect = (plain as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                     attributes: [.font: font],
                                                     context: nil)
        return min(max(ceil(rect.height), 20) + 16, maxHeight)
    }

    private func updateHeight(_ height: CGFloat) {
        let clamped = min(max(ceil(height), 20), Self.maxHeight)
        guard abs(clamped - lastHeight) >= 1,
              let onHeightChange else { return }
        lastHeight = clamped
        onHeightChange(clamped)
    }

    private static var fontBaseURL: URL? {
        if let url = Bundle.main.url(forResource: "Nunito-Variable", withExtension: "ttf", subdirectory: "Fonts") {
            return url.deletingLastPathComponent()
        }
        return Bundle.main.url(forResource: "Nunito-Variable", withExtension: "ttf")?.deletingLastPathComponent()
    }

    private static func documentHTML(for rawHTML: String?) -> String {
        let body = render(rawHTML)
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <style>
            @font-face { font-family: 'Nunito'; src: url('Nunito-Variable.ttf') format('truetype'); }
            html, body { margin: 0; padding: 0; background: transparent; overflow-x: hidden; }
            body { padding: 8px 0; color: hsl(0 0% 98%); font-family: 'Nunito', -apple-system, BlinkMacSystemFont, sans-serif; font-size: 14px; line-height: 20px; -webkit-user-select: none; -webkit-touch-callout: none; }
            p, details { margin-block-start: .5em; margin-block-end: .5em; white-space: pre-wrap; }
            img, video { max-width: 100%; -webkit-user-drag: none; }
            summary { font-weight: bold; cursor: pointer; list-style: none; background: #0003; display: inline-block; padding: 0.4em 0.8em; border-radius: 0.5em; margin-block-end: .5em; }
          </style>
        </head>
        <body>
          \(body)
          <script>
            const sendHeight = () => window.webkit.messageHandlers.height.postMessage(Math.ceil(document.body.scrollHeight));
            new ResizeObserver(sendHeight).observe(document.body);
            window.addEventListener('load', sendHeight);
            document.addEventListener('DOMContentLoaded', sendHeight);
            setTimeout(sendHeight, 50);
            setTimeout(sendHeight, 300);
            sendHeight();
          </script>
        </body>
        </html>
        """
    }

    private static func render(_ rawHTML: String?) -> String {
        let fallback = "No user description"
        var html = rawHTML?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? rawHTML! : fallback
        html = forceSecureMediaURLs(html)
        html = renderAniListImageSyntax(html)
        html = renderUserLinks(html)
        html = replace(pattern: "youtube\\s?\\([\\s\\S]*?([-_0-9A-Za-z]{10,15})[\\s\\S]*?\\)", in: html, options: [.caseInsensitive]) { match, text in
            "youtube (\(substring(in: text, for: match.range(at: 1))))"
        }
        html = replace(pattern: "webm\\s?\\(h?([A-Za-z0-9-._~:/?#\\[\\]@!$&()*+,;=%]+)\\)", in: html, options: [.caseInsensitive]) { match, text in
            "webmv(`\(substring(in: text, for: match.range(at: 1)))`)"
        }
        html = replace(pattern: "~{3}([\\s\\S]*?)~{3}", in: html) { match, text in
            "+++\(substring(in: text, for: match.range(at: 1)))+++"
        }
        html = replace(pattern: "~!([\\s\\S]*?)!~", in: html) { match, text in
            "<details><summary>Spoiler, click to view</summary>\(substring(in: text, for: match.range(at: 1)))</details>"
        }
        html = sanitize(markdown(html))
        html = replace(pattern: "\\+{3}([\\s\\S]*?)\\+{3}", in: html) { match, text in
            "<center>\(substring(in: text, for: match.range(at: 1)))</center>"
        }
        html = replace(pattern: "youtube\\s?\\(([-_0-9A-Za-z]{10,15})\\)", in: html, options: [.caseInsensitive]) { match, text in
            let id = attributeEscape(substring(in: text, for: match.range(at: 1)))
            return "<iframe credentialless style=\"width: 500px; height: 200px; max-width: 100%; border: none;\" title=\"youtube-embed\" allow=\"autoplay\" allowfullscreen src=\"https://www.youtube-nocookie.com/embed/\(id)?enablejsapi=1&autoplay=0&controls=1&mute=0&disablekb=1&loop=1&playlist=\(id)&cc_lang_pref=ja\"></iframe>"
        }
        html = replace(pattern: "webmv\\s?\\(<code>([A-Za-z0-9-._~:/?#\\[\\]@!$&()*+,;=%]+)</code>\\)", in: html, options: [.caseInsensitive]) { match, text in
            let url = attributeEscape("h" + substring(in: text, for: match.range(at: 1)))
            return "<video muted loop controls><source src=\"\(url)\" type=\"video/webm\">Your browser does not support the video tag.</video>"
        }
        return html
    }

    private static func forceSecureMediaURLs(_ html: String) -> String {
        replace(pattern: "http(:\\/\\/[^\\s\"'()<>]+?\\.(?:jpe?g|gif|png|mp4|webm))", in: html, options: [.caseInsensitive]) { match, text in
            "https\(substring(in: text, for: match.range(at: 1)))"
        }
    }

    private static func renderAniListImageSyntax(_ html: String) -> String {
        replace(pattern: "img\\s?(\\d+%?)?\\s?\\(([^\\s)]+)\\)", in: html, options: [.caseInsensitive]) { match, text in
            let width = substring(in: text, for: match.range(at: 1))
            let src = attributeEscape(substring(in: text, for: match.range(at: 2)))
            return "<img width=\"\(attributeEscape(width))\" src=\"\(src)\">"
        }
    }

    private static func renderUserLinks(_ html: String) -> String {
        replace(pattern: "(^|>| )@([A-Za-z0-9]+)", in: html, options: [.anchorsMatchLines]) { match, text in
            let prefix = substring(in: text, for: match.range(at: 1))
            let name = htmlEscape(substring(in: text, for: match.range(at: 2)))
            return "\(prefix)<a href=\"#\" target=\"_blank\" rel=\"noopener noreferrer\">@\(name)</a>"
        }
    }

    private static func markdown(_ html: String) -> String {
        let normalized = html.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = markdownBlocks(normalized)
        return blocks.map { block in
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            if trimmed.hasPrefix("<details") || trimmed.hasPrefix("<center") { return inlineMarkdown(trimmed) }
            if let heading = headingHTML(trimmed) { return heading }
            if let list = listHTML(trimmed) { return list }
            if trimmed.hasPrefix("> ") {
                let quote = trimmed.split(separator: "\n").map { line -> String in
                    line.hasPrefix("> ") ? String(line.dropFirst(2)) : String(line)
                }.joined(separator: "\n")
                return "<blockquote>\(inlineMarkdown(quote))</blockquote>"
            }
            return "<p>\(inlineMarkdown(trimmed))</p>"
        }.joined(separator: "\n")
    }

    private static func headingHTML(_ block: String) -> String? {
        for level in 1...5 {
            let prefix = String(repeating: "#", count: level) + " "
            if block.hasPrefix(prefix) {
                return "<h\(level)>\(inlineMarkdown(String(block.dropFirst(prefix.count))))</h\(level)>"
            }
        }
        return nil
    }

    private static func listHTML(_ block: String) -> String? {
        let lines = block.split(separator: "\n").map(String.init)
        guard !lines.isEmpty else { return nil }
        let unordered = lines.allSatisfy { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
        if unordered {
            return "<ul>" + lines.map { "<li>\(inlineMarkdown(String($0.dropFirst(2))))</li>" }.joined() + "</ul>"
        }
        let orderedRegex = try? NSRegularExpression(pattern: "^\\d+\\. ")
        let ordered = lines.allSatisfy { line in
            let range = NSRange(location: 0, length: (line as NSString).length)
            return orderedRegex?.firstMatch(in: line, range: range) != nil
        }
        guard ordered else { return nil }
        return "<ol>" + lines.map { line in
            let text = line.replacingOccurrences(of: "^\\d+\\. ", with: "", options: .regularExpression)
            return "<li>\(inlineMarkdown(text))</li>"
        }.joined() + "</ol>"
    }

    private static func inlineMarkdown(_ text: String) -> String {
        var html = text
        html = replace(pattern: "`([^`]+)`", in: html) { match, text in
            "<code>\(htmlEscape(substring(in: text, for: match.range(at: 1))))</code>"
        }
        html = replace(pattern: "\\[([^\\]]+)\\]\\(([^\\s)]+)(?:\\s+\"([^\"]+)\")?\\)", in: html) { match, text in
            let title = substring(in: text, for: match.range(at: 3))
            let href = renderedLinkHref(substring(in: text, for: match.range(at: 2)))
            let titleAttr = title.isEmpty ? "" : " title=\"\(attributeEscape(title))\""
            return "<a href=\"\(attributeEscape(href))\" target=\"_blank\" rel=\"noopener noreferrer\"\(titleAttr)>\(htmlEscape(substring(in: text, for: match.range(at: 1))))</a>"
        }
        html = replace(pattern: "\\*\\*([^*]+)\\*\\*", in: html) { match, text in
            "<strong>\(substring(in: text, for: match.range(at: 1)))</strong>"
        }
        html = replace(pattern: "__([^_]+)__", in: html) { match, text in
            "<strong>\(substring(in: text, for: match.range(at: 1)))</strong>"
        }
        html = replace(pattern: "~~([^~]+)~~", in: html) { match, text in
            "<del>\(substring(in: text, for: match.range(at: 1)))</del>"
        }
        html = replace(pattern: "(^|[^*])\\*([^*]+)\\*", in: html) { match, text in
            "\(substring(in: text, for: match.range(at: 1)))<em>\(substring(in: text, for: match.range(at: 2)))</em>"
        }
        return html.replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func renderedLinkHref(_ href: String) -> String {
        let animeURL = "https://anilist.co/anime/"
        guard href.hasPrefix(animeURL) else { return href }
        let rest = href.dropFirst(animeURL.count)
        let id = rest.split(separator: "/").first.map(String.init) ?? ""
        return "/#/app/anime/\(id)"
    }

    private static func sanitize(_ html: String) -> String {
        var sanitized = html
        sanitized = sanitized.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        sanitized = sanitized.replacingOccurrences(of: "<\\s*(script|style|object|embed|link|meta)[^>]*>[\\s\\S]*?<\\s*/\\s*\\1\\s*>", with: "", options: [.regularExpression, .caseInsensitive])
        sanitized = sanitized.replacingOccurrences(of: "<\\s*(script|style|object|embed|link|meta)[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        return replace(pattern: "<\\s*(/?)\\s*([A-Za-z][A-Za-z0-9]*)\\b([^>]*)>", in: sanitized) { match, text in
            let closing = !substring(in: text, for: match.range(at: 1)).isEmpty
            let tag = substring(in: text, for: match.range(at: 2)).lowercased()
            let attrs = substring(in: text, for: match.range(at: 3))
            guard allowedTags.contains(tag) else { return "" }
            if closing { return "</\(tag)>" }
            let cleanedAttrs = sanitizedAttributes(attrs)
            return cleanedAttrs.isEmpty ? "<\(tag)>" : "<\(tag) \(cleanedAttrs)>"
        }
    }

    private static func sanitizedAttributes(_ attrs: String) -> String {
        let regex = try? NSRegularExpression(pattern: "([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s\"'>]+)")
        guard let regex else { return "" }
        let nsText = attrs as NSString
        let matches = regex.matches(in: attrs, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            let name = nsText.substring(with: match.range(at: 1)).lowercased()
            guard allowedAttributes.contains(name), !name.hasPrefix("on") else { return nil }
            var value = nsText.substring(with: match.range(at: 2))
            if value.hasPrefix("\"") || value.hasPrefix("'") { value.removeFirst() }
            if value.hasSuffix("\"") || value.hasSuffix("'") { value.removeLast() }
            value = htmlEntityDecode(value)
            if (name == "href" || name == "src"), !isSafeURL(value) { return nil }
            return "\(name)=\"\(attributeEscape(value))\""
        }.joined(separator: " ")
    }

    private static func isSafeURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("https://")
            || trimmed.hasPrefix("http://")
            || trimmed.hasPrefix("//")
            || trimmed.hasPrefix("/#/")
            || trimmed.hasPrefix("#")
            || trimmed.hasPrefix("/")
            || trimmed.hasPrefix("mailto:")
    }

    private static func containsRichContent(_ text: String) -> Bool {
        let patterns = ["img\\s?(\\d+%?)?\\s?\\(", "youtube\\s?\\(", "webm\\s?\\(", "~{3}", "<img", "<video", "<iframe"]
        return patterns.contains { pattern in
            let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
            return range != nil
        }
    }

    private static func plainText(from html: String) -> String {
        html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(pattern: String,
                                in text: String,
                                options: NSRegularExpression.Options = [],
                                transform: (NSTextCheckingResult, String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = 0
        for match in matches {
            let prefixRange = NSRange(location: cursor, length: match.range.location - cursor)
            result += nsText.substring(with: prefixRange)
            result += transform(match, text)
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            result += nsText.substring(from: cursor)
        }
        return result
    }

    private static func substring(in text: String, for range: NSRange) -> String {
        guard range.location != NSNotFound, range.length > 0 else { return "" }
        return (text as NSString).substring(with: range)
    }

    private static func htmlEntityDecode(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func htmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func attributeEscape(_ value: String) -> String {
        htmlEscape(value).replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#039;")
    }

    private static let allowedTags: Set<String> = [
        "a", "b", "blockquote", "br", "center", "del", "div", "em", "font", "h1", "h2", "h3", "h4", "h5", "hr", "i", "img", "li", "ol", "p", "pre", "code", "span", "strike", "strong", "ul", "details", "summary"
    ]

    private static let allowedAttributes: Set<String> = [
        "align", "height", "href", "src", "target", "width", "rel"
    ]

    private static func markdownBlocks(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\n\\s*\\n") else { return [text] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return [text] }

        var blocks: [String] = []
        var cursor = 0
        for match in matches {
            blocks.append(nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = match.range.location + match.range.length
        }
        if cursor <= nsText.length {
            blocks.append(nsText.substring(from: cursor))
        }
        return blocks
    }
}


private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

extension ProfileShadowView: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let number = message.body as? NSNumber {
            updateHeight(CGFloat(truncating: number))
        }
    }
}

extension ProfileShadowView: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if let path = routePath(from: url) {
            onNavigatePath?(path)
            decisionHandler(.cancel)
            return
        }

        if url.absoluteString == "about:blank" || url.absoluteString.hasSuffix("#") {
            decisionHandler(.cancel)
            return
        }

        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }

    private func routePath(from url: URL) -> String? {
        if let fragment = url.fragment, fragment.hasPrefix("/app/") { return fragment }
        if url.path.hasPrefix("/app/") { return url.path }
        return nil
    }
}


extension ProfileShadowView: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else { return nil }

        if let path = routePath(from: url) {
            onNavigatePath?(path)
        } else if url.absoluteString != "about:blank" && !url.absoluteString.hasSuffix("#") {
            UIApplication.shared.open(url)
        }
        return nil
    }
}
