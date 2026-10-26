import SwiftUI
import AirTodayCore

/// Credits for the data on the page, which the WAQI terms and Open-Meteo's
/// CC BY 4.0 licence both require next to it.
public struct AttributionView: View {
    /// The reporting station's sources, from WAQI.
    let attributions: [Attribution]
    /// Whether the page shows model data (estimate, forecast, EU/UK index or weather).
    let showsModelData: Bool

    public init(attributions: [Attribution], showsModelData: Bool) {
        self.attributions = attributions
        self.showsModelData = showsModelData
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text("Data provided by")
                .font(DS.Typeface.fine)
                .foregroundStyle(.white.opacity(DS.opacityTertiary))

            ForEach(attributions) { attribution in
                credit(attribution.name, url: URL(string: attribution.url))
            }
            // WAQI usually lists itself among a station's sources; credit it once either way.
            if !attributions.isEmpty, !attributions.contains(where: { $0.url.contains("waqi.info") }) {
                credit("World Air Quality Index Project", url: URL(string: "https://waqi.info"))
            }
            if showsModelData {
                credit("Air quality and weather data by Open-Meteo.com (CC BY 4.0)", url: URL(string: "https://open-meteo.com"))
                Text("Contains modified Copernicus Atmosphere Monitoring Service information \(Self.year)")
                    .font(DS.Typeface.fine)
                    .foregroundStyle(.white.opacity(DS.opacityTertiary))
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func credit(_ name: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                Text(name)
                    .font(DS.Typeface.fine)
                    .foregroundStyle(.white.opacity(DS.opacitySecondary))
                    .multilineTextAlignment(.center)
                    // Small print, but a full-size tap target.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
    }

    private static var year: String {
        String(Calendar(identifier: .gregorian).component(.year, from: Date()))
    }
}
