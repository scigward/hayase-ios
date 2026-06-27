// ThreadDetailViewController.swift
// Renders AniList forum threads in-app using WKWebView + dark HTML.
// Fetches thread body + comments from AniList GraphQL, builds a complete
// dark-themed HTML page — same approach as Hayase's thread detail page.

import UIKit
import WebKit

final class ThreadDetailViewController: UIViewController {

    // MARK: - Init
    private let threadID: Int
    private let threadTitle: String
    var routeThreadID: Int { threadID }

    init(threadID: Int, title: String) {
        self.threadID = threadID
        self.threadTitle = title
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Views
    private let webView: WKWebView = {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.backgroundColor = UIColor(white: 0.039, alpha: 1)
        wv.scrollView.backgroundColor = UIColor(white: 0.039, alpha: 1)
        wv.isOpaque = false
        wv.translatesAutoresizingMaskIntoConstraints = false
        return wv
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .large)
        s.color = .white
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.039, alpha: 1)
        view.addSubview(webView)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        spinner.startAnimating()
        fetchThread()
    }

    // MARK: - Fetch
    private func fetchThread() {
        let query = """
        query($id:Int){
          Thread(id:$id){
            id title body(asHtml:true) viewCount replyCount likeCount isLocked createdAt
            user{name avatar{large}}
            categories{id name}
          }
          Page(perPage:50){
            threadComments(threadId:$id,sort:ID){
              id comment(asHtml:true) likeCount createdAt
              user{name avatar{large}}
            }
          }
        }
        """
        guard let url = URL(string: "https://graphql.anilist.co") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": ["id": threadID]
        ])
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = json["data"] as? [String: Any] else {
                DispatchQueue.main.async { self?.showError() }
                return
            }
            let thread   = d["Thread"] as? [String: Any]
            let page     = d["Page"] as? [String: Any]
            let comments = page?["threadComments"] as? [[String: Any]] ?? []
            DispatchQueue.main.async {
                self.render(thread: thread, comments: comments)
            }
        }.resume()
    }

    // MARK: - Render
    private func render(thread: [String: Any]?, comments: [[String: Any]]) {
        spinner.stopAnimating()

        let body     = (thread?["body"] as? String ?? "<p>No content.</p>")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        let views    = thread?["viewCount"]  as? Int ?? 0
        let replies  = thread?["replyCount"] as? Int ?? 0
        let likes    = thread?["likeCount"]  as? Int ?? 0
        let locked   = thread?["isLocked"]   as? Bool ?? false
        let user     = thread?["user"]       as? [String: Any]
        let userName = user?["name"]         as? String ?? "Unknown"
        let avatarURL = (user?["avatar"] as? [String: Any])?["large"] as? String ?? ""

        let ts       = thread?["createdAt"]  as? TimeInterval ?? 0
        let timeAgo  = sinceString(ts)

        let lockedBadge = locked
            ? "<span class='badge locked'>\(lucideSVG("lock")) Locked</span>" : ""

        // Build comment HTML
        var commentsHTML = ""
        for c in comments {
            let cBody    = (c["comment"]  as? String ?? "<p>—</p>")
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
            let cLikes   = c["likeCount"] as? Int ?? 0
            let cTs      = c["createdAt"] as? TimeInterval ?? 0
            let cTime    = sinceString(cTs)
            let cUser    = c["user"]      as? [String: Any]
            let cName    = cUser?["name"] as? String ?? "Unknown"
            let cAvatar  = (cUser?["avatar"] as? [String: Any])?["large"] as? String ?? ""
            commentsHTML += """
            <div class='comment'>
              <div class='comment-header'>
                <img class='avatar' src='\(cAvatar)' onerror="this.style.display='none'"/>
                <span class='username'>\(htmlEscape(cName))</span>
                <span class='meta'>\(cTime)</span>
                <span class='meta stat-inline' style='margin-left:auto'>\(lucideSVG("heart")) \(cLikes)</span>
              </div>
              <div class='comment-body'>\(cBody)</div>
            </div>
            """
        }

        let noComments = comments.isEmpty
            ? "<p class='empty'>No comments yet.</p>" : ""

        let html = """
        <!DOCTYPE html><html lang='en'><head>
        <meta charset='UTF-8'>
        <meta name='viewport' content='width=device-width,initial-scale=1,maximum-scale=1'>
        <style>
          :root { color-scheme: dark; }
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body {
            background: #0a0a0a; color: #e5e5e5;
            font-family: -apple-system, system-ui, sans-serif;
            font-size: 14px; line-height: 1.6;
            padding: 16px; padding-bottom: 40px;
          }
          .thread-header { margin-bottom: 16px; }
          .thread-title  { font-size: 20px; font-weight: 700; color: #fff; margin-bottom: 8px; line-height: 1.3; }
          .meta-row      { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-bottom: 12px; }
          .avatar        { width: 28px; height: 28px; border-radius: 50%; object-fit: cover; }
          .username      { font-weight: 600; color: #e5e5e5; font-size: 13px; }
          .meta          { color: #888; font-size: 12px; }
          .badge         { background: #27272a; border-radius: 4px; padding: 2px 8px; font-size: 11px; color: #a3a3a3; }
          .badge, .stat-inline, .stats span { display: inline-flex; align-items: center; gap: 4px; }
          .badge.locked  { color: #f87171; }
          .stats         { display: flex; gap: 12px; color: #888; font-size: 12px; margin-bottom: 12px; }
          .icon          { width: 12px; height: 12px; flex: 0 0 12px; stroke: currentColor; fill: none; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
          .divider       { border: none; border-top: 1px solid #27272a; margin: 20px 0; }
          .thread-body, .comment-body { color: #d4d4d4; }
          .thread-body img, .comment-body img {
            max-width: 100%; border-radius: 8px; margin: 8px 0; height: auto;
          }
          .thread-body a, .comment-body a  { color: #60a5fa; }
          .thread-body p, .comment-body p  { margin-bottom: 10px; }
          .thread-body blockquote, .comment-body blockquote {
            border-left: 3px solid #3f3f46; margin: 8px 0; padding: 4px 12px; color: #a3a3a3;
          }
          .comment       { background: #111; border-radius: 8px; padding: 12px; margin-bottom: 8px; }
          .comment-header { display: flex; align-items: center; gap: 8px; margin-bottom: 8px; flex-wrap: wrap; }
          .comments-title { font-size: 15px; font-weight: 700; color: #fff; margin-bottom: 12px; }
          .empty         { color: #555; text-align: center; padding: 24px 0; }
        </style>
        </head><body>
        <div class='thread-header'>
          <div class='thread-title'>\(htmlEscape(threadTitle))</div>
          <div class='meta-row'>
            <img class='avatar' src='\(avatarURL)' onerror="this.style.display='none'"/>
            <span class='username'>\(htmlEscape(userName))</span>
            <span class='meta'>\(timeAgo)</span>
            \(lockedBadge)
          </div>
          <div class='stats'>
            <span>\(lucideSVG("heart")) \(likes) likes</span>
            <span>\(lucideSVG("eye")) \(views) views</span>
            <span>\(lucideSVG("messages-square")) \(replies) replies</span>
          </div>
        </div>
        <div class='thread-body'>\(body)</div>
        <hr class='divider'/>
        <div class='comments-title'>Comments (\(comments.count))</div>
        \(commentsHTML)
        \(noComments)
        </body></html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: "https://anilist.co"))
    }

    // MARK: - Error
    private func showError() {
        spinner.stopAnimating()
        let html = """
        <!DOCTYPE html><html><body style='background:#0a0a0a;color:#888;
        display:flex;align-items:center;justify-content:center;height:100vh;
        font-family:-apple-system,sans-serif;font-size:14px;text-align:center;'>
        <p>Failed to load thread.<br>Check your connection and try again.</p>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - Helpers
    private func sinceString(_ ts: TimeInterval) -> String {
        guard ts > 0 else { return "" }
        let diff = Date().timeIntervalSince1970 - ts
        switch diff {
        case ..<60:      return "just now"
        case ..<3600:    return "\(Int(diff/60))m ago"
        case ..<86400:   return "\(Int(diff/3600))h ago"
        case ..<2592000: return "\(Int(diff/86400))d ago"
        default:         return "\(Int(diff/2592000))mo ago"
        }
    }

    private func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func lucideSVG(_ id: String) -> String {
        let path: String
        switch id {
        case "eye":
            path = "<path d='M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0'/><circle cx='12' cy='12' r='3'/>"
        case "lock":
            path = "<rect width='18' height='11' x='3' y='11' rx='2' ry='2'/><path d='M7 11V7a5 5 0 0 1 10 0v4'/>"
        case "messages-square":
            path = "<path d='M14 9a2 2 0 0 1-2 2H6l-4 4V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2z'/><path d='M18 9h2a2 2 0 0 1 2 2v11l-4-4h-6a2 2 0 0 1-2-2v-1'/>"
        default:
            path = "<path d='M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.29 1.51 4.04 3 5.5l7 7z'/>"
        }
        return "<svg class='icon' viewBox='0 0 24 24' aria-hidden='true'>\(path)</svg>"
    }
}
