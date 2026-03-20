import SwiftUI

// MARK: - Particle Configuration

/// Parameters controlling the particle system's appearance and behavior per AQI level.
public struct ParticleConfig: Equatable, Sendable {
    public let birthRate: Double
    public let maxParticles: Int
    public let minSpeed: Double
    public let maxSpeed: Double
    public let minSize: CGFloat
    public let maxSize: CGFloat
    public let minOpacity: Double
    public let maxOpacity: Double
    public let colorRed: Double
    public let colorGreen: Double
    public let colorBlue: Double
    public let wobbleAmount: Double

    public static let disabled = ParticleConfig(
        birthRate: 0, maxParticles: 0,
        minSpeed: 0, maxSpeed: 0,
        minSize: 0, maxSize: 0,
        minOpacity: 0, maxOpacity: 0,
        colorRed: 1, colorGreen: 1, colorBlue: 1,
        wobbleAmount: 0
    )
}

// MARK: - Atmosphere Parameters

/// Pure mapping from AQI data to visual atmosphere parameters.
/// Consumed by MeshGradient, Metal shaders, particle system, and spring animations.
public struct AtmosphereParameters: Equatable, Sendable {
    /// 9 colors for a 3×3 MeshGradient.
    public let meshColors: [Color]

    /// Haze density for Metal shader (0.0 = clear, 1.0 = thick fog).
    public let hazeDensity: Float

    /// Dominant haze tint color.
    public let hazeColor: Color

    /// Heat distortion amplitude (0.0 = none, only active at AQI 150+).
    public let distortionAmplitude: Float

    /// Global saturation multiplier (1.0 = vivid, 0.3 = desaturated).
    public let saturation: Double

    /// Warmth for colorGrade shader (0.0 = neutral, 1.0 = amber shift).
    public let warmth: Double

    /// Spring animation response time (lower = bouncier).
    public let springResponse: Double

    /// Spring damping fraction (lower = more bounce, 1.0 = overdamped).
    public let springDamping: Double

    /// Spring extra bounce (0.0-0.3 for clean air, 0.0 for polluted).
    public let springBounce: Double

    /// Particle system configuration.
    public let particleConfig: ParticleConfig

    public init(from quality: AirQuality) {
        let level = quality.level
        let normalizedAQI = Float(min(quality.aqi, 500)) / 500.0

        self.meshColors = Self.meshPalette(for: level)
        self.hazeDensity = Self.hazeDensity(for: normalizedAQI)
        self.hazeColor = Self.hazeColor(for: level)
        self.distortionAmplitude = quality.aqi > 150 ? Float(quality.aqi - 150) / 350.0 * 4.0 : 0.0
        self.saturation = Self.saturation(for: level)
        self.warmth = Self.warmth(for: level)
        self.springResponse = Self.springResponse(for: level)
        self.springDamping = Self.springDamping(for: level)
        self.springBounce = Self.springBounce(for: level)
        self.particleConfig = Self.particleConfig(for: level)
    }

    /// Default clean-air atmosphere for loading state.
    public static let placeholder = AtmosphereParameters(
        meshColors: meshPalette(for: .good),
        hazeDensity: 0.0,
        hazeColor: .clear,
        distortionAmplitude: 0.0,
        saturation: 1.0,
        warmth: 0.0,
        springResponse: 0.35,
        springDamping: 0.6,
        springBounce: 0.2,
        particleConfig: .disabled
    )

    private init(
        meshColors: [Color], hazeDensity: Float, hazeColor: Color,
        distortionAmplitude: Float, saturation: Double, warmth: Double,
        springResponse: Double, springDamping: Double, springBounce: Double,
        particleConfig: ParticleConfig
    ) {
        self.meshColors = meshColors
        self.hazeDensity = hazeDensity
        self.hazeColor = hazeColor
        self.distortionAmplitude = distortionAmplitude
        self.saturation = saturation
        self.warmth = warmth
        self.springResponse = springResponse
        self.springDamping = springDamping
        self.springBounce = springBounce
        self.particleConfig = particleConfig
    }

    // MARK: - Palette Mapping

