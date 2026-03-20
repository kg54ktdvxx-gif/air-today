import SwiftUI
import AirTodayCore

/// First-launch onboarding — explains app purpose + requests location.
public struct OnboardingView: View {
    let locationService: LocationService
    let onComplete: () -> Void

    @State private var currentPage = 0

    public init(locationService: LocationService, onComplete: @escaping () -> Void) {
        self.locationService = locationService
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.20, blue: 0.30),
                    Color(red: 0.02, green: 0.08, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                featuresPage.tag(1)
                locationPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: DS.spacingXL + 4) {
            Spacer()

            Image(systemName: "aqi.medium")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.breathe)

            Text("Air Today")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)

            Text("Know when it's safe to be outside")
                .font(.title3)
                .foregroundStyle(.white.opacity(DS.opacitySecondary))
                .multilineTextAlignment(.center)

            Spacer()

            nextButton("Get Started") {
                withAnimation { currentPage = 1 }
            }
        }
        .padding(DS.spacingXXL)
    }

    // MARK: - Features

    private var featuresPage: some View {
        VStack(spacing: DS.spacingXXL) {
            Spacer()

            VStack(spacing: DS.spacingXL + 4) {
                featureRow(
                    icon: "sun.max.fill",
                    color: .green,
                    title: "Health Verdicts",
                    description: "Clear guidance on outdoor safety, not just numbers"
                )

                featureRow(
                    icon: "figure.run",
                    color: .blue,
                    title: "Activity Guidance",
                    description: "Per-activity recommendations for running, cycling, and more"
                )

                featureRow(
                    icon: "chart.xyaxis.line",
                    color: .orange,
                    title: "Forecast",
                    description: "9-day air quality forecast with improvement predictions"
                )

                featureRow(
                    icon: "map.fill",
                    color: .purple,
                    title: "Nearby Stations",
                    description: "See air quality at monitoring stations around you"
                )
            }

            Spacer()

            nextButton("Continue") {
                withAnimation { currentPage = 2 }
            }
        }
        .padding(DS.spacingXXL)
    }

    // MARK: - Location Permission

    private var locationPage: some View {
        VStack(spacing: DS.spacingXL + 4) {
            Spacer()

            Image(systemName: "location.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Enable Location")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)

            Text("Air Today needs your location to find the nearest monitoring station and show accurate local air quality data.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(DS.opacitySecondary))
                .multilineTextAlignment(.center)

            Text("Your location is only sent to the WAQI API — we never store or track it.")
                .font(.caption)
                .foregroundStyle(.white.opacity(DS.opacityTertiary))
                .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: DS.spacingMD) {
                nextButton("Enable Location") {
                    locationService.requestPermission()
                    onComplete()
                }

                Button("Skip for Now") {
                    onComplete()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(DS.opacitySecondary))
            }
        }
        .padding(DS.spacingXXL)
    }

    // MARK: - Helpers

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(spacing: DS.spacingLG) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: DS.iconLG)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(DS.opacitySecondary))
            }

            Spacer()
        }
    }

    private func nextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.spacingLG)
                .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.35)))
        }
    }
}
