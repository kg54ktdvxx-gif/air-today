import SwiftUI
import AirTodayCore

/// UV Index display row for the conditions card.
public struct UVIndexRow: View {
    let uvIndex: Int

    public init(uvIndex: Int) {
        self.uvIndex = uvIndex
    }

    public var body: some View {
        HStack(spacing: DS.spacingSM) {
            Image(systemName: "sun.max.trianglebadge.exclamationmark")
                .font(.title3)
                .foregroundStyle(uvColor)
                .frame(width: DS.iconMD)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.spacingXS + 2) {
                    Text("\(uvIndex)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(riskLevel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(uvColor)
                }
                Text("UV Index")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(DS.opacityTertiary))
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("UV Index: \(uvIndex), \(riskLevel)")
    }

    private var riskLevel: String {
        switch uvIndex {
        case 0...2: "Low"
        case 3...5: "Moderate"
        case 6...7: "High"
        case 8...10: "Very High"
        default: "Extreme"
        }
    }

    private var uvColor: Color {
        switch uvIndex {
        case 0...2: .green
        case 3...5: .yellow
        case 6...7: .orange
        case 8...10: .red
        default: .purple
        }
    }
}
