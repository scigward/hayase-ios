//
//  Globe.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit
import SwiftUI
import CobeKit
import simd

final class Globe: UIView {
    private let markerQueue = DispatchQueue(label: "app.hayase.torrentclient.globe.markers", qos: .utility)
    private let model: NativeGlobeModel
    private let hostingController: UIHostingController<NativeGlobeContentView>
    private var currentSize: CGFloat = NativeGlobeStyle.compactSize
    private var markerGeneration = 0
    private var displayLink: CADisplayLink?
    private let animationStartTime = CACurrentMediaTime()

    override init(frame: CGRect) {
        let model = NativeGlobeModel()
        self.model = model
        self.hostingController = UIHostingController(rootView: NativeGlobeContentView(model: model))
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        let model = NativeGlobeModel()
        self.model = model
        self.hostingController = UIHostingController(rootView: NativeGlobeContentView(model: model))
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        let hostedView = hostingController.view!
        hostedView.backgroundColor = .clear
        hostedView.isOpaque = false
        hostedView.isUserInteractionEnabled = false
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostedView)

        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    deinit {
        stopAnimating()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopAnimating()
        } else {
            startAnimating()
        }
    }

    private func startAnimating() {
        guard displayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(updateAnimationFrame))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func stopAnimating() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateAnimationFrame() {
        let elapsed = Float(CACurrentMediaTime() - animationStartTime)
        model.setPhi((elapsed * NativeGlobeStyle.rotationSpeed).truncatingRemainder(dividingBy: Float.pi * 2))
    }

    func setViewportWidth(_ width: CGFloat) {
        let size: CGFloat = width >= 1920 ? NativeGlobeStyle.expandedSize : NativeGlobeStyle.compactSize
        guard currentSize != size else { return }
        currentSize = size
        model.setSize(size)
    }

    func setPeers(_ rows: [TorrentClientPeerRow]) {
        markerGeneration += 1
        let generation = markerGeneration
        markerQueue.async { [weak self] in
            let markers = Self.markers(for: rows)
            DispatchQueue.main.async {
                guard let self, self.markerGeneration == generation else { return }
                self.model.setMarkers(markers)
            }
        }
    }

    private static func markers(for rows: [TorrentClientPeerRow]) -> [CobeKit.GlobeMarker] {
        let picked = rows
            .sorted { $0.totalSpeed > $1.totalSpeed }
            .prefix(NativeGlobeStyle.maxMarkers)

        let speeds = picked.map { Double($0.totalSpeed) }
        let lowestSpeed = speeds.min() ?? 0
        let highestSpeed = speeds.max() ?? 0

        return picked.compactMap { row in
            guard let geoLocation = TorrentClientGeoIP.shared.lookup(row.ip) else { return nil }
            var location = geoLocation.coordinate
            if geoLocation.city.isEmpty {
                location.latitude += Double.random(in: -2...2)
                location.longitude += Double.random(in: -2...2)
            }

            let normalized = Self.normalize(Double(row.totalSpeed), max: highestSpeed, min: lowestSpeed)
            let markerSize = min(max(Float(normalized) * 0.05, 0.02), 0.05)
            let color = row.isSeeder ? NativeGlobeStyle.seederColor : NativeGlobeStyle.leecherColor
            return CobeKit.GlobeMarker(
                location: SIMD2<Float>(Float(location.latitude), Float(location.longitude)),
                size: markerSize,
                color: color
            )
        }
    }

    private static func normalize(_ value: Double, max: Double, min: Double) -> Double {
        let denominator = max - min
        guard denominator != 0 else { return 0 }
        return (value - min) / denominator
    }
}

private enum NativeGlobeStyle {
    static let compactSize: CGFloat = 400
    static let expandedSize: CGFloat = 600
    static let maxMarkers = 64

    static let theta: Float = 0.1
    static let dark: Float = 1
    static let diffuse: Float = 1.4
    static let mapSamples: Float = 19_000
    static let mapBrightness: Float = 6
    static let mapBaseBrightness: Float = 0
    static let opacity: Float = 0.8
    static let scale: Float = 1.5
    static let rotationSpeed: Float = 0.2

    static let baseColor = SIMD3<Float>(0.23, 0.23, 0.23)
    static let markerColor = SIMD3<Float>(1, 1, 1)
    static let glowColor = SIMD3<Float>(0, 0, 0)
    static let seederColor = SIMD3<Float>(0.05, 1.0, 0.0)
    static let leecherColor = SIMD3<Float>(0.01, 0.37, 0.94)

    static func offset(for size: CGFloat) -> SIMD2<Float> {
        let size = Float(size)
        return SIMD2<Float>(
            size * 0.8 / scale,
            size * 0.4 / scale
        )
    }
}

private final class NativeGlobeModel: ObservableObject {
    @Published private(set) var configuration: GlobeConfiguration
    private var size = NativeGlobeStyle.compactSize

    init() {
        var configuration = GlobeConfiguration()
        configuration.theta = NativeGlobeStyle.theta
        configuration.dark = NativeGlobeStyle.dark
        configuration.diffuse = NativeGlobeStyle.diffuse
        configuration.mapSamples = NativeGlobeStyle.mapSamples
        configuration.mapBrightness = NativeGlobeStyle.mapBrightness
        configuration.mapBaseBrightness = NativeGlobeStyle.mapBaseBrightness
        configuration.opacity = NativeGlobeStyle.opacity
        configuration.baseColor = NativeGlobeStyle.baseColor
        configuration.markerColor = NativeGlobeStyle.markerColor
        configuration.glowColor = NativeGlobeStyle.glowColor
        configuration.scale = NativeGlobeStyle.scale
        configuration.offset = NativeGlobeStyle.offset(for: size)
        configuration.dragEnabled = false
        configuration.autoRotateSpeed = 0
        self.configuration = configuration
    }

    func setPhi(_ phi: Float) {
        updateConfiguration { configuration in
            configuration.phi = phi
        }
    }

    func setSize(_ size: CGFloat) {
        guard self.size != size else { return }
        self.size = size
        updateConfiguration { configuration in
            configuration.offset = NativeGlobeStyle.offset(for: size)
        }
    }

    func setMarkers(_ markers: [CobeKit.GlobeMarker]) {
        updateConfiguration { configuration in
            configuration.markers = markers
        }
    }

    private func updateConfiguration(_ body: (inout GlobeConfiguration) -> Void) {
        var next = configuration
        body(&next)
        configuration = next
    }
}

private struct NativeGlobeContentView: View {
    @ObservedObject var model: NativeGlobeModel

    var body: some View {
        GlobeView(configuration: Binding(
            get: { model.configuration },
            set: { _ in }
        ))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .background(Color.clear)
    }
}
