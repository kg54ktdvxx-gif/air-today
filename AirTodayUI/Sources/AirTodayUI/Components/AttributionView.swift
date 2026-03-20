import SwiftUI
import AirTodayCore

/// WAQI attribution display — required by Terms of Service.
public struct AttributionView: View {
    let attributions: [Attribution]

    public init(attributions: [Attribution]) {
        self.attributions = attributions
    }

    public var body: some View {
        VStack(spacing: DS.spacingXS) {
            Text("Data provided by")
                .font(.caption2)
                .foregroundStyle(.white.opacity(DS.opacityTertiary))

            ForEach(attributions) { attribution in
                Link(attribution.name, destination: URL(string: attribution.url) ?? URL(string: "https://waqi.info")!)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(DS.opacitySecondary))
            }
        }
    }
}
