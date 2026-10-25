import SwiftUI
import AirTodayCore

/// Single pollutant display row with name, sub-index on the chosen scale, and band indicator.
public struct PollutantRow: View {
    let pollutant: Pollutant
    let scale: AQIScale

    public init(pollutant: Pollutant, scale: AQIScale = .usEPA) {
        self.pollutant = pollutant
        self.scale = scale
    }

    private var subIndex: Double {
        scale.subIndex(for: pollutant.kind, epaAQI: pollutant.aqi) ?? pollutant.aqi
    }

    public var body: some View {
        let band = scale.band(forValue: subIndex)

        HStack {
            Text(pollutant.kind.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 55, alignment: .leading)

            Text(pollutant.kind.description)
                .font(.caption)
                .foregroundStyle(.white.opacity(DS.opacitySecondary))
                .lineLimit(1)

            Spacer()

            Text("\(Int(subIndex.rounded()))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)

            Circle()
                .fill(band.color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        }
        .padding(.vertical, DS.spacingXS + 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pollutant.kind.description): \(Int(subIndex.rounded())), \(band.longName)")
    }
}
