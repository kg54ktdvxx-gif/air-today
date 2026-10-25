import SwiftUI

/// In-app privacy policy display.
public struct PrivacyPolicyView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.spacingXL) {
                Text("Privacy Policy")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                Text("Last updated: October 25, 2026")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(DS.opacityTertiary))

                policySection(
                    "Location",
                    "When you allow it, Air Today uses your location (on your iPhone, and on your Apple Watch " +
                    "if you use the Watch app) to show the air where you are. The coordinates are sent " +
                    "directly to two services to fetch data: the World Air Quality Index (WAQI) for nearby " +
                    "station measurements, and Open-Meteo for estimates, forecasts and weather (rounded to " +
                    "about 1 km; Open-Meteo keeps request logs for up to 90 days). Your device " +
                    "also asks Apple Maps for the name of your town, under Apple's privacy policy. The " +
                    "coordinates are not sent anywhere else.\n\n" +
                    "If you don't allow location access, WAQI estimates your area from your internet " +
                    "connection's IP address, and Open-Meteo is asked about that area. The coordinates of " +
                    "your last check are kept on your device so widgets and background updates can stay current."
                )

                policySection(
                    "Your Health Profile",
                    "The optional answers about asthma, ozone sensitivity and children are stored only on " +
                    "your device (and your paired Apple Watch). They tailor the advice the app shows and are " +
                    "never sent to WAQI, Open-Meteo or any other server."
                )

                policySection(
                    "Saved Locations & Settings",
                    "Places you save and your settings are stored on your device using App Groups, shared " +
                    "between the app, its widgets and its Apple Watch app. They never leave your devices."
                )

                policySection(
                    "Notifications",
                    "Alerts and the daily verdict are created on your device from air quality data the app " +
                    "has fetched. Air Today doesn't use a push notification server."
                )

                policySection(
                    "Widgets & Complications",
                    "Widgets and Watch complications read data stored on your device. When that data is more " +
                    "than an hour old, they request a fresh reading the same way the app does."
                )

                policySection(
                    "Apple Watch",
                    "Your iPhone sends its latest reading and your settings to your Apple Watch using Apple's " +
                    "WatchConnectivity, directly between your devices."
                )

                policySection(
                    "Siri & Shortcuts",
                    "When you ask Siri about the air, Air Today answers using the same data as the app. Siri " +
                    "requests are handled by Apple under Apple's privacy policy."
                )

                policySection(
                    "Data Sources",
                    "Station measurements come from the World Air Quality Index project (waqi.info) and its " +
                    "network of monitoring stations worldwide. Estimates, forecasts and weather come from " +
                    "Open-Meteo (open-meteo.com), whose air quality data comes from the Copernicus Atmosphere " +
                    "Monitoring Service (CAMS). Air Today does not operate any monitoring stations or servers."
                )

                policySection(
                    "Analytics & Tracking",
                    "Air Today does not include any analytics SDKs, crash reporters, or advertising " +
                    "frameworks. We do not track your usage or collect device identifiers, and nothing is " +
                    "shared beyond the requests described above."
                )

                policySection(
                    "Contact",
                    "If you have questions about this privacy policy, contact us at busiest-21.qualm@icloud.com."
                )
            }
            .padding(DS.spacingLG)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func policySection(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: DS.spacingSM) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(DS.opacitySecondary))
        }
    }
}
