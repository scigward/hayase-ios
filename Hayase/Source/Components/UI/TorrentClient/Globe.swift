//
//  Globe.swift
//  Hayase
//

import MetalKit
import UIKit
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

// MARK: - TorrentGlobeShader

// Shader and map adapted from thaunknown/cobe, the interface dependency pinned
// at 9687dd14ad06894e28781d170ef9c98aa5d03d9c.
//
// MIT License
// Copyright (c) 2021 Shu Ding
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

enum TorrentGlobeShader {
    static let mapTexture = "iVBORw0KGgoAAAANSUhEUgAAAQAAAACAAQAAAADMzoqnAAAAAXNSR0IArs4c6QAABA5JREFUeNrV179uHEUAx/Hf3JpbF+E2VASBsmVKTBcpKJs3SMEDcDwBiVJAAewYEBUivIHT0uUBIt0YCovKD0CRjUC4QfHYh8hYXu+P25vZ2Zm9c66gMd/GJ/tz82d3bk8GN4SrByYF2366FNTACIAkivVAAazQdnf3MvAlbNUQfOPAdQDvSAimMWhwy4I2g4SU+Kp04ISLpPBAKLxPyic3O/CCi+Y7rUJbiodcpDOFY7CgxCEXmdYD2EYK2s5lApOx5pEDDYCUwM1XdJUwBV11QQMg59kePSCaPAASQMEL2hwo6TJFgxpg+TgC2ymXPbuvc40awr3D1QCFfbH9kcoqAOkZozpQo0aqAGQRKCog/+tjkgbNFEtg2FffBvBGlSxHoAaAa1u6X4PBAwDiR8FFsrQgeUhfJTSALaB9jy5NCybJPn1SVFiWk7ywN+KzhH1aKAuydhGkbEF4lWohLXDXavlyFgHY7LBnLRdlAP6BS5Cc8RfVDXbkwN/oIvmY+6obbNeBP0JwTuMGu9gTzy1Q4RS/cWpfzszeYwd+CAFrtBW/Hur0gLbJGlD+/OjVwe/drfBxkbbg63dndEDfiEBlAd7ac0BPe1D6Jd8dfbLH+RI0OzseFB5s01/M+gMdAeluLOCAuaUA9Lezo/vSgXoCX9rtEiXnp7Q1W/CNyWcd8DXoS6jH/YZ5vAJEWY2dXFQe2TUgaFaNejCzJ98g6HnlVrsE58sDcYqg+9XY75fPqdoh/kRQWiXKg8MWlJQxUFMPjqnyujhFBE7UxIMjyszk0QwQlFsezImsyvUYYYVED2pk6m0Tg8T04Fwjk2kdAwSACqlM6gRRt3vQYAFGX0Ah7Ebx1H+MDRI5ui0QldH4j7FGcm90XdxD2Jg1AOEAVAKhEFXSn4cKUELurIAKwJ3MArypPscQaLhJFICJ0ohjDySAdH8AhDtCiTuMycH8CXzhH9jUACAO5uMhoAwA5i+T6WAKmmAqnLy80wxHqIPFYpqCwxGaYLt4Dyievg5kEoVEUAhs6pqKgFtDQYOuaXypaWKQfIuwwoGSZgfLsu/XAtI8cGN+h7Cc1A5oLOMhwlIPXuhu48AIvsSBkvtV9wsJRKCyYLfq5lTrQMFd1a262oqBck9K1V0YjQg0iEYYgpS1A9GlXQV5cykwm4A7BzVsxQqo7E+zCegO7Ma7yKgsuOcfKbMBwLC8wvVNYDsANYalEpOAa6zpWjTeMKGwEwC1CiQewJc5EKfgy7GmRAZA4vUVGwE2dPM/g0xuAInE/yG5aZ8ISxWGfYigUVbdyBElTHh2uCwGdfCkOLGgQVBh3Ewp+/QK4CDlR5Ws/Zf7yhCf8pH7vinWAvoVCQ6zz0NX5V/6GkAVV+2/5qsJ/gU8bsxpM8IeAQAAAABJRU5ErkJggg=="

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct GlobeUniforms {
        float4 resolutionAndOffset;
        float4 animationAndPixelScale;
    };
    struct GlobeVertex {
        float4 position [[position]];
    };

