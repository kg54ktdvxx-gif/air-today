#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Noise functions

/// Simple hash for pseudo-random values.
float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.13);
    p3 += dot(p3, p3.yzx + 3.333);
    return fract((p3.x + p3.y) * p3.z);
}

/// 2D value noise.
float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);  // Smoothstep

    float a = hash(i);
    float b = hash(i + float2(1, 0));
    float c = hash(i + float2(0, 1));
    float d = hash(i + float2(1, 1));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

/// Fractal Brownian Motion — layered noise for organic cloud textures.
/// 3 octaves for performance (half precision where possible).
float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }

    return value;
}

// MARK: - Haze Overlay

/// Atmospheric haze shader — slow-drifting noise clouds tinted by AQI.
/// Applied as .colorEffect() on a clear rectangle overlaying the content.
///
/// Parameters (after auto-injected position, color):
///   time: elapsed seconds
///   aqiDensity: 0.0 (clear) to 1.0 (thick haze)
///   viewSize: view dimensions
[[ stitchable ]] half4 hazeOverlay(
    float2 position,
    half4 color,
    float time,
    float aqiDensity,
    float2 viewSize
) {
    // Normalize to 0..1 UV coordinates
    float2 uv = position / viewSize;

    // Slow-drifting noise at 3 octaves
    float2 noiseCoord = uv * 3.0 + float2(time * 0.04, time * 0.02);
    float n = fbm(noiseCoord, 3);

    // Second noise layer at different scale for depth
    float n2 = fbm(uv * 5.0 + float2(-time * 0.03, time * 0.05), 3);
    float combined = mix(n, n2, 0.4);

    // Haze color: warm amber at low density, gray-purple at high
    half3 warmHaze = half3(0.9h, 0.75h, 0.5h);
    half3 coldHaze = half3(0.5h, 0.4h, 0.5h);
    half3 hazeColor = mix(warmHaze, coldHaze, half(aqiDensity));

    // Intensity: exponential falloff from edges + noise modulation
    float edgeFade = smoothstep(0.0, 0.3, uv.y) * smoothstep(1.0, 0.7, uv.y);
    float intensity = combined * float(aqiDensity) * 0.5 * edgeFade;

    // Blend haze over the existing content
    half4 hazePixel = half4(hazeColor, half(intensity));
    return mix(color, hazePixel, half(intensity));
}

// MARK: - Color Grade

/// Global color grading — desaturates and warm-shifts for poor air quality.
/// Applied as .colorEffect() on the entire ZStack.
///
/// Parameters:
///   saturation: 0.0 (grayscale) to 1.0 (full color)
///   warmth: 0.0 (neutral) to 1.0 (amber shift)
[[ stitchable ]] half4 colorGrade(
    float2 position,
    half4 color,
    float saturation,
    float warmth
) {
    // Luminance (perceptual weights)
    half luma = dot(color.rgb, half3(0.2126h, 0.7152h, 0.0722h));

    // Desaturate
    half3 desaturated = mix(half3(luma), color.rgb, half(saturation));

    // Warm shift (add amber tint proportional to warmth)
    half3 warmed = desaturated + half3(warmth * 0.15h, warmth * 0.05h, -warmth * 0.10h);

    return half4(clamp(warmed, 0.0h, 1.0h), color.a);
}
