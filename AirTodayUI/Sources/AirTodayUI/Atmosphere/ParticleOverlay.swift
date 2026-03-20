import SwiftUI
import AirTodayCore

/// Airborne particle simulation rendered via Canvas + TimelineView.
/// At low AQI: sparse, slow, nearly invisible dust motes.
/// At high AQI: dense, agitated, thick smog streaming past.
public struct ParticleOverlay: View {
    let config: ParticleConfig
    let tier: RenderQuality.QualityTier
    @State private var system = ParticleSystem()
    @State private var canvasSize: CGSize = .zero

    public init(config: ParticleConfig, tier: RenderQuality.QualityTier) {
        self.config = config
        self.tier = tier
    }

    private var effectiveMaxParticles: Int {
        Int(Double(config.maxParticles) * tier.particleMultiplier)
    }

    private var frameInterval: Double {
        tier == .high ? 1.0 / 60.0 : 1.0 / 30.0
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            Canvas { context, size in
                guard !system.particles.isEmpty else { return }

                context.blendMode = .plusLighter

                let particleColor = Color(
                    red: config.colorRed,
                    green: config.colorGreen,
                    blue: config.colorBlue
                )

                for particle in system.particles {
                    let age = particle.maxLifetime - particle.lifetime
                    let fadeIn = min(1, age / 0.5)
                    let fadeOut = min(1, particle.lifetime / 1.0)
                    let alpha = particle.opacity * fadeIn * fadeOut

                    guard alpha > 0.01 else { continue }

                    let rect = CGRect(
                        x: particle.position.x - particle.size,
                        y: particle.position.y - particle.size,
                        width: particle.size * 2,
                        height: particle.size * 2
                    )

                    context.opacity = alpha
                    context.fill(
                        Circle().path(in: rect),
                        with: .color(particleColor)
                    )
                }
            }
            .onChange(of: timeline.date) { _, date in
                system.update(
                    date: date,
                    config: config,
                    maxParticles: effectiveMaxParticles,
                    bounds: canvasSize
                )
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                canvasSize = newSize
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Particle

struct Particle {
    var position: CGPoint
    var velocity: CGPoint
    var size: CGFloat
    var opacity: Double
    var lifetime: Double
    var maxLifetime: Double
    var phase: Double
}

// MARK: - Particle System

@MainActor
final class ParticleSystem {
    var particles: [Particle] = []
    private var lastUpdate: Date?
    private var spawnAccumulator: Double = 0

    func update(date: Date, config: ParticleConfig, maxParticles: Int, bounds: CGSize) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let dt: Double
        if let last = lastUpdate {
            dt = min(date.timeIntervalSince(last), 0.1) // Cap to avoid burst on resume
        } else {
            dt = 0
            // Seed initial particles on first frame (only if allowed)
            if maxParticles > 0 {
                let seedCount = min(maxParticles / 3, Int(config.birthRate * 2), maxParticles - particles.count)
                for _ in 0..<seedCount {
                    particles.append(Particle.random(in: bounds, config: config))
                }
            }
        }
        lastUpdate = date

        // Spawn new particles (only when under the cap)
        if maxParticles > 0 {
            spawnAccumulator += config.birthRate * dt
            let toSpawn = Int(spawnAccumulator)
            spawnAccumulator -= Double(toSpawn)

            for _ in 0..<toSpawn where particles.count < maxParticles {
                particles.append(Particle.random(in: bounds, config: config))
            }
        } else {
            // Tier dropped to zero — stop spawning, let existing particles die naturally
            spawnAccumulator = 0
        }

        // Update existing particles
        let time = date.timeIntervalSinceReferenceDate
        for i in particles.indices {
            // Drift
            particles[i].position.x += particles[i].velocity.x * dt
            particles[i].position.y += particles[i].velocity.y * dt

            // Wobble (sinusoidal horizontal oscillation)
            let wobbleOffset = sin(time * 1.5 + particles[i].phase) * config.wobbleAmount * 15 * dt
            particles[i].position.x += wobbleOffset

            // Age
            particles[i].lifetime -= dt
        }

        // Remove dead particles
        particles.removeAll { $0.lifetime <= 0 }
    }
}

// MARK: - Particle Factory

extension Particle {
    static func random(in bounds: CGSize, config: ParticleConfig) -> Particle {
        // Random position across the view
        let position = CGPoint(
            x: Double.random(in: 0...bounds.width),
            y: Double.random(in: 0...bounds.height)
        )

        // Upward drift with lateral variation (-60° to 60° from vertical)
        let angle = Double.random(in: -Double.pi / 3 ... Double.pi / 3)
        let speed = Double.random(in: config.minSpeed...max(config.minSpeed, config.maxSpeed))
        let velocity = CGPoint(
            x: sin(angle) * speed,
            y: -cos(angle) * speed // Negative = upward
        )

        let lifetime = Double.random(in: 5...10)

        return Particle(
            position: position,
            velocity: velocity,
            size: CGFloat.random(in: config.minSize...max(config.minSize, config.maxSize)),
            opacity: Double.random(in: config.minOpacity...max(config.minOpacity, config.maxOpacity)),
            lifetime: lifetime,
            maxLifetime: lifetime,
            phase: Double.random(in: 0 ... .pi * 2)
        )
    }
}
