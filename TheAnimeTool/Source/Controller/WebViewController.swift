//
//  WebViewController.swift — Full-screen WKWebView loading the bundled Svelte webapp.
//
import UIKit
import WebKit

final class WebViewController: UIViewController {

    private var webView: WKWebView!
    private let bridge = NativeBridge()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupWebView()
        loadWebApp()
    }

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()

        // Register the native bridge message handler
        config.userContentController.add(bridge, name: "bridge")

        // Allow file:// → https:// cross-origin reads (needed for bundled webapp → AniList API)
        config.allowsInlineMediaPlayback = true
        if #available(iOS 14, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.uiDelegate = self
        webView.navigationDelegate = self

        // Pass reference to bridge so it can call back into JS
        bridge.webView = webView

        view.addSubview(webView)
    }

    private func loadWebApp() {
        // Try to load the compiled webapp from the app bundle
        if let webAppDir = Bundle.main.url(forResource: "webapp", withExtension: nil),
           let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "webapp") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: webAppDir)
        } else {
            // Fallback: show error page
            let html = """
            <!DOCTYPE html><html><body style="background:#000;color:#fff;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
            <div style="text-align:center"><h2>⚠️ App Not Built</h2><p>Run <code>npm run build</code> in the WebApp directory.</p></div>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

// MARK: - WKUIDelegate

extension WebViewController: WKUIDelegate {
    // Allow alert() dialogs from JS
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
}

// MARK: - WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[WebViewController] Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Block external navigation, open in Safari instead
        if let url = navigationAction.request.url,
           navigationAction.navigationType == .linkActivated,
           (url.scheme == "http" || url.scheme == "https") {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