    /// 9-color palette for 3×3 MeshGradient, per AQI level.
    private static func meshPalette(for level: AQILevel) -> [Color] {
        switch level {
        case .good:
            return [
                Color(.sRGB, red: 0.55, green: 0.88, blue: 0.96),
                Color(.sRGB, red: 0.40, green: 0.85, blue: 0.75),
                Color(.sRGB, red: 0.50, green: 0.80, blue: 0.95),
                Color(.sRGB, red: 0.30, green: 0.78, blue: 0.85),
                Color(.sRGB, red: 0.85, green: 0.96, blue: 0.98),
                Color(.sRGB, red: 0.45, green: 0.90, blue: 0.80),
                Color(.sRGB, red: 0.35, green: 0.70, blue: 0.90),
                Color(.sRGB, red: 0.50, green: 0.92, blue: 0.85),
                Color(.sRGB, red: 0.40, green: 0.82, blue: 0.92),
            ]
        case .moderate:
            return [
                Color(.sRGB, red: 0.65, green: 0.88, blue: 0.55),
                Color(.sRGB, red: 0.90, green: 0.90, blue: 0.40),
                Color(.sRGB, red: 0.50, green: 0.82, blue: 0.65),
                Color(.sRGB, red: 0.75, green: 0.85, blue: 0.45),
                Color(.sRGB, red: 0.95, green: 0.95, blue: 0.80),
                Color(.sRGB, red: 0.85, green: 0.88, blue: 0.50),
                Color(.sRGB, red: 0.55, green: 0.80, blue: 0.55),
                Color(.sRGB, red: 0.80, green: 0.90, blue: 0.60),
                Color(.sRGB, red: 0.70, green: 0.85, blue: 0.50),
            ]
        case .sensitive:
            return [
                Color(.sRGB, red: 0.95, green: 0.75, blue: 0.40),
                Color(.sRGB, red: 0.90, green: 0.65, blue: 0.30),
                Color(.sRGB, red: 0.85, green: 0.80, blue: 0.55),
                Color(.sRGB, red: 0.92, green: 0.70, blue: 0.35),
                Color(.sRGB, red: 0.88, green: 0.82, blue: 0.65),
                Color(.sRGB, red: 0.95, green: 0.72, blue: 0.42),
                Color(.sRGB, red: 0.80, green: 0.68, blue: 0.40),
                Color(.sRGB, red: 0.92, green: 0.78, blue: 0.50),
                Color(.sRGB, red: 0.88, green: 0.72, blue: 0.38),
            ]
        case .unhealthy:
            return [
                Color(.sRGB, red: 0.90, green: 0.35, blue: 0.25),
                Color(.sRGB, red: 0.85, green: 0.45, blue: 0.20),
                Color(.sRGB, red: 0.75, green: 0.40, blue: 0.30),
                Color(.sRGB, red: 0.80, green: 0.30, blue: 0.25),
                Color(.sRGB, red: 0.65, green: 0.45, blue: 0.40),
                Color(.sRGB, red: 0.88, green: 0.40, blue: 0.22),
                Color(.sRGB, red: 0.70, green: 0.35, blue: 0.30),
                Color(.sRGB, red: 0.82, green: 0.38, blue: 0.28),
                Color(.sRGB, red: 0.75, green: 0.32, blue: 0.22),
            ]
        case .veryUnhealthy:
            return [
                Color(.sRGB, red: 0.55, green: 0.20, blue: 0.50),
                Color(.sRGB, red: 0.65, green: 0.25, blue: 0.40),
                Color(.sRGB, red: 0.45, green: 0.25, blue: 0.45),
                Color(.sRGB, red: 0.50, green: 0.18, blue: 0.42),
                Color(.sRGB, red: 0.40, green: 0.30, blue: 0.38),
                Color(.sRGB, red: 0.58, green: 0.22, blue: 0.48),
                Color(.sRGB, red: 0.42, green: 0.20, blue: 0.40),
                Color(.sRGB, red: 0.52, green: 0.24, blue: 0.45),
                Color(.sRGB, red: 0.48, green: 0.22, blue: 0.42),
            ]
        case .hazardous:
            return [
                Color(.sRGB, red: 0.35, green: 0.08, blue: 0.12),
                Color(.sRGB, red: 0.25, green: 0.10, blue: 0.15),
                Color(.sRGB, red: 0.20, green: 0.15, blue: 0.18),
                Color(.sRGB, red: 0.30, green: 0.06, blue: 0.10),
                Color(.sRGB, red: 0.18, green: 0.12, blue: 0.14),
                Color(.sRGB, red: 0.32, green: 0.08, blue: 0.14),
                Color(.sRGB, red: 0.22, green: 0.10, blue: 0.12),
                Color(.sRGB, red: 0.28, green: 0.07, blue: 0.11),
                Color(.sRGB, red: 0.25, green: 0.09, blue: 0.13),
            ]
        }
    }

    // MARK: - Haze

    private static func hazeDensity(for normalizedAQI: Float) -> Float {
        return min(pow(normalizedAQI, 1.5) * 0.8, 0.8)
    }

