import SwiftUI
import AirTodayCore

/// Single pollutant display row with name, sub-index on the chosen scale, and band indicator.
public struct PollutantRow: View {
    let kind: Pollutant.Kind
    /// The pollutant's index on `scale`.
    let value: Int
    let scale: AQIScale

    public init(kind: Pollutant.Kind, value: Int, scale: AQIScale) {
        self.kind = kind
        self.value = value
        self.scale = scale
    }

    public var body: some View {
        let band = scale.band(forValue: value)

        HStack {
            Text(kind.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 55, alignment: .leading)

            Text(kind.description)
                .font(.caption)
                .foregroundStyle(.white.opacity(DS.opacitySecondary))
                .lineLimit(1)

            Spacer()

            Text("\(value)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)

            Circle()
                .fill(band.color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        }
        .padding(.vertical, DS.spacingXS + 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.description): \(value), \(band.longName)")
    }
}
