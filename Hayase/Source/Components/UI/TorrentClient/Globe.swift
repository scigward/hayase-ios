//
//  Globe.swift
//  Hayase
//

import UIKit
import MetalKit
import simd

/// Native renderer for the cobe fork pinned by interface. Markers share the
/// globe's lattice, rotation, scale and offset, rather than separate flat quads.
final class Globe: UIView {
    private let markerQueue = DispatchQueue(label: "app.hayase.torrentclient.globe.markers", qos: .utility)
    private var metalView: MTKView?
    private var renderer: TorrentGlobeRenderer?
    private var currentSize: CGFloat = 400
    private var markerGeneration = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let view = MTKView(frame: bounds, device: device)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = true
        do {
            let renderer = try TorrentGlobeRenderer(device: device, pixelFormat: view.colorPixelFormat)
            view.delegate = renderer
            self.renderer = renderer
            metalView = view
            addSubview(view)
        } catch {
            // interface also leaves the decorative canvas empty on setup failure.
            NSLog("[TorrentClient] Failed to create globe: %@", error.localizedDescription)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let screen = window?.screen {
            metalView?.contentScaleFactor = screen.scale
            metalView?.preferredFramesPerSecond = screen.maximumFramesPerSecond
        }
        metalView?.isPaused = window == nil
    }

    func setViewportWidth(_ width: CGFloat) {
        let size: CGFloat = width >= 1920 ? 600 : 400
        guard currentSize != size else { return }
        currentSize = size
        setNeedsLayout()
    }

    func setPeers(_ rows: [TorrentClientPeerRow]) {
        markerGeneration += 1
        let generation = markerGeneration
        markerQueue.async { [weak self] in
            let markers = Self.markers(for: rows)
            DispatchQueue.main.async {
                guard let self, self.markerGeneration == generation else { return }
                self.renderer?.setMarkers(markers)
            }
        }
    }

    private static func markers(for rows: [TorrentClientPeerRow]) -> [TorrentGlobeMarker] {
        let picked = rows.sorted { $0.totalSpeed > $1.totalSpeed }.prefix(64)
        let speeds = picked.map { Double($0.totalSpeed) }
        let lowestSpeed = speeds.min() ?? 0
        let highestSpeed = speeds.max() ?? 0
        let range = highestSpeed - lowestSpeed
        return picked.compactMap { row in
            guard let geoLocation = TorrentClientGeoIP.shared.lookup(row.ip) else { return nil }
            var location = geoLocation.coordinate
            if geoLocation.city.isEmpty {
                location.latitude += Double.random(in: -2...2)
                location.longitude += Double.random(in: -2...2)
            }
            let normalized = range == 0 ? 0 : (Double(row.totalSpeed) - lowestSpeed) / range
            let size = min(max(Float(normalized) * 0.05, 0.02), 0.05)
            let color = row.isSeeder ? SIMD3<Float>(0.05, 1, 0) : SIMD3<Float>(0.01, 0.37, 0.94)
            return TorrentGlobeMarker(latitude: location.latitude, longitude: location.longitude, size: size, color: color)
        }
    }
}

private struct TorrentGlobeMarker {
    let latitude: Double
    let longitude: Double
    let size: Float
    let color: SIMD3<Float>
}

private struct TorrentGlobeUniforms {
    // Two float4s avoid Swift/Metal float3 structure-padding differences.
    var resolutionAndOffset: SIMD4<Float>
    var animationAndPixelScale: SIMD4<Float>
}

