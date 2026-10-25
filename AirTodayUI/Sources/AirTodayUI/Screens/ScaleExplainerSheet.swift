import SwiftUI
import AirTodayCore

/// What the big number means: the scale, its bands, and who publishes it.
/// Opened by tapping the number.
struct ScaleExplainerSheet: View {
    let scale: AQIScale
    let reading: ScaledReading
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: DS.spacingMD) {
                        Text("\(reading.value)")
                            .font(.system(size: 44, weight: .light, design: .rounded))
                            .monospacedDigit()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reading.band.longName)
                                .font(.headline)
                            if let dominant = reading.dominantPollutant {
                                Text("Driven by \(dominant.description)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, DS.spacingXS)
                    .accessibilityElement(children: .combine)
                } footer: {
                    Text("\(scale.caption). The number is the worst of the pollutants it measures.")
                }

                Section("Bands") {
                    ForEach(scale.bands, id: \.range) { item in
                        HStack(spacing: DS.spacingMD) {
                            Circle()
                                .fill(item.band.color)
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)
                            Text(item.band.longName)
                                .fontWeight(item.band.longName == reading.band.longName ? .semibold : .regular)
                            Spacer()
                            Text(item.range)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    Link(scale.authority.name, destination: scale.authority.url)
                } header: {
                    Text("Published by")
                } footer: {
                    Text("You can change the scale in Settings.")
                }
            }
            .navigationTitle(scale.shortName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