    constant float root5 = 2.23606797749979;
    constant float pi = 3.141592653589793;
    constant float tau = 6.283185307179586;
    constant float golden = 1.618033988749895;
    constant float logFactor = 0.7202100452062783;
    constant float tauOverGolden = 3.8832220774509327;
    constant float goldenMinusOne = 0.618033988749895;
    constant float dots = 19000;
    constant float bitValues[20] = {
        524288, 262144, 131072, 65536, 32768, 16384, 8192, 4096, 2048, 1024,
        512, 256, 128, 64, 32, 16, 8, 4, 2, 1
    };
    constant float bitFractions[20] = {
        0.8038937048986554, 0.9019468524493277, 0.9509734262246639,
        0.4754867131123319, 0.737743356556166, 0.868871678278083,
        0.9344358391390415, 0.46721791956952075, 0.7336089597847604,
        0.8668044798923802, 0.4334022399461901, 0.21670111997309505,
        0.10835055998654752, 0.5541752799932738, 0.7770876399966369,
        0.8885438199983184, 0.9442719099991592, 0.4721359549995796,
        0.2360679774997898, 0.6180339887498949
    };

    float3x3 globeRotation(float theta, float phi) {
        float cx = cos(theta), cy = cos(phi);
        float sx = sin(theta), sy = sin(phi);
        return float3x3(
            float3(cy, sy * sx, -sy * cx),
            float3(0, cx, sx),
            float3(sy, -cy * sx, cy * cx)
        );
    }

    float3 nearestGlobeLattice(float3 p, thread float &distance) {
        p = p.xzy;
        float k = max(2.0f, floor(log2(root5 * dots * pi * (1 - p.z * p.z)) * logFactor));
        float2 f = floor(pow(golden, k) / root5 * float2(1, golden) + 0.5f);
        float2 br1 = fract((f + 1) * goldenMinusOne) * tau - tauOverGolden;
        float2 br2 = -2 * f;
        float2 sp = float2(atan2(p.y, p.x), p.z - 1);
        float2 c = floor(float2(
            br2.y * sp.x - br1.y * (sp.y * dots + 1),
            -br2.x * sp.x + br1.x * (sp.y * dots + 1)
        ) / (br1.x * br2.y - br2.x * br1.y));

        distance = pi;
        float3 nearest = float3(0);
        for (int candidate = 0; candidate < 4; ++candidate) {
            float2 o = float2(candidate % 2, candidate / 2);
            float index = dot(f, c + o);
            if (index < 0 || index > dots) continue;
            // Keep the upstream high-precision modular decomposition. A direct
            // index/golden fract produces visible lattice errors in float32.
            float remaining = index, fraction = 0;
            for (int bit = 0; bit < 20; ++bit) {
                if (remaining >= bitValues[bit]) {
                    remaining -= bitValues[bit];
                    fraction += bitFractions[bit];
                }
            }
            float theta = fract(fraction) * tau;
            float cosPhi = 1 - 2 * index / dots;
            float sinPhi = sqrt(max(0.0f, 1 - cosPhi * cosPhi));
            float3 samplePoint = float3(cos(theta) * sinPhi, sin(theta) * sinPhi, cosPhi);
            float sampleDistance = length(p - samplePoint);
            if (sampleDistance < distance) {
                distance = sampleDistance;
                nearest = samplePoint;
            }
        }
        return nearest.xzy;
    }

    vertex GlobeVertex torrentGlobeVertex(uint index [[vertex_id]]) {
        const float2 positions[3] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
        GlobeVertex output;
        output.position = float4(positions[index], 0, 1);
        return output;
    }

