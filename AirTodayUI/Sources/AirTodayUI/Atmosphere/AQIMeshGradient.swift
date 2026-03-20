import SwiftUI
import AirTodayCore

/// Animated 3×3 MeshGradient that morphs based on AQI level.
/// Interior points drift with organic sin/cos motion; colors transition smoothly on AQI change.
public struct AQIMeshGradient: View {
    let params: AtmosphereParameters

    public init(params: AtmosphereParameters) {
        self.params = params
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            MeshGradient(
                width: 3,
                height: 3,
                points: animatedPoints(time: t),
                colors: params.meshColors,
                smoothsColors: true
            )
        }
        .animation(.easeInOut(duration: 1.5), value: params.meshColors)
        .ignoresSafeArea()
    }

    /// Edge points stay pinned, interior points drift organically.
    private func animatedPoints(time: Double) -> [SIMD2<Float>] {
        let t = Float(time)
        let speed: Float = 0.08  // Slow, ambient drift
        let amplitude: Float = 0.06

        // 3×3 grid — edge points fixed, center point + mid-edge points drift
        return [
            // Row 0 (top edge — fixed)
            SIMD2(0.0, 0.0),
            SIMD2(0.5 + sin(t * speed * 1.1) * amplitude * 0.5, 0.0),
            SIMD2(1.0, 0.0),

            // Row 1 (middle — interior points drift)
            SIMD2(0.0, 0.5 + sin(t * speed * 0.9) * amplitude * 0.5),
            SIMD2(
                0.5 + sin(t * speed) * amplitude,
                0.5 + cos(t * speed * 0.7) * amplitude
            ),
            SIMD2(1.0, 0.5 + cos(t * speed * 1.2) * amplitude * 0.5),

            // Row 2 (bottom edge — fixed)
            SIMD2(0.0, 1.0),
            SIMD2(0.5 + cos(t * speed * 0.8) * amplitude * 0.5, 1.0),
            SIMD2(1.0, 1.0),
        ]
    }
}

#Preview("Good AQI") {
    AQIMeshGradient(params: .placeholder)
}
