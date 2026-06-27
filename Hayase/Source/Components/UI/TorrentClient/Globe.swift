//
//  Globe.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit
import WebKit

final class Globe: UIView {
    private let webView: WKWebView
    private let markerQueue = DispatchQueue(label: "app.hayase.torrentclient.globe.markers", qos: .utility)
    private var isLoaded = false
    private var pendingMarkersJSON: String?
    private var pendingSize: CGFloat = 400
    private var markerGeneration = 0

    override init(frame: CGRect) {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        configuration.suppressesIncrementalRendering = false
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        configuration.suppressesIncrementalRendering = false
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        alpha = 0.8

        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        loadRenderer()
    }

    func setViewportWidth(_ width: CGFloat) {
        let size: CGFloat = width >= 1920 ? 600 : 400
        guard pendingSize != size else { return }
        pendingSize = size
        evaluate("window.HayaseGlobe?.setSize(\(Int(size)))")
    }

    func setPeers(_ rows: [TorrentClientPeerRow]) {
        markerGeneration += 1
        let generation = markerGeneration
        markerQueue.async { [weak self] in
            guard let json = Self.markersJSON(for: rows) else { return }
            DispatchQueue.main.async {
                guard let self, self.markerGeneration == generation else { return }
                self.pendingMarkersJSON = json
                self.evaluate("window.HayaseGlobe?.setMarkers(\(json))")
            }
        }
    }

    private static func markersJSON(for rows: [TorrentClientPeerRow]) -> String? {
        let picked = rows
            .sorted { $0.totalSpeed > $1.totalSpeed }
            .prefix(64)

        let speeds = picked.map { Double($0.totalSpeed) }
        let lowestSpeed = speeds.min() ?? 0
        let highestSpeed = speeds.max() ?? 0

        let markers: [[String: Any]] = picked.compactMap { row in
            guard let geoLocation = TorrentClientGeoIP.shared.lookup(row.ip) else { return nil }
            var location = geoLocation.coordinate
            if geoLocation.city.isEmpty {
                location.latitude += Double.random(in: -2...2)
                location.longitude += Double.random(in: -2...2)
            }

            let normalized = Self.normalize(Double(row.totalSpeed), max: highestSpeed, min: lowestSpeed)
            let markerSize = min(max(normalized * 0.05, 0.02), 0.05)
            let color = row.isSeeder ? [0.05, 1.0, 0.0] : [0.01, 0.37, 0.94]

            return [
                "location": [location.latitude, location.longitude],
                "size": markerSize,
                "color": color,
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: markers) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func normalize(_ value: Double, max: Double, min: Double) -> Double {
        let denominator = max - min
        guard denominator != 0 else { return 0 }
        return (value - min) / denominator
    }

    private func loadRenderer() {
        guard let htmlURL = Bundle.main.url(forResource: "globe",
                                            withExtension: "html",
                                            subdirectory: "TorrentClientGlobe")
            ?? Bundle.main.url(forResource: "globe", withExtension: "html") else {
            isHidden = true
            return
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    private func evaluate(_ script: String) {
        guard isLoaded else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func flushPendingState() {
        evaluate("window.HayaseGlobe?.setSize(\(Int(pendingSize)))")
        if let pendingMarkersJSON {
            evaluate("window.HayaseGlobe?.setMarkers(\(pendingMarkersJSON))")
        }
    }
}

extension Globe: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        flushPendingState()
    }
}