    fragment float4 torrentGlobeFragment(
        GlobeVertex input [[stage_in]],
        constant GlobeUniforms &uniforms [[buffer(0)]],
        constant float4 *markers [[buffer(1)]],
        texture2d<float> map [[texture(0)]],
        sampler mapSampler [[sampler(0)]]
    ) {
        float2 resolution = uniforms.resolutionAndOffset.xy;
        float2 offset = uniforms.resolutionAndOffset.zw;
        float2 pixelScale = uniforms.animationAndPixelScale.zw;
        // Metal fragment coordinates start at the top left; WebGL's start at
        // the bottom left. Normalize Retina pixels into the CSS-point units
        // used by interface's resolution and offset.
        float2 coordinate = input.position.xy / pixelScale;
        coordinate.y = resolution.y - coordinate.y;
        float2 invResolution = 1 / resolution;
        float2 uv = (coordinate * invResolution * 2 - 1) / 1.5f
                  - offset * float2(1, -1) * invResolution;
        uv.x *= resolution.x * invResolution.y;
        float l = dot(uv, uv);
        float4 color = float4(0);
        float glowFactor = 0;
        const float3 baseColor = float3(0.23f);
        const float3 markerColor = float3(1);
        const float3 glowColor = float3(0);

        if (l <= 0.64f) {
            float distance;
            float3 p = normalize(float3(uv, sqrt(0.64f - l)));
            float dotNL = p.z;
            float3 rotated = p * globeRotation(0.1f, uniforms.animationAndPixelScale.x);
            float3 lattice = nearestGlobeLattice(rotated, distance);
            float latitude = asin(clamp(lattice.y, -1.0f, 1.0f));
            float longitude = acos(clamp(-lattice.x / cos(latitude), -1.0f, 1.0f));
            if (lattice.z < 0) longitude = -longitude;
            float mapColor = map.sample(mapSampler, float2(longitude * 0.5f / pi, -(latitude / pi + 0.5f))).r;
            // Equivalent to upstream smoothstep(.008, 0, distance), without
            // relying on the undefined reversed-edge case in Metal.
            float v = 1 - smoothstep(0.0f, 0.008f, distance);
            float lighting = pow(dotNL, 1.4f) * 6;
            float sampled = mapColor * v * lighting;
            float colorFactor = mix((1 - sampled) * pow(dotNL, 0.4f), sampled, 1.0f) + 0.1f;
            float4 layer = float4(baseColor * colorFactor, 1);

            float largestSize = 0, markerAlpha = 0;
            float3 accumulatedMarkerColor = float3(0);
            // Each marker has TWO float4s. Count markers, not uniform vectors;
            // do not reproduce the fork's onRender half-marker-count bug.
            int count = min(int(uniforms.animationAndPixelScale.y), 64);
            for (int index = 0; index < count; ++index) {
                float4 marker = markers[index * 2];
                float4 markerColorData = markers[index * 2 + 1];
                distance = length(marker.xyz - rotated);
                if (distance < marker.w && marker.w > largestSize) {
                    float strength = 1 - smoothstep(0.0f, marker.w * 0.5f, distance);
                    largestSize = marker.w;
                    markerAlpha = strength * lighting;
                    accumulatedMarkerColor = markerColorData.w > 0.5f ? markerColorData.xyz : markerColor;
                }
            }
            layer.xyz = mix(layer.xyz, accumulatedMarkerColor, min(markerAlpha, 1.0f));
            layer.xyz += pow(1 - dotNL, 4.0f) * glowColor;
            color += layer * 0.9f; // (1 + opacity .8) * .5
            glowFactor = pow(sqrt(1 - l), 4.0f) * smoothstep(0.0f, 1.0f, 0.2f / (l - 0.64f));
        } else {
            float outD = sqrt(0.2f / (l - 0.64f));
            glowFactor = smoothstep(0.5f, 1.0f, outD / (outD + 1));
        }
        return color + float4(glowFactor * glowColor, glowFactor);
    }
    """
}
