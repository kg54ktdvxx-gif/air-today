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

                Text("Last updated: March 12, 2026")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(DS.opacityTertiary))

                policySection(
                    "What We Collect",
                    "Air Today uses your device's location (when you grant permission) to find the nearest " +
                    "air quality monitoring station. Your location is sent directly to the World Air Quality " +
                    "Index (WAQI) API to retrieve local air quality data. We do not store, log, or transmit " +
                    "your location to any other service.\n\n" +
                    "If you deny location access, the app falls back to IP-based geolocation through the " +
                    "WAQI API, which provides approximate (city-level) location only."
                )

                policySection(
                    "Data Sources",
                    "All air quality data is provided by the World Air Quality Index project (waqi.info) " +
                    "and its network of monitoring stations worldwide. Air Today does not operate any " +
                    "monitoring stations."
                )

                policySection(
                    "Saved Locations",
                    "Locations you save are stored locally on your device using App Groups (shared between " +
                    "the app and its widgets). This data never leaves your device."
                )

                policySection(
                    "Analytics & Tracking",
                    "Air Today does not include any analytics SDKs, crash reporters, or advertising " +
                    "frameworks. We do not track your usage, collect device identifiers, or share data " +
                    "with third parties."
                )

                policySection(
                    "Widgets & Live Activities",
                    "Widgets and Live Activities read cached air quality data stored in a shared App Group " +
                    "container on your device. No network requests are made from widgets directly."
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
