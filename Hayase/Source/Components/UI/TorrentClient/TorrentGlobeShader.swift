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
