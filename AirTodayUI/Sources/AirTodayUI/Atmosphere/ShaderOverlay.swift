import SwiftUI
import AirTodayCore

/// Metal shader overlay for atmospheric haze effect.
/// Uses a stitchable colorEffect shader from Atmosphere.metal in the app target.
public struct ShaderOverlay: View {
    let params: AtmosphereParameters
    @State private var startDate = Date.now

    public init(params: AtmosphereParameters) {
        self.params = params
    }

    public var body: some View {
        if params.hazeDensity > 0.01 {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let elapsed = Float(startDate.distance(to: timeline.date))

                Rectangle()
                    .fill(.clear)
                    .visualEffect { content, proxy in
                        content.colorEffect(
                            ShaderLibrary.hazeOverlay(
                                .float(elapsed),
                                .float(params.hazeDensity),
                                .float2(proxy.size)
                            )
                        )
                    }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