    private static func hazeColor(for level: AQILevel) -> Color {
        switch level {
        case .good: .clear
        case .moderate: Color(.sRGB, red: 0.9, green: 0.85, blue: 0.6, opacity: 0.3)
        case .sensitive: Color(.sRGB, red: 0.9, green: 0.7, blue: 0.3, opacity: 0.5)
        case .unhealthy: Color(.sRGB, red: 0.85, green: 0.4, blue: 0.2, opacity: 0.6)
        case .veryUnhealthy: Color(.sRGB, red: 0.6, green: 0.2, blue: 0.5, opacity: 0.7)
        case .hazardous: Color(.sRGB, red: 0.4, green: 0.1, blue: 0.15, opacity: 0.8)
        }
    }

    // MARK: - Saturation & Warmth

    private static func saturation(for level: AQILevel) -> Double {
        switch level {
        case .good: 1.0
        case .moderate: 0.85
        case .sensitive: 0.7
        case .unhealthy: 0.55
        case .veryUnhealthy: 0.4
        case .hazardous: 0.3
        }
    }

    private static func warmth(for level: AQILevel) -> Double {
        switch level {
        case .good: 0.0
        case .moderate: 0.15
        case .sensitive: 0.35
        case .unhealthy: 0.55
        case .veryUnhealthy: 0.6
        case .hazardous: 0.7
        }
    }

    // MARK: - Spring Physics

    private static func springResponse(for level: AQILevel) -> Double {
        switch level {
        case .good: 0.35
        case .moderate: 0.45
        case .sensitive: 0.6
        case .unhealthy: 0.8
        case .veryUnhealthy: 1.2
        case .hazardous: 1.5
        }
    }

    private static func springDamping(for level: AQILevel) -> Double {
        switch level {
        case .good: 0.6
        case .moderate: 0.7
        case .sensitive: 0.8
        case .unhealthy: 0.88
        case .veryUnhealthy: 0.95
        case .hazardous: 1.0
        }
    }

    private static func springBounce(for level: AQILevel) -> Double {
        switch level {
        case .good: 0.2
        case .moderate: 0.1
        case .sensitive: 0.05
        case .unhealthy: 0.0
        case .veryUnhealthy: 0.0
        case .hazardous: 0.0
        }
    }

    // MARK: - Particle System

    private static func particleConfig(for level: AQILevel) -> ParticleConfig {
        switch level {
        case .good:
            ParticleConfig(
                birthRate: 2, maxParticles: 30,
                minSpeed: 5, maxSpeed: 10,
                minSize: 1.5, maxSize: 3,
                minOpacity: 0.12, maxOpacity: 0.2,
                colorRed: 1.0, colorGreen: 1.0, colorBlue: 1.0,
                wobbleAmount: 1.0
            )
        case .moderate:
            ParticleConfig(
                birthRate: 8, maxParticles: 60,
                minSpeed: 10, maxSpeed: 20,
                minSize: 1.5, maxSize: 3,
                minOpacity: 0.1, maxOpacity: 0.2,
                colorRed: 1.0, colorGreen: 0.95, colorBlue: 0.85,
                wobbleAmount: 0.7
            )
        case .sensitive:
            ParticleConfig(
                birthRate: 20, maxParticles: 120,
                minSpeed: 15, maxSpeed: 30,
                minSize: 2, maxSize: 4,
                minOpacity: 0.15, maxOpacity: 0.3,
                colorRed: 1.0, colorGreen: 0.8, colorBlue: 0.4,
                wobbleAmount: 0.5
            )
        case .unhealthy:
            ParticleConfig(
                birthRate: 40, maxParticles: 180,
                minSpeed: 20, maxSpeed: 40,
                minSize: 2.5, maxSize: 5,
                minOpacity: 0.2, maxOpacity: 0.4,
                colorRed: 1.0, colorGreen: 0.5, colorBlue: 0.2,
                wobbleAmount: 0.3
            )
        case .veryUnhealthy:
            ParticleConfig(
                birthRate: 70, maxParticles: 250,
                minSpeed: 25, maxSpeed: 50,
                minSize: 3, maxSize: 6,
                minOpacity: 0.3, maxOpacity: 0.5,
                colorRed: 0.7, colorGreen: 0.3, colorBlue: 0.7,
                wobbleAmount: 0.15
            )
        case .hazardous:
            ParticleConfig(
                birthRate: 100, maxParticles: 300,
                minSpeed: 30, maxSpeed: 60,
                minSize: 4, maxSize: 8,
                minOpacity: 0.4, maxOpacity: 0.7,
                colorRed: 0.8, colorGreen: 0.2, colorBlue: 0.2,
                wobbleAmount: 0.05
            )
        }
    }
}