private final class TorrentGlobeRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let texture: MTLTexture
    private let sampler: MTLSamplerState
    private var markerData = [SIMD4<Float>](repeating: .zero, count: 128)
    private var markerCount = 0

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        guard let commandQueue = device.makeCommandQueue(),
              let textureData = Data(base64Encoded: TorrentGlobeShader.mapTexture) else {
            throw NSError(domain: "TorrentGlobe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Globe renderer resources are unavailable."])
        }
        self.commandQueue = commandQueue
        let library = try device.makeLibrary(source: TorrentGlobeShader.source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "torrentGlobeVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "torrentGlobeFragment")
        guard let attachment = descriptor.colorAttachments[0] else {
            throw NSError(domain: "TorrentGlobe", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Globe renderer resources are unavailable."])
        }
        attachment.pixelFormat = pixelFormat
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        texture = try MTKTextureLoader(device: device).newTexture(data: textureData, options: [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft.rawValue,
            .generateMipmaps: false,
        ])
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw NSError(domain: "TorrentGlobe", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Globe texture sampling is unavailable."])
        }
        self.sampler = sampler
        super.init()
    }

    func setMarkers(_ markers: [TorrentGlobeMarker]) {
        markerCount = min(markers.count, 64)
        for (index, marker) in markers.prefix(64).enumerated() {
            let latitude = marker.latitude * Double.pi / 180
            let longitude = marker.longitude * Double.pi / 180 - Double.pi
            let cosLatitude = cos(latitude)
            let position = SIMD3<Double>(-cosLatitude * cos(longitude), sin(latitude), cosLatitude * sin(longitude))
            let lattice = Self.nearestLattice(to: position)
            markerData[index * 2] = SIMD4<Float>(Float(lattice.x), Float(lattice.y), Float(lattice.z), marker.size)
            markerData[index * 2 + 1] = SIMD4<Float>(marker.color.x, marker.color.y, marker.color.z, 1)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard view.bounds.width > 0, view.bounds.height > 0,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let width = Float(view.bounds.width)
        let height = Float(view.bounds.height)
        // Match Date.now() * .0002 without losing subsecond rotation in Float.
        let phi = Float((Date().timeIntervalSince1970 * 0.2).truncatingRemainder(dividingBy: Double.pi * 2))
        var uniforms = TorrentGlobeUniforms(
            resolutionAndOffset: SIMD4<Float>(width, height, width * 0.8 / 1.5, height * 0.4 / 1.5),
            animationAndPixelScale: SIMD4<Float>(phi, Float(markerCount), Float(view.drawableSize.width) / width,
                                               Float(view.drawableSize.height) / height)
        )
        encoder.setRenderPipelineState(pipeline)
        withUnsafePointer(to: &uniforms) {
            encoder.setFragmentBytes($0, length: MemoryLayout<TorrentGlobeUniforms>.stride, index: 0)
        }
        markerData.withUnsafeBufferPointer {
            guard let baseAddress = $0.baseAddress else { return }
            encoder.setFragmentBytes(baseAddress, length: $0.count * MemoryLayout<SIMD4<Float>>.stride, index: 1)
        }
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// CPU lattice lookup from thaunknown/cobe's mapMarkers. Evaluated only
    /// when the peer snapshot changes, not for every animation frame.
    private static func nearestLattice(to position: SIMD3<Double>) -> SIMD3<Double> {
        let dots = 19_000.0
        let root5 = 2.23606797749979
        let golden = 1.618033988749895
        let goldenMinusOne = 0.618033988749895
        let tau = Double.pi * 2
        let p = SIMD3<Double>(position.x, position.z, position.y)
        let k = max(2, floor(log2(root5 * dots * Double.pi * max(0, 1 - p.z * p.z)) * 0.7202100452062783))
        let pk = pow(golden, k) / root5
        let f = SIMD2<Double>(floor(pk + 0.5), floor(pk * golden + 0.5))
        let a = SIMD2<Double>(((f.x + 1) * goldenMinusOne).truncatingRemainder(dividingBy: 1) * tau - 3.8832220774509327,
                             ((f.y + 1) * goldenMinusOne).truncatingRemainder(dividingBy: 1) * tau - 3.8832220774509327)
        let b = -2 * f
        let sp = SIMD2<Double>(atan2(p.y, p.x), p.z - 1)
        let determinant = a.x * b.y - b.x * a.y
        let c = SIMD2<Double>(floor((b.y * sp.x - a.y * (sp.y * dots + 1)) / determinant),
                             floor((-b.x * sp.x + a.x * (sp.y * dots + 1)) / determinant))
        var distance = Double.pi
        var nearest = SIMD3<Double>.zero
        for candidate in 0..<4 {
            let offset = SIMD2<Double>(Double(candidate % 2), Double(candidate / 2))
            let index = simd_dot(f, c + offset)
            guard index >= 0, index <= dots else { continue }
            let theta = (index * goldenMinusOne).truncatingRemainder(dividingBy: 1) * tau
            let cosPhi = 1 - 2 * index / dots
            let sinPhi = sqrt(max(0, 1 - cosPhi * cosPhi))
            let sample = SIMD3<Double>(cos(theta) * sinPhi, sin(theta) * sinPhi, cosPhi)
            let sampleDistance = simd_length(p - sample)
            if sampleDistance < distance {
                distance = sampleDistance
                nearest = sample
            }
        }
        return SIMD3<Double>(nearest.x, nearest.z, nearest.y)
    }
}
