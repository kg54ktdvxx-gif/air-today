import SwiftUI
import AirTodayCore

/// How the verdict and activity advice are worked out, and where the guidance and
/// data come from.
struct AdviceInfoSheet: View {
    let scale: AQIScale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("How the advice works") {
                    Text("The verdict and activity advice follow the scale you've chosen, \(scale.shortName). Each of its bands is matched to the US EPA's activity guidance by what its publisher advises — for example, the European index's Good and Fair both mean usual activity for everyone.")
                    Text("Your health answers make the advice stricter: asthma or another respiratory condition for every activity, ozone sensitivity for running and cycling while ozone is up, and children for the playground.")
                    Text("Best times come from the hourly forecast: the cleanest two hours of daylight left in the day.")
                }

                Section("Guidance") {
                    ForEach(AQIScale.allCases, id: \.self) { scale in
                        Link(scale.authority.name, destination: scale.authority.url)
                    }
                }

                Section {
                    Link("World Air Quality Index Project", destination: URL(string: "https://waqi.info")!)
                    Link("Open-Meteo", destination: URL(string: "https://open-meteo.com")!)
                    Link("Copernicus Atmosphere Monitoring Service", destination: URL(string: "https://atmosphere.copernicus.eu")!)
                } header: {
                    Text("Data")
                } footer: {
                    Text("Measurements come from monitoring stations via the World Air Quality Index Project. Estimates and forecasts come from CAMS, through Open-Meteo, which also supplies the weather. A station's reading is shown when it's under 2 hours old and within 20 km; otherwise the estimate is.")
                }

                Section {
                    Text("General guidance, not medical advice. If you have a health condition, follow your doctor's advice.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About This Advice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
