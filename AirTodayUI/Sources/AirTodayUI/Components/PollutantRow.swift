import SwiftUI
import AirTodayCore

/// Single pollutant display row with name, AQI sub-index, and level indicator.
public struct PollutantRow: View {
    let pollutant: Pollutant

    public init(pollutant: Pollutant) {
        self.pollutant = pollutant
    }

    public var body: some View {
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

            let level = AQILevel(aqi: Int(pollutant.aqi))
            Text("\(Int(pollutant.aqi))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)

            Circle()
                .fill(level.color)
                .frame(width: 10, height: 10)
                .accessibilityLabel(level.label)
        }
        .padding(.vertical, DS.spacingXS + 2)
    }
}
